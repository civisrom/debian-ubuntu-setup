#!/usr/bin/env python3
"""Node address validation and SSH rollback, using synthetic data only."""
import importlib.util
from pathlib import Path
import tempfile
import types
import argparse
import json
import os
import unittest
from unittest.mock import patch


def module(name):
    path = Path(__file__).resolve().parents[1] / 'config' / (name + '.py')
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


nft = module('nft-ipv6-profile')
ssh = module('telegram-ssh-tunnel')
PROFILE = '''table ip6 filter {
    chain input {
        type filter hook input priority 0; policy drop;
    }
    chain forward {
        type filter hook forward priority 0; policy drop;
    }
    set egress6_reserved {
        type ipv6_addr; flags interval;
        elements = { 2001::/23, 2001:db8::/32 };
    }
}
'''


class NodeSetup(unittest.TestCase):
    def test_attach_repairs_file_written_before_interrupted_recreate(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root/'scripts').mkdir()
            (root/'scripts/protocol_modules.py').touch()
            (root/'override.env').write_text('\nTELEGRAM_PROXY=socks5h://10.10.0.1:10890\n')
            reply = types.SimpleNamespace(returncode=0, stdout='synthetic')
            real_stat = Path.stat
            def root_stat(path, *args, **kwargs):
                result = real_stat(path, *args, **kwargs)
                if path == root:
                    fields = list(result)
                    fields[4] = 0
                    return os.stat_result(fields)
                return result
            with patch.object(ssh, 'safe_dir'), patch.object(ssh, 'run', return_value=reply) as commands, \
                 patch.object(ssh, 'bot_proxy_active', side_effect=[False, True]), \
                 patch.object(Path, 'stat', root_stat):
                ssh.attach_bot(str(root))
            self.assertTrue(any('--force-recreate' in call.args[0] for call in commands.call_args_list))

    def test_active_proxy_checks_both_containers_without_reading_environment(self):
        replies = [types.SimpleNamespace(returncode=0, stdout='a'*64+'\n'+'b'*64+'\n'),
                   types.SimpleNamespace(returncode=0, stdout=''),
                   types.SimpleNamespace(returncode=1, stdout='')]
        with patch.object(ssh, 'run', side_effect=replies) as commands:
            self.assertFalse(ssh.bot_proxy_active(Path('/root/synthetic-bot')))
        self.assertEqual(len(commands.call_args_list), 3)
        for call in commands.call_args_list[1:]:
            self.assertIn('test "$TELEGRAM_PROXY" =', call.args[0][-1])

    def test_ipv6_rejects_iproute_boolean_unstable_flags(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root/'source.nft').write_text(PROFILE)
            for flag in ('tentative', 'dadfailed', 'temporary', 'deprecated'):
                addresses = [{'addr_info': [{'local': '2606:4700:4700::1111', 'scope': 'global', flag: True}]}]
                argv = ['profile', str(root/'source.nft'), str(root/'output.nft'),
                        '--public-ipv6', '2606:4700:4700::1111', '--interface', 'eth0']
                with self.subTest(flag=flag), patch.object(nft.sys, 'argv', argv), \
                     patch.object(nft.subprocess, 'check_output', return_value=json.dumps(addresses)), \
                     self.assertRaises(ValueError):
                    nft.main()
                self.assertFalse((root/'output.nft').exists())

    def test_relay_source_rejects_multicast_and_scoped_addresses(self):
        for value in ['224.0.0.1', 'ff0e::1', '2606:4700::1%eth0']:
            with self.subTest(value=value), self.assertRaises(argparse.ArgumentTypeError):
                ssh.source(value)

    def test_safe_directory_rejects_writable_ancestor(self):
        with tempfile.TemporaryDirectory() as directory:
            parent = Path(directory)
            parent.chmod(0o777)
            child = parent/'root-owned'
            child.mkdir(mode=0o755)
            with patch.object(ssh.os, 'geteuid', return_value=0), self.assertRaises(ValueError):
                ssh.safe_dir(child)

    def test_account_cannot_repurpose_an_existing_service(self):
        existing = types.SimpleNamespace(pw_uid=33, pw_shell='/usr/sbin/nologin', pw_dir='/var/www')
        with patch.object(ssh.pwd, 'getpwnam', return_value=existing), self.assertRaises(ValueError):
            ssh.account('web-service', '/nonexistent')

    def test_ipv6_creates_missing_sets_and_preserves_rules(self):
        result = nft.prepare(PROFILE, '2606:4700:4700::1111', ['2620:fe::fe'], ['fe80::1'])
        for name in nft.SETS:
            self.assertEqual(result.count(' '+name+' {'), 1)
        self.assertIn('fd42:7662:6::9 : 2606:4700:4700::1111', result)
        self.assertIn('elements = { 2620:fe::fe }', result)
        self.assertIn('elements = { fe80::1 }', result)
        self.assertIn('elements = { 2001::/23, 2001:db8::/32 };', result)
        self.assertEqual(result.count('policy drop;'), 2)

    def test_ipv6_idempotent_empty_sources(self):
        first = nft.prepare(PROFILE, '2606:4700:4700::1111', [], [])
        self.assertEqual(first, nft.prepare(first, '2606:4700:4700::1111', [], []))
        self.assertNotIn('2001:db8:1::10', first)

    def test_minimal_node_uses_assigned_address_without_container_snat(self):
        profile = '# VPNBOT_MANAGED_NODE_HOST\n'+PROFILE
        first = nft.prepare(profile, '2606:4700:4700::1111', ['2620:fe::fe'], [])
        self.assertNotIn('egress6_snat', first)
        self.assertIn('elements = { 2606:4700:4700::1111 }', first)
        self.assertIn('elements = { 2620:fe::fe }', first)
        self.assertEqual(first, nft.prepare(first, '2606:4700:4700::1111', ['2620:fe::fe'], []))

    def test_ipv6_rejects_non_public_and_injection(self):
        for value in ['127.0.0.1', '::', '::1', 'fc00::1', 'fe80::1', 'ff02::1',
                      '2001:db8::1', '2606:4700::1/64', '2606:4700::1%eth0',
                      '2606:4700::1 }; accept', 'example.com']:
            with self.subTest(value=value), self.assertRaises(ValueError):
                nft.prepare(PROFILE, value, [], [])

    def test_ipv6_router_requires_link_local(self):
        for value in ['2606:4700::1', '::1', 'fe80::1%eth0', 'ff02::1']:
            with self.subTest(value=value), self.assertRaises(ValueError):
                nft.prepare(PROFILE, routers=[value])

    def test_ipv6_refuses_unprotected_profile(self):
        for text in ['', PROFILE.replace('policy drop;', 'policy accept;')]:
            with self.assertRaises(ValueError):
                nft.prepare(text)

    def test_ssh_validation_failure_restores_authorized_key_and_dropin(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            auth = root / 'authorized_keys_vpb-test'
            dropin = root / 'tunnel-vpb-test.conf'
            auth.write_text('previous synthetic public authorization\n')
            dropin.write_text('# previous SSH settings\n')
            with patch.object(ssh, 'CONF', root), patch.object(ssh, 'DROPIN', root/'tunnel.conf'), \
                 patch.object(ssh, 'safe_dir'), patch.object(ssh, 'run', side_effect=RuntimeError('synthetic validation failure')):
                with self.assertRaises(RuntimeError):
                    ssh.configure_sshd('vpb-test', '11.77.0.2', 'ssh-ed25519 synthetic')
            self.assertEqual(dropin.read_text(), '# previous SSH settings\n')
            self.assertEqual(auth.read_text(), 'previous synthetic public authorization\n')

    def test_ssh_new_failed_install_removes_both_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with patch.object(ssh, 'CONF', root), patch.object(ssh, 'DROPIN', root/'tunnel.conf'), \
                 patch.object(ssh, 'safe_dir'), patch.object(ssh, 'run', side_effect=RuntimeError('synthetic failure')):
                with self.assertRaises(RuntimeError):
                    ssh.configure_sshd('vpb-test', '11.77.0.2', 'ssh-ed25519 synthetic')
            self.assertEqual(list(root.iterdir()), [])

    def test_node_bad_bot_path_rejected_before_key_or_config_changes(self):
        args = types.SimpleNamespace(bot_dir='/root/vpnbot/../other', host_key_file='synthetic.pub')
        with patch.object(ssh.shutil, 'which', return_value='/usr/bin/synthetic'), \
             patch.object(ssh, 'public_key', return_value='ssh-ed25519 synthetic'), \
             patch.object(ssh, 'prepare_key', side_effect=AssertionError('mutated before validation')):
            with self.assertRaises(ValueError):
                ssh.node(args)


if __name__ == '__main__':
    unittest.main()
