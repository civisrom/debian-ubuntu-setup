#!/usr/bin/env python3
"""Synthetic payload tests: no credentials or real /opt files are read."""
import hashlib
import importlib.util
import io
import os
from pathlib import Path
import re
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("payload", REPO / "config/opt-payload.py")
payload = importlib.util.module_from_spec(spec)
spec.loader.exec_module(payload)


class PayloadTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="opt-vault-test-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.source = self.root / "source"
        self.vault = self.root / "vault"
        self.target = self.root / "target"
        self.backups = self.root / "backups"
        self.source.mkdir(); self.vault.mkdir(); self.target.mkdir()
        (self.source / "scripts").mkdir()
        self.fixtures = {
            "environment": b"SYNTHETIC='literal $() `text`'\n",
            "geolite_config": b"fixture only\n",
            "scripts/tool.py": b"#!/usr/bin/python3\nprint('fixture')\n",
            "scripts/lists.json": b'{"fixture":true}\n',
            "имя с пробелом.txt": b"\x00\xff\x01",
            ".hidden": b"hidden fixture\n",
        }
        for name, contents in self.fixtures.items():
            (self.source / name).write_bytes(contents)

    def pack(self):
        payload.pack(self.source, self.vault)

    def bad_archive(self, entries):
        with tarfile.open(self.vault / "payload.tar.gz", "w:gz") as archive:
            for name, kind in entries:
                item = tarfile.TarInfo(name); item.type = kind
                if kind == tarfile.REGTYPE:
                    item.size = 1; archive.addfile(item, io.BytesIO(b"x"))
                else:
                    item.linkname = "/etc/passwd"; archive.addfile(item)
        (self.vault / "payload.sha256").write_text(payload.digest(self.vault / "payload.tar.gz") + "  payload.tar.gz\n")

    def test_roundtrip_bytes_permissions_hidden_and_unrelated_files(self):
        self.pack()
        (self.target / "unrelated.txt").write_text("keep")
        (self.target / "environment").write_text("old fixture")
        payload.restore(self.vault, self.target, self.backups)
        for name, content in self.fixtures.items():
            self.assertEqual((self.target / name).read_bytes(), content)
            self.assertEqual((self.target / name).stat().st_mode & 0o777, payload.mode(name))
        self.assertEqual((self.target / "unrelated.txt").read_text(), "keep")
        backup = next(self.backups.glob("opt-before-*"))
        self.assertEqual(backup.stat().st_mode & 0o777, 0o700)
        with tarfile.open(backup / "previous.tar.gz") as archive:
            self.assertEqual(archive.extractfile("environment").read(), b"old fixture")

    def test_repeat_restore(self):
        self.pack()
        payload.restore(self.vault, self.target, self.backups)
        payload.restore(self.vault, self.target, self.backups)
        self.assertEqual(len(list(self.backups.iterdir())), 2)

    def test_checksum_damage_keeps_destination(self):
        self.pack()
        with (self.vault / "payload.tar.gz").open("ab") as stream:
            stream.write(b"damage")
        with self.assertRaises(ValueError):
            payload.restore(self.vault, self.target, self.backups)
        self.assertEqual(list(self.target.iterdir()), [])

    def test_checksum_cannot_select_external_file(self):
        self.pack()
        (self.vault / "payload.sha256").write_text("0" * 64 + "  /etc/passwd\n")
        with self.assertRaises(ValueError):
            payload.verify(self.vault)

    def test_tar_traversal_links_duplicates_special_files(self):
        cases = [
            [("../escape", tarfile.REGTYPE)], [("/absolute", tarfile.REGTYPE)],
            [("a", tarfile.SYMTYPE)], [("a", tarfile.LNKTYPE)],
            [("a", tarfile.FIFOTYPE)], [("a", tarfile.CHRTYPE)],
            [("a", tarfile.REGTYPE), ("a", tarfile.REGTYPE)],
            [("missing/child", tarfile.REGTYPE)], [("control\nname", tarfile.REGTYPE)],
        ]
        for entries in cases:
            with self.subTest(entries=entries):
                self.bad_archive(entries)
                with self.assertRaises(ValueError):
                    payload.restore(self.vault, self.target, self.backups)
                self.assertFalse(self.backups.exists())

    def test_destination_symlink_and_hardlink(self):
        self.pack()
        outside = self.root / "outside"; outside.write_text("keep")
        for kind in ("symlink", "hardlink"):
            if kind == "symlink": (self.target / "environment").symlink_to(outside)
            else: os.link(outside, self.target / "environment")
            with self.assertRaises(ValueError):
                payload.restore(self.vault, self.target, self.backups)
            self.assertEqual(outside.read_text(), "keep")
            (self.target / "environment").unlink()

    def test_destination_parent_symlink(self):
        self.pack()
        link = self.root / "link"; link.symlink_to(self.target, target_is_directory=True)
        with self.assertRaises(ValueError):
            payload.restore(self.vault, link / "child", self.backups)

    def test_source_symlink_rejected(self):
        (self.source / "linked").symlink_to(self.source / "environment")
        with self.assertRaises(ValueError): self.pack()

    def test_source_empty_and_output_inside_source_rejected(self):
        empty = self.root / "empty"; empty.mkdir()
        with self.assertRaises(ValueError): payload.pack(empty, self.vault)
        with self.assertRaises(ValueError): payload.pack(self.source, self.source / "output")

    def test_oversize_rejected(self):
        self.pack()
        with patch.object(payload, "MAX_BYTES", 1):
            with self.assertRaises(ValueError): payload.restore(self.vault, self.target, self.backups)

    def test_copy_failure_rolls_back(self):
        self.pack()
        for name, content in self.fixtures.items():
            dest = self.target / name; dest.parent.mkdir(exist_ok=True)
            dest.write_bytes(b"original"); dest.chmod(0o640)
        (self.target / "scripts").chmod(0o700)
        original = os.replace
        count = 0
        def fail_second(src, dst):
            nonlocal count
            count += 1
            if count == 5: raise OSError("synthetic write failure")
            original(src, dst)
        with patch.object(payload.os, "replace", side_effect=fail_second):
            with self.assertRaises(OSError): payload.restore(self.vault, self.target, self.backups)
        for name in self.fixtures:
            self.assertEqual((self.target / name).read_bytes(), b"original")
            self.assertEqual((self.target / name).stat().st_mode & 0o777, 0o640)
        self.assertEqual(list(self.target.rglob(".opt-vault-*")), [])
        self.assertEqual((self.target / "scripts").stat().st_mode & 0o777, 0o700)

    def test_private_config_and_git_modes(self):
        for name in ("environment", "geolite_config", "a/.env", "a/wg0.conf", "a/x.toml", "a/x.ini", "x/.git/config"):
            self.assertEqual(payload.mode(name), 0o600)
        self.assertEqual(payload.mode("a/.git", True), 0o700)
        self.assertEqual(payload.mode("GeoLite2-ASN.mmdb"), 0o644)

    def test_help_does_not_need_root_or_password(self):
        result = subprocess.run(["bash", str(REPO / "config/opt-vault.sh"), "--help"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0)
        self.assertIn("100", result.stdout)

    def test_installer_passes_password_on_stdin_and_propagates_failure(self):
        source = (REPO / "system-setup.sh").read_text()
        function = re.search(r"(?ms)^restore_opt_vault\(\) \{\n.*?^\}$", source)[0]
        helper = self.root / "fake-helper.sh"
        helper.write_text('''#!/bin/bash
IFS= read -r supplied
[[ $supplied == 'synthetic $() `literal` password' ]] || exit 90
printf '%s\\n' "$@" > "$RECORD"
exit "$HELPER_RC"
''')
        body = r'''
print_error() { printf 'fixture error\n' >&2; }
create_temp_dir() { SYSTEM_SETUP_CREATED_TEMP_DIR="$WORK"; }
validate_shell_script() { bash -n "$1"; }
download_verified_url() {
    [[ $1 == "https://raw.githubusercontent.com/civisrom/debian-ubuntu-setup/${SYSTEM_SETUP_REPOSITORY_REF}/config/"* ]] || return 92
    [[ $3 =~ ^[a-f0-9]{64}$ ]] || return 93
    [[ ${FAIL_DOWNLOAD:-no} != yes ]] || return 94
    case $1 in */opt-vault.sh) cp "$HELPER" "$2";; *) : > "$2";; esac
}
OPT_VAULT_PASSWORD='synthetic $() `literal` password'
restore_opt_vault
rc=$?
[[ ${FAIL_DOWNLOAD:-no} == yes || -z ${OPT_VAULT_PASSWORD+x} ]] || exit 95
exit "$rc"
'''
        record = self.root / "arguments"
        for failure in (0, 57):
            env = dict(os.environ, WORK=str(self.root), HELPER=str(helper), RECORD=str(record),
                       HELPER_RC=str(failure), SYSTEM_SETUP_REPOSITORY_REF="a" * 40)
            result = subprocess.run(["bash", "-c", function + "\n" + body], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, failure)
            self.assertEqual(record.read_text().splitlines(), ["restore", str(self.root / "opt.hc")])
            self.assertNotIn("synthetic $()", result.stdout + result.stderr)
        record.unlink()
        env["FAIL_DOWNLOAD"] = "yes"
        result = subprocess.run(["bash", "-c", function + "\n" + body], env=env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(record.exists())

    def test_failed_restore_skips_firewall_and_clears_password(self):
        source = (REPO / "system-setup.sh").read_text()
        block = source.split("# RESTORE VERACRYPT SNAPSHOT TO /OPT\n", 1)[1].split("# ENABLE NFTABLES FIREWALL", 1)[0]
        body = r'''
print_header() { :; }; print_message() { :; }; print_error() { :; }
restore_opt_vault() { return 1; }
RESTORE_OPT_VAULT=y ENABLE_NFTABLES=y OPT_VAULT_PASSWORD=synthetic
'''
        result = subprocess.run(["bash", "-c", body + block + '\n[[ $ENABLE_NFTABLES == n && $OPT_COPY_OK == false && -z ${OPT_VAULT_PASSWORD+x} ]]'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
