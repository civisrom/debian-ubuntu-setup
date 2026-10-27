#!/usr/bin/env python3
"""Run the real helper against synthetic commands; never touch host firewall."""
import json
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
APPLY = (ROOT / 'config/nft-apply.sh').read_text()
INSTALLER = (ROOT / 'install-nft-docker-watch.sh').read_text()

NFT = r'''#!/usr/bin/python3
import json, os, pathlib, sys
p = pathlib.Path(os.environ['FIXTURE'])
a = sys.argv[1:]
mode = os.environ.get('FAILURE', '')
with (p / 'calls').open('a') as f: f.write(' '.join(a) + '\n')
if '-c' in a:
    sys.exit(1 if mode == 'invalid' or (mode == 'rollback-check' and 'rollback.' in a[-1]) else 0)
if '-e' in a:
    if mode == 'apply': sys.exit(1)
    expected = json.loads((p / 'expected').read_text())
    actual = json.loads(json.dumps(expected))
    if mode in ('missing', 'rollback-check'): actual = actual[:1]
    if mode == 'policy': actual[-1]['chain']['policy'] = 'accept'
    (p / 'runtime').write_text(json.dumps({'nftables': actual}))
    print('bad json' if mode == 'echo' else json.dumps({'nftables': [{'add': x} for x in expected]}))
elif '-f' in a:
    (p / 'runtime').write_text('restored')
elif a == ['list', 'ruleset']:
    print('table inet before {\n chain input { type filter hook input priority 0; policy drop; }\n}')
elif a == ['-j', 'list', 'ruleset']:
    if mode == 'read': sys.exit(1)
    print((p / 'runtime').read_text())
else:
    sys.exit(1)
'''


class NftWatchTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='nft-watch-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        for name, body in {'nft': NFT, 'docker': '#!/bin/sh\nexit 0\n',
                           'systemd-cat': '#!/bin/sh\ncat >/dev/null\n'}.items():
            path = self.bin / name
            path.write_text(body)
            path.chmod(0o755)
        (self.root / 'config').write_text('table inet fixture {}\n')
        self.script = self.root / 'apply.sh'
        self.script.write_text(APPLY.replace('/run/lock/nft-docker-watch.lock', str(self.root / 'lock')))

    def run_apply(self, expected, failure=''):
        (self.root / 'expected').write_text(json.dumps(expected))
        (self.root / 'runtime').write_text('original')
        (self.root / 'calls').write_text('')
        env = {'PATH': f'{self.bin}:/usr/bin:/bin', 'FIXTURE': str(self.root),
               'FAILURE': failure, 'NFT_CONF': str(self.root / 'config'),
               'NFT_BACKUP_DIR': str(self.root / 'backups'), 'DOCKER_SETTLE_DELAY': '0'}
        return subprocess.run(['bash', str(self.script)], env=env,
                              capture_output=True, text=True, timeout=10)

    @staticmethod
    def profile(family='inet', name='custom'):
        return [{'table': {'family': family, 'name': name}},
                {'chain': {'family': family, 'table': name, 'name': 'input',
                           'type': 'filter', 'hook': 'input', 'prio': 0, 'policy': 'drop'}}]

    def test_custom_inet_and_relay_profiles(self):
        for expected in (self.profile(), self.profile('ip', 'filter') +
                         [{'table': {'family': 'ip', 'name': 'relay_nat'}}] + self.profile('ip6', 'filter')):
            with self.subTest(expected=expected):
                result = self.run_apply(expected)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertNotEqual((self.root / 'runtime').read_text(), 'restored')
                backups = self.root / 'backups'
                self.assertEqual(backups.stat().st_mode & 0o777, 0o700)
                self.assertTrue(all(p.name.startswith('ruleset-') for p in backups.iterdir()))
                self.assertTrue(all(p.stat().st_mode & 0o777 == 0o600 for p in backups.iterdir()))

    def test_missing_changed_or_unreadable_ruleset_rolls_back(self):
        for mode in ('missing', 'policy', 'echo', 'read', 'apply'):
            with self.subTest(mode=mode):
                result = self.run_apply(self.profile(), mode)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual((self.root / 'runtime').read_text(), 'restored')

    def test_empty_firewall_rolls_back(self):
        result = self.run_apply([])
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.root / 'runtime').read_text(), 'restored')

    def test_invalid_config_never_changes_live_rules(self):
        result = self.run_apply(self.profile(), 'invalid')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.root / 'runtime').read_text(), 'original')

    def test_invalid_rollback_is_never_applied(self):
        result = self.run_apply(self.profile(), 'rollback-check')
        self.assertNotEqual(result.returncode, 0)
        self.assertNotEqual((self.root / 'runtime').read_text(), 'restored')
        self.assertIn('CRITICAL: postcondition failed and rollback failed', result.stdout)

    def test_local_apply_script_install_returns_success(self):
        body = re.search(r'(?ms)^create_apply_script\(\) \{\n.*?^\}$', INSTALLER)[0]
        command = '''set -euo pipefail
INSTALLER_DIR=$1 NFT_APPLY_SCRIPT=$2
NFT_APPLY_SHA256=$(sha256sum "$1/config/nft-apply.sh" | awk '{print $1}')
log_info() { :; }
log_error() { printf '%s\n' "$*" >&2; }
install() { cp "${@: -2:1}" "${@: -1}"; }
''' + body + '\ncreate_apply_script\n'
        result = subprocess.run(['bash', '-c', command, 'test', str(ROOT), str(self.root / 'installed')],
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.root / 'installed').read_bytes(), (ROOT / 'config/nft-apply.sh').read_bytes())


if __name__ == '__main__':
    unittest.main()
