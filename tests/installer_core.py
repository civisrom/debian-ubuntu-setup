#!/usr/bin/env python3
"""Regression tests for installer I/O, locking and bootstrap failures."""

import fcntl
import hashlib
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "system-setup.sh").read_text()


def function(name):
    return re.search(rf"(?ms)^{name}\(\) \{{\n.*?^\}}$", SOURCE)[0] + "\n"


LOGGING = """
print_error() { printf 'ERROR: %s\\n' "$1" >&2; }
print_warning() { printf 'WARNING: %s\\n' "$1" >&2; }
print_message() { :; }
print_success() { :; }
"""


class InstallerCoreAudit(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="installer-core-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def shell(self, body, *args, input=None):
        return subprocess.run(
            ["bash", "-c", "set -o pipefail\n" + LOGGING + body, "test", *map(str, args)],
            text=True, input=input, capture_output=True, timeout=10,
        )

    def test_atomic_writer_honors_explicit_mode_on_existing_file(self):
        target = self.root / "config"
        target.write_text("old\n")
        target.chmod(0o644)
        result = self.shell(function("write_file_atomic") +
                            'write_file_atomic "$1" 0600 "$2"',
                            target, f"{os.getuid()}:{os.getgid()}", input="new\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(target.read_text(), "new\n")
        self.assertEqual(target.stat().st_mode & 0o777, 0o600)

    def test_atomic_writer_preserves_unspecified_metadata(self):
        target = self.root / "config"
        target.write_text("old\n")
        target.chmod(0o640)
        before = target.stat()
        result = self.shell(function("write_file_atomic") + 'write_file_atomic "$1"',
                            target, input="new\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        after = target.stat()
        self.assertEqual((after.st_uid, after.st_gid, after.st_mode),
                         (before.st_uid, before.st_gid, before.st_mode))

    def test_atomic_writer_keeps_original_on_metadata_failure(self):
        for command in ("chmod", "chown"):
            with self.subTest(command=command):
                target = self.root / "config"
                target.write_text("old\n")
                result = self.shell(function("write_file_atomic") +
                                    f"{command}() {{ return 1; }}\n" +
                                    'write_file_atomic "$1" 0600 "$2"',
                                    target, f"{os.getuid()}:{os.getgid()}", input="new\n")
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(target.read_text(), "old\n")
                self.assertEqual(list(self.root.glob("config.*")), [])

    def test_atomic_writer_rejects_a_directory_destination(self):
        target = self.root / "directory"
        target.mkdir()
        result = self.shell(function("write_file_atomic") +
                            'write_file_atomic "$1" 0600 "$2"',
                            target, f"{os.getuid()}:{os.getgid()}", input="new\n")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(list(target.iterdir()), [])
        self.assertEqual(list(self.root.glob("directory.*")), [])

    def test_apt_wait_detects_real_posix_record_lock(self):
        lock = self.root / "apt-lock"
        body = function("wait_for_apt_locks") + """
APT_LOCK_FILES=("$1")
APT_LOCK_WAIT_SECONDS=0
wait_for_apt_locks
"""
        with lock.open("w+") as stream:
            fcntl.lockf(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
            result = self.shell(body, lock)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("APT lock still held", result.stderr)
        result = self.shell(body, lock)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_apt_inherited_configuration_stays_private(self):
        original = self.root / "apt.conf"
        original.write_text('Acquire::Retries "3";\n')
        result = self.shell(function("configure_apt_lock_timeout") + """
SYSTEM_SETUP_TEMP_FILES=()
APT_CONFIG=$1 TMPDIR=$2 APT_LOCK_WAIT_SECONDS=10
configure_apt_lock_timeout || exit 1
stat -c '%a' "$APT_CONFIG"
""", original, self.root)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "600")

    def test_dns_recovery_preserves_a_working_resolver(self):
        resolv = self.root / "resolv.conf"
        resolv.write_text("nameserver 192.0.2.53\n")
        body = function("ensure_dns_works").replace("/etc/resolv.conf", str(resolv))
        result = self.shell(body + """
getent() { return 0; }
systemctl() { printf 'unexpected service change\\n' >&2; return 1; }
sleep() { :; }
ensure_dns_works fixture
""")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(resolv.read_text(), "nameserver 192.0.2.53\n")
        self.assertNotIn("unexpected service change", result.stderr)

    def test_bootstrap_runs_without_a_controlling_terminal(self):
        child = self.root / "payload.sh"
        child.write_text("#!/bin/bash\nprintf 'BOOTSTRAP_CHILD_RAN\\n'\nexit 7\n")
        (self.root / "payload.sha256").write_text(hashlib.sha256(child.read_bytes()).hexdigest() + "\n")
        (self.root / "commit.json").write_text('{\n  "sha": "' + "a" * 40 + '",\n}\n')
        binary = self.root / "bin"
        binary.mkdir()
        curl = binary / "curl"
        curl.write_text("""#!/bin/bash
output=${@: -1}
url=${@: -3:1}
case "$url" in
    */commits/main) cp "$FIXTURES/commit.json" "$output" ;;
    */system-setup.sh.sha256) cp "$FIXTURES/payload.sha256" "$output" ;;
    */system-setup.sh) cp "$FIXTURES/payload.sh" "$output" ;;
    *) exit 1 ;;
esac
""")
        curl.chmod(0o755)
        wrapper = self.root / "install.sh"
        # Root is only required by the real payload, which this test replaces.
        wrapper.write_text((ROOT / "install.sh").read_text().replace(
            'if [ "$EUID" -ne 0 ]; then', "if false; then"))
        result = subprocess.run(
            ["bash", str(wrapper)], stdin=subprocess.DEVNULL, capture_output=True,
            text=True, start_new_session=True, timeout=10,
            env={**os.environ, "PATH": str(binary) + os.pathsep + os.environ["PATH"],
                 "FIXTURES": str(self.root), "TMPDIR": str(self.root)},
        )
        self.assertEqual(result.returncode, 7, result.stdout + result.stderr)
        self.assertIn("BOOTSTRAP_CHILD_RAN", result.stdout)
        self.assertEqual(list(self.root.glob("system-setup.*")), [])

    def test_ssh_port_prompt_normalizes_accepted_leading_zeroes(self):
        section = re.search(r"(?ms)^        while true; do\n"
                            r"            prompt_value SSH_PORT.*?^        done\n", SOURCE)[0]
        result = self.shell("""
prompt_value() { SSH_PORT=00022; }
ss() { :; }
""" + section + 'printf "%s" "$SSH_PORT"')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "22")

    def test_ssh_verifier_accepts_equivalent_user_whitespace(self):
        managed = self.root / "sshd.conf"
        managed.write_text("AllowUsers root   fixture\n")
        result = self.shell(function("verify_sshd_parameters") + """
sshd() { printf 'allowusers root fixture\\n'; }
verify_sshd_parameters "$1"
""", managed)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_ntp_reply_does_not_imply_synchronized_clock(self):
        body = function("timesync_wait_timesyncd") + """
TIMESYNC_WAIT_SECONDS=1
timesync_is_synchronized() { return 1; }
sleep() { SECONDS=$((SECONDS + 2)); }
timedatectl() {
    case "$*" in
        "show-timesync -p ServerName --value") printf 'time.example\\n' ;;
        "show-timesync -p NTPMessage --value") printf '{ Leap=3, Version=4, Mode=4, Stratum=3 }\\n' ;;
    esac
}
timesync_wait_timesyncd time.example
"""
        result = self.shell(body)
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
