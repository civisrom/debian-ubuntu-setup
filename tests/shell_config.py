#!/usr/bin/env python3
"""Check shell startup using disposable homes and synthetic credentials."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which("zsh"), "zsh is not installed")
class ShellConfigTests(unittest.TestCase):
    def test_noninteractive_shell_loads_only_private_token_file(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            (home / ".config").mkdir()
            shutil.copyfile(REPO / "config/.zshenv", home / ".zshenv")
            fixture = home / ".config/secrets.env"
            fixture.write_text("export GITHUB_TOKEN_TEST=synthetic-fixture\n")
            env = {key: value for key, value in os.environ.items()
                   if "TOKEN" not in key and key not in ("ZDOTDIR", "GITHUB_TOKEN_TEST")}
            env.update(HOME=directory, ZDOTDIR=directory)
            for permissions, expected in ((0o600, "loaded"), (0o400, "loaded"), (0o644, "missing")):
                with self.subTest(permissions=oct(permissions)):
                    fixture.chmod(permissions)
                    result = subprocess.run(
                        ["zsh", "-c", 'if [[ ${GITHUB_TOKEN_TEST:-} == synthetic-fixture ]]; '
                         'then print loaded; else print missing; fi; '
                         '[[ $path[1] == "$HOME/.local/bin" ]]'],
                        env=env, capture_output=True, text=True, timeout=10,
                    )
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(result.stdout.strip(), expected)


if __name__ == "__main__":
    unittest.main()
