#!/usr/bin/env python3
"""Exercise account routing in disposable homes without credentials or network."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class GhxTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='ghx-fixture-')
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        config = self.home / '.config'
        config.mkdir()
        (config / 'github-repos.tsv').write_text(
            'fixture fixture-account fixture-host allowed GITHUB_TOKEN_FIXTURE\n')
        self.repo = self.home / 'codex_project' / 'fixture'
        self.repo.mkdir(parents=True)
        self.env = {'HOME': str(self.home), 'PATH': '/usr/bin:/bin', 'LANG': 'C',
                    'GIT_CONFIG_NOSYSTEM': '1', 'GIT_CONFIG_GLOBAL': '/dev/null'}
        self.git('init', '-q')

    def git(self, *args, check=True):
        return subprocess.run(['git', *args], cwd=self.repo, env=self.env,
                              check=check, capture_output=True, text=True, timeout=10)

    def ghx(self, *args):
        return subprocess.run([sys.executable, str(ROOT / 'config/ghx'), *args],
                              cwd=self.repo, env=self.env, capture_output=True,
                              text=True, timeout=10)

    def test_remote_replaces_all_stale_push_destinations(self):
        self.git('remote', 'add', 'origin', 'git@old-fixture:old/fixture.git')
        for url in ('git@old-fixture:old/push-one.git', 'git@old-fixture:old/push-two.git'):
            self.git('config', '--add', 'remote.origin.pushurl', url)
        result = self.ghx('remote', 'fixture', 'allowed')
        self.assertEqual(result.returncode, 0, result.stderr)
        expected = 'git@fixture-host:fixture-account/allowed.git'
        self.assertEqual(self.git('remote', 'get-url', 'origin').stdout.strip(), expected)
        self.assertEqual(self.git('remote', 'get-url', '--push', '--all', 'origin').stdout.splitlines(), [expected])

    def test_new_remote_and_disallowed_repo(self):
        result = self.ghx('remote', 'fixture', 'allowed', 'work')
        self.assertEqual(result.returncode, 0, result.stderr)
        expected = self.git('remote', 'get-url', 'work').stdout
        result = self.ghx('remote', 'fixture', 'forbidden', 'work')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.git('remote', 'get-url', 'work').stdout, expected)

    def test_default_clone_rejects_destination_symlink_outside_workspace(self):
        outside = self.home / 'outside'
        outside.mkdir()
        (self.home / 'codex_project/allowed').symlink_to(outside, target_is_directory=True)
        stub_dir = self.home / 'bin'
        stub_dir.mkdir()
        marker = self.home / 'git-executed'
        git = stub_dir / 'git'
        git.write_text('#!/bin/sh\n: > "$HOME/git-executed"\n')
        git.chmod(0o755)
        self.env['PATH'] = str(stub_dir) + ':' + self.env['PATH']
        result = self.ghx('clone', 'fixture', 'allowed')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(marker.exists())

    def test_remote_rejects_option_like_name(self):
        result = self.ghx('remote', 'fixture', 'allowed', '--mirror')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('некорректное имя remote', result.stderr)
        self.assertEqual(self.git('remote').stdout, '')

    def test_api_routes_synthetic_token_only_through_environment(self):
        stub_dir = self.home / 'bin'
        stub_dir.mkdir()
        gh = stub_dir / 'gh'
        gh.write_text('#!/usr/bin/python3\nimport os, sys\n'
                      'assert sys.argv[1:] == ["api", "/user"]\n'
                      'assert os.environ["GH_HOST"] == "github.com"\n'
                      'assert os.environ["GH_TOKEN"] == "synthetic-fixture"\n'
                      'print("routing-ok")\n')
        gh.chmod(0o755)
        self.env.update(PATH=str(stub_dir) + ':' + self.env['PATH'],
                        GH_TOKEN='synthetic-old-fixture', GITHUB_TOKEN_FIXTURE='synthetic-fixture')
        result = self.ghx('api', 'fixture', '/user')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), 'routing-ok')


if __name__ == '__main__':
    unittest.main()
