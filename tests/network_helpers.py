#!/usr/bin/env python3
"""Regression tests for network helpers, using only synthetic files and commands."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import time
import types
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


def module(name, source):
    spec = importlib.util.spec_from_file_location(name, source)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


ssh = module('telegram_audit', ROOT / 'config/telegram-ssh-tunnel.py')
watch = module('nft_watch_audit_fixture', ROOT / 'tests/nft_watch.py')
node_sets = module('node_sets_audit', ROOT / 'config/nft-node-sets.py')


class NftMapTests(unittest.TestCase):
    def test_existing_incompatible_map_is_rejected_before_mutation(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'nftables.conf'
            path.write_text('table ip6 filter {\n}\n')
            def nft(args, data=None, check=True):
                if args[:3] == ['-j', 'list', 'set']:
                    return types.SimpleNamespace(returncode=1)
                if args[:3] == ['-j', 'list', 'map']:
                    return types.SimpleNamespace(returncode=0, stdout=json.dumps({'nftables': [
                        {'map': {'name': 'egress6_snat', 'type': 'ipv4_addr', 'map': 'ipv4_addr'}}]}))
                raise AssertionError('Attempted mutation before validating existing map')
            with patch.object(node_sets, 'trusted'), patch.object(node_sets, 'nft', side_effect=nft), \
                    self.assertRaises(ValueError):
                node_sets.ensure(path)
            self.assertEqual(path.read_text(), 'table ip6 filter {\n}\n')


class TelegramAuditTests(unittest.TestCase):
    def test_relay_host_rejects_scoped_ipv6_and_config_injection(self):
        for value in ('fe80::1%eth0', 'fe80::1%eth0\nProxyCommand false',
                      'fe80::1%eth0 extra', 'relay.example\nProxyCommand false'):
            with self.subTest(value=value), self.assertRaises(argparse.ArgumentTypeError):
                ssh.host(value)
        for value in ('relay.example', '11.77.0.1', '2606:4700:4700::1111'):
            self.assertEqual(ssh.host(value), value)

    def fixture(self, root):
        (root / 'scripts').mkdir()
        (root / 'scripts/protocol_modules.py').touch()
        real_stat = Path.stat

        def root_stat(path, *args, **kwargs):
            result = real_stat(path, *args, **kwargs)
            if path == root:
                fields = list(result)
                fields[4] = 0
                return os.stat_result(fields)
            return result

        self.enterContext(patch.object(ssh, 'safe_dir'))
        self.enterContext(patch.object(Path, 'stat', root_stat))
        self.enterContext(patch.object(ssh, 'bot_proxy_active', return_value=False))

    def test_metadata_failure_does_not_change_override(self):
        for existed in (False, True):
            with self.subTest(existed=existed), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                self.fixture(root)
                target = root / 'override.env'
                if existed:
                    target.write_text('# synthetic previous override\n')
                with patch.object(ssh, 'run', side_effect=RuntimeError('synthetic hostname failure')):
                    with self.assertRaises(RuntimeError):
                        ssh.attach_bot(str(root))
                self.assertEqual(target.exists(), existed)
                if existed:
                    self.assertEqual(target.read_text(), '# synthetic previous override\n')

    def test_failed_recreate_removes_new_override(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root)
            replies = [types.SimpleNamespace(returncode=0, stdout='11.77.0.1\n'),
                       types.SimpleNamespace(returncode=0, stdout='synthetic-version\n'),
                       RuntimeError('synthetic compose failure'),
                       types.SimpleNamespace(returncode=0, stdout='')]
            with patch.object(ssh, 'run', side_effect=replies):
                with self.assertRaises(RuntimeError):
                    ssh.attach_bot(str(root))
            self.assertFalse((root / 'override.env').exists())


class NftSignalTests(unittest.TestCase):
    setUp = watch.NftWatchTests.setUp
    run_apply = watch.NftWatchTests.run_apply
    profile = staticmethod(watch.NftWatchTests.profile)

    def signal_script(self):
        self.script.write_text(self.script.read_text().replace('umask 077', 'umask 077\nexport MAIN_PID=$$'))

    def test_hung_docker_is_bounded_and_firewall_still_applies(self):
        self.script.write_text(self.script.read_text().replace('DOCKER_WAIT_TIMEOUT:-60', 'DOCKER_WAIT_TIMEOUT:-1'))
        (self.bin / 'docker').write_text('#!/bin/sh\nexec sleep 30\n')
        started = time.monotonic()
        result = self.run_apply(self.profile())
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertLess(time.monotonic() - started, 5)
        self.assertIn('applying rules without it', result.stdout)
        self.assertNotEqual((self.root / 'runtime').read_text(), 'original')

    def test_term_before_apply_exits_without_touching_firewall(self):
        self.signal_script()
        (self.bin / 'docker').write_text('''#!/usr/bin/python3
import os, pathlib, signal
marker = pathlib.Path(os.environ['FIXTURE']) / 'signalled'
if not marker.exists():
    marker.touch()
    os.kill(int(os.environ['MAIN_PID']), signal.SIGTERM)
''')
        result = self.run_apply(self.profile())
        self.assertEqual(result.returncode, 143, result.stdout + result.stderr)
        self.assertEqual((self.root / 'calls').read_text(), '')
        self.assertEqual((self.root / 'runtime').read_text(), 'original')

    def test_term_after_apply_restores_snapshot_and_exits(self):
        self.signal_script()
        nft = self.bin / 'nft'
        nft.write_text(nft.read_text().replace('import json, os, pathlib, sys',
                                               'import json, os, pathlib, signal, sys').replace(
            "    print('bad json'", "    os.kill(int(os.environ['MAIN_PID']), signal.SIGTERM)\n    print('bad json'"))
        result = self.run_apply(self.profile())
        self.assertEqual(result.returncode, 143, result.stdout + result.stderr)
        self.assertEqual((self.root / 'runtime').read_text(), 'restored')
        self.assertNotIn('-j list ruleset', (self.root / 'calls').read_text())
        self.assertTrue(all(p.name.startswith('ruleset-') for p in (self.root / 'backups').iterdir()))


if __name__ == '__main__':
    unittest.main()
