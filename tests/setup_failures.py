#!/usr/bin/env python3
"""Exercise installer failure paths without installing or changing the host."""

import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest


SOURCE = (Path(__file__).resolve().parents[1] / "system-setup.sh").read_text()


def function(name):
    return re.search(rf"(?ms)^{name}\(\) \{{\n.*?^\}}$", SOURCE)[0] + "\n"


LOGGING = """
print_error() { printf 'ERROR: %s\n' "$1" >&2; }
print_warning() { printf 'WARNING: %s\n' "$1" >&2; }
print_success() { printf 'SUCCESS: %s\n' "$1"; }
print_message() { printf 'INFO: %s\n' "$1"; }
"""


class SetupFailures(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="setup-regression-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def shell(self, body, *args, input=None):
        return subprocess.run(
            ["bash", "-c", "set -o pipefail\n" + LOGGING + body, "test", *map(str, args)],
            input=input, text=True, capture_output=True, timeout=30,
        )

    @unittest.skipUnless(shutil.which("7z"), "7z required for real encrypted archive tests")
    def test_archive_password_stdin_and_failure_diagnostics(self):
        payload = self.root / "payload.txt"
        payload.write_text("extracted contents\n")
        # Public fixture password, deliberately including shell metacharacters.
        password = "fixture $() `literal` \\ проба !"
        for headers in ("on", "off"):
            archive = self.root / f"headers-{headers}.7z"
            subprocess.run(
                ["7z", "a", "-p" + password, "-mhe=" + headers, str(archive), str(payload)],
                check=True, capture_output=True,
            )
            output = self.root / f"out-{headers}"
            body = function("extract_7z_archive") + 'extract_7z_archive "$1" "$2"'
            result = self.shell(body, archive, output, input=password + "\n")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((output / payload.name).read_text(), payload.read_text())
            result = self.shell(body, archive, self.root / "wrong", input="incorrect\n")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("7z extraction failed", result.stderr)
            self.assertNotIn(password, result.stdout + result.stderr)

        corrupt = self.root / "corrupt.7z"
        corrupt.write_text("not an archive")
        result = self.shell(body, corrupt, self.root / "bad", input=password + "\n")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("7z extraction failed", result.stderr)

    def test_go_metadata_selection_and_rejection(self):
        def release(version, stable=True):
            return {"version": version, "stable": stable, "files": [{
                "filename": f"{version}.linux-amd64.tar.gz", "os": "linux",
                "arch": "amd64", "kind": "archive", "sha256": "a" * 64,
            }]}

        metadata = self.root / "go.json"
        releases = [release("go1.26.9"), release("go1.28.0", False), release("go1.27.1")]
        metadata.write_text(json.dumps(releases))
        body = function("select_go_archive") + 'select_go_archive "$1" "$2"'
        result = self.shell(body, metadata, "amd64")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "go1.27.1 go1.27.1.linux-amd64.tar.gz " + "a" * 64)
        self.assertNotEqual(self.shell(body, metadata, "arm64").returncode, 0)
        releases[-1]["files"][0]["sha256"] = "<html>error</html>"
        metadata.write_text(json.dumps(releases))
        self.assertNotEqual(self.shell(body, metadata, "amd64").returncode, 0)
        metadata.write_text("<html>error</html>")
        self.assertNotEqual(self.shell(body, metadata, "amd64").returncode, 0)

    def test_ppa_preflight_prevents_unsupported_source_addition(self):
        body = function("add_supported_ubuntu_ppa") + """
VERSION_CODENAME=resolute
download_url_ipv4() {
    case "$1" in
        https://ppa.launchpadcontent.net/ondrej/php/ubuntu/dists/resolute/Release) ;;
        *) return 2 ;;
    esac
    case "$2:$mode" in
        *:unavailable) return 1 ;;
        *:wrong) printf 'Codename: noble\n' > "$2" ;;
        *) printf 'Codename: resolute\n' > "$2" ;;
    esac
}
add-apt-repository() { printf '%s\n' "$*" > "$marker"; }
mode=$1 marker=$2
add_supported_ubuntu_ppa ppa:ondrej/php
"""
        marker = self.root / "added"
        for mode in ("unavailable", "wrong"):
            result = self.shell(body, mode, marker)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(marker.exists())
        self.assertEqual(self.shell(body, "available", marker).returncode, 0)
        self.assertEqual(marker.read_text().strip(), "--no-update -y ppa:ondrej/php")

    def test_pinned_commit_is_fetched_from_shallow_checkout(self):
        # This creates only disposable local repositories, with an explicit
        # non-personal identity independent of the user's Git configuration.
        repo = self.root / "origin"
        clone = self.root / "clone"
        env = dict(os.environ, GIT_AUTHOR_NAME="fixture", GIT_COMMITTER_NAME="fixture",
                   GIT_AUTHOR_EMAIL="fixture@users.noreply.github.com",
                   GIT_COMMITTER_EMAIL="fixture@users.noreply.github.com")

        def git(*args, check=True):
            return subprocess.run(["git", *map(str, args)], env=env,
                                  check=check, text=True, capture_output=True)

        git("init", repo)
        payload = repo / "payload"
        payload.write_text("pinned")
        git("-C", repo, "add", "payload")
        git("-C", repo, "commit", "-m", "fixture pinned")
        pinned = git("-C", repo, "rev-parse", "HEAD").stdout.strip()
        payload.write_text("new tip")
        git("-C", repo, "commit", "-am", "fixture tip")
        git("clone", "--depth=1", repo.as_uri(), clone)
        self.assertNotEqual(git("-C", clone, "cat-file", "-e", pinned, check=False).returncode, 0)
        body = function("pin_user_git_checkout") + """
sudo() { shift 2; "$@"; }
pin_user_git_checkout fixture "$1" "$2"
"""
        result = self.shell(body, clone, pinned)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((clone / "payload").read_text(), "pinned")
        self.assertEqual(git("-C", clone, "rev-parse", "HEAD").stdout.strip(), pinned)
        self.assertNotEqual(self.shell(body, clone, "0" * 40).returncode, 0)

    def test_swap_success_requires_active_swap(self):
        start = SOURCE.index('        if [ "$SWAP_SETUP_EXIT_CODE" -eq 0 ] && swapon')
        end = SOURCE.index('        print_message "You can manage swap later:', start)
        body = """
SWAP_SETUP_EXIT_CODE=$1
swapon() { if [ "$2" = "--noheadings" ]; then printf '%s' "$active"; else return 2; fi; }
active=$2
""" + SOURCE[start:end] + '\n[ "${SWAP_SETUP_OK:-false}" = true ]'
        for code, active, success in ((100, "", False), (100, "/oldswap", False),
                                      (0, "", False), (0, "/swapfile file 1G", True)):
            self.assertEqual(self.shell(body, code, active).returncode == 0, success)

    def test_ssh_effective_conflict_rejected(self):
        managed = self.root / "managed.conf"
        managed.write_text("# Managed\nPort 7384\nPasswordAuthentication no\nAllowUsers codex admin\n")
        body = function("verify_sshd_parameters") + """
sshd() { printf 'port 7384\npasswordauthentication %s\nallowusers codex\nallowusers admin\n' "$password"; }
password=$2
verify_sshd_parameters "$1"
"""
        self.assertEqual(self.shell(body, managed, "no").returncode, 0)
        result = self.shell(body, managed, "yes")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Effective SSH PasswordAuthentication", result.stderr)

    def test_prompt_eof_aborts_and_preserves_literal_input(self):
        body = function("prompt_read") + 'prompt_read -r value\nprintf "%s" "$value"'
        self.assertNotEqual(self.shell(body, input="").returncode, 0)
        value = "  literal \\ $()  "
        self.assertEqual(self.shell(body, input=value + "\n").stdout, value)

    def test_managed_blocks_reject_truncation(self):
        path = self.root / "config"
        body = function("strip_managed_block") + 'strip_managed_block "$1" sysctl'
        path.write_text("before\n# BEGIN system-setup.sh managed sysctl\nold\n# END system-setup.sh managed sysctl\nafter\n")
        self.assertEqual(self.shell(body, path).stdout, "before\nafter\n")
        path.write_text("before\n# BEGIN system-setup.sh managed sysctl\nkeep me\n")
        self.assertNotEqual(self.shell(body, path).returncode, 0)

    def test_grub_quotes_comments_and_idempotence(self):
        path = self.root / "grub"
        original = "GRUB_CMDLINE_LINUX_DEFAULT='quiet splash' # keep\nGRUB_CMDLINE_LINUX=\"$existing\"\n"
        path.write_text(original)
        body = function("prepare_grub_ipv6") + 'prepare_grub_ipv6 "$1"'
        result = self.shell(body, path)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("'quiet splash ipv6.disable=1' # keep", result.stdout)
        self.assertIn('"$existing ipv6.disable=1"', result.stdout)
        path.write_text(result.stdout)
        self.assertEqual(self.shell(body, path).stdout, result.stdout)
        path.write_text('GRUB_CMDLINE_LINUX="one"\nGRUB_CMDLINE_LINUX="two"\n')
        result = self.shell(body, path)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")

    def test_empty_firewall_snapshot_can_be_restored(self):
        snapshot = self.root / "empty.nft"
        transaction = self.root / "transaction.nft"
        snapshot.touch()
        body = function("build_nft_transaction") + function("restore_live_nft_ruleset") + """
nft() { printf '%s\n' "$*"; }
restore_live_nft_ruleset "$1" "$2"
"""
        result = self.shell(body, snapshot, transaction)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(transaction.read_text(), "flush ruleset\n")
        self.assertIn("-f " + str(transaction), result.stdout)

    @unittest.skipUnless(shutil.which("sshd"), "sshd required for real SSH config tests")
    def test_ssh_migration_cloud_init_and_rollback(self):
        ssh_dir = self.root / "ssh"
        dropins = ssh_dir / "sshd_config.d"
        dropins.mkdir(parents=True)
        hostkey = self.root / "hostkey"
        subprocess.run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", str(hostkey)], check=True)
        config = ssh_dir / "sshd_config"
        legacy = dropins / "99-system-setup.conf"
        cloud = dropins / "50-cloud-init.conf"
        cloud.write_text("PasswordAuthentication yes\n")
        main_text = f"HostKey {hostkey}\nPort 22\nAllowUsers olduser\n"
        legacy_text = "# Managed by system-setup.sh\nPort 7384\nPasswordAuthentication no\n"
        section = SOURCE.split("# CONFIGURE SSH\n# ============================================", 1)[1]
        section = section.split("# CONFIGURE UFW\n", 1)[0]
        helpers = "".join(function(name) for name in (
            "ensure_sshd_include_first", "remove_sshd_accumulating_parameters",
            "verify_sshd_parameters", "warn_sshd_dropin_conflicts",
        ))
        body = (helpers + section).replace("/etc/ssh", str(ssh_dir))
        stubs = f"""
CONFIGURE_SSH=y SSH_PORT=7384 SSH_ALLOW_USERS=codex SSH_PASSWORD_AUTH=no
SSH_PUBKEY_AUTH=yes SSH_EMPTY_PASSWORDS=no SSH_ROOT_LOGIN=no SSH_PRINT_MOTD=yes
sshd() {{ {shutil.which('sshd')} -f '{config}' "$@"; }}
write_file_atomic() {{ local temporary; temporary=$(mktemp); cat > "$temporary" && mv -- "$temporary" "$1"; }}
restart_ssh_listener() {{ [ "$1" = 22 ] || [ "$fail_restart" = no ]; }}
restore_ssh_activation_state() {{ :; }}
fail_restart=$1
"""
        for fail_restart in ("no", "yes"):
            config.write_text(main_text)
            legacy.write_text(legacy_text)
            managed = dropins / "10-system-setup.conf"
            managed.unlink(missing_ok=True)
            result = self.shell(stubs + body + '\nprintf "RESULT:%s" "$CONFIGURE_SSH"', fail_restart)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(cloud.read_text(), "PasswordAuthentication yes\n")
            if fail_restart == "no":
                self.assertIn("RESULT:y", result.stdout, result.stdout + result.stderr)
                self.assertTrue(managed.exists())
                self.assertFalse(legacy.exists())
            else:
                self.assertIn("RESULT:failed", result.stdout)
                self.assertEqual(config.read_text(), main_text)
                self.assertEqual(legacy.read_text(), legacy_text)
                self.assertFalse(managed.exists())

    def test_ufw_failure_never_enables_firewall(self):
        section = SOURCE.split("# CONFIGURE UFW\n# ============================================", 1)[1]
        section = section.split("# Configure ICMP blocking in UFW", 1)[0]
        body = """
CONFIGURE_UFW=y SSH_PORT=22 CUSTOM_PORTS=''
ufw() {
    printf 'UFW:%s\n' "$*"
    if [ "$1" = allow ]; then return 1; fi
}
sshd() { printf 'port 7384\n'; }
""" + section
        result = self.shell(body)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("UFW:allow 7384/tcp", result.stdout)
        self.assertNotIn("UFW:--force enable", result.stdout)
        self.assertNotIn("UFW:--force default", result.stdout)

    def test_resolver_success_and_exact_rollback(self):
        etc = self.root / "etc"
        dropins = etc / "systemd/resolved.conf.d"
        dropins.mkdir(parents=True)
        runtime = self.root / "run/systemd/resolve"
        runtime.mkdir(parents=True)
        target = runtime / "stub-resolv.conf"
        target.write_text("nameserver 127.0.0.53\n")
        managed = dropins / "99-system-setup.conf"
        resolver = etc / "resolv.conf"
        old_target = etc / "previous-resolver"
        old_target.write_text("nameserver 192.0.2.53\n")
        body = function("is_yes") + function("configure_systemd_resolved")
        body = body.replace("/etc/", str(etc) + "/").replace("/var/backups", str(self.root / "backups"))
        body = body.replace("/run/systemd/", str(self.root / "run/systemd") + "/")
        stubs = """
RESOLVED_DNS=1.1.1.1 RESOLVED_DNS_OVER_TLS=n RESOLVED_STUB_LISTENER_OFF=n
failure=$1 started=false
apt-get() {
    if [ "$failure" = apt ]; then
        rm -f -- "$resolv_file"
        printf 'package changed resolver\n' > "$resolv_file"
        return 1
    fi
}
systemctl() {
    case "$1" in
        is-active) [ "$started" = true ] ;;
        is-enabled) printf 'disabled\n'; return 1 ;;
        restart) started=true; [ "$failure" != restart ] ;;
        *) return 0 ;;
    esac
}
getent() { [ "$failure" != dns ]; }
write_file_atomic() { local temporary; temporary=$(mktemp); cat > "$temporary" && mv -- "$temporary" "$1"; }
"""
        for kind in ("file", "symlink"):
            for failure in ("none", "apt", "restart", "dns"):
                resolver.unlink(missing_ok=True)
                if kind == "file":
                    resolver.write_text(old_target.read_text())
                else:
                    resolver.symlink_to(old_target)
                managed.write_text("[Resolve]\nDNS=192.0.2.53\n")
                result = self.shell(stubs + body + "configure_systemd_resolved", failure)
                if failure == "none":
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertEqual(resolver.readlink(), target)
                    self.assertIn("DNS=1.1.1.1", managed.read_text())
                else:
                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual(managed.read_text(), "[Resolve]\nDNS=192.0.2.53\n")
                    self.assertEqual(resolver.is_symlink(), kind == "symlink")
                    self.assertEqual(resolver.read_text(), old_target.read_text())

    def test_nftables_failure_restores_config_and_empty_runtime(self):
        etc = self.root / "etc"
        etc.mkdir()
        profile_dir = self.root / "opt/nftables"
        profile_dir.mkdir(parents=True)
        profile = profile_dir / "profile.conf"
        profile.write_text("table inet replacement {}\n")
        config = etc / "nftables.conf"
        config.write_text("table inet previous {}\n")
        section = SOURCE.split("# ENABLE NFTABLES FIREWALL\n", 1)[1].split("# INSTALL NFT-DOCKER-WATCH SERVICE\n", 1)[0]
        helpers = "".join(function(name) for name in (
            "create_temp_dir", "build_nft_transaction", "restore_live_nft_ruleset",
        ))
        body = helpers + section
        for prefix in ("/etc/", "/opt/", "/run/", "/var/backups"):
            body = body.replace(prefix, str(self.root) + prefix)
        calls = self.root / "nft-calls"
        stubs = """
ENABLE_NFTABLES=y INSTALL_NFTABLES_CONF=y INSTALL_NFTABLES_LOGGING=n
NFTABLES_CONF_FILE=profile.conf NFTABLES_PROFILE=test OPT_EXTRACTED_OK=true
SYSTEM_SETUP_TEMP_DIRS=()
TMPDIR=$1
calls=$2
print_header() { :; }
flock() { :; }
dpkg-query() { return 1; }
systemctl() { if [ "$1" = is-enabled ]; then printf 'disabled\n'; fi; }
nft() {
    printf '%s\n' "$*" >> "$calls"
    case "$1" in
        --version) printf 'fixture nft\n' ;;
        list) : ;; # empty snapshot and failed postcondition
        -c) : ;;
        -f) cat "$2" >> "$calls" ;;
        *) return 1 ;;
    esac
}
write_file_atomic() { local temporary; temporary=$(mktemp); cat > "$temporary" && mv -- "$temporary" "$1"; }
"""
        result = self.shell(stubs + body + '\n[ "$NFTABLES_OK" = false ]', self.root, calls)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(config.read_text(), "table inet previous {}\n")
        self.assertIn("rollback.nft", calls.read_text())

    def test_apt_sources_preserve_third_party_entries(self):
        for os_name, version, codename in (("debian", "13", "trixie"), ("ubuntu", "26.04", "resolute")):
            apt = self.root / os_name / "apt"
            sources_dir = apt / "sources.list.d"
            sources_dir.mkdir(parents=True)
            main = apt / "sources.list"
            third_party = "deb https://packages.example.invalid/repo stable main\n"
            host = "deb.debian.org/debian" if os_name == "debian" else "archive.ubuntu.com/ubuntu"
            main.write_text(f"deb http://{host} {codename} main\n" + third_party)
            target = sources_dir / f"{os_name}.sources"
            target.write_text("# previous distro definition\n")
            body = function("configure_apt_repositories").replace("/etc/apt", str(apt))
            stubs = """
OS=$1 VERSION=$2 VERSION_CODENAME=$3
dpkg() { printf 'amd64\n'; }
write_file_atomic() { local temporary; temporary=$(mktemp); cat > "$temporary" && mv -- "$temporary" "$1"; }
"""
            for _ in range(2):
                result = self.shell(stubs + body + "configure_apt_repositories", os_name, version, codename)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(main.read_text(), third_party)
                self.assertIn(f"Suites: {codename} {codename}-updates", target.read_text())
                self.assertEqual(target.read_text().count("Types: deb"), 2)


if __name__ == "__main__":
    unittest.main(verbosity=2)
