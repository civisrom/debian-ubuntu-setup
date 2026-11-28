#!/usr/bin/env python3
"""Failure-path regressions for optional services and network configuration."""

import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "system-setup.sh").read_text()
LOGGING = """
print_error() { printf 'ERROR: %s\\n' "$1" >&2; }
print_warning() { :; }
print_message() { :; }
print_success() { :; }
print_header() { :; }
"""


class InstallerFeatures(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="installer-features-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)

    def shell(self, body, *args):
        return subprocess.run(
            ["bash", "-c", "set -o pipefail\n" + LOGGING + body, "test", *map(str, args)],
            text=True, capture_output=True, timeout=20,
        )

    def test_login_shell_requires_plugins_and_both_verified_startup_files(self):
        start = SOURCE.index('    if [ "$OH_MY_ZSH_OK" = true ]; then')
        end = SOURCE.index('    echo ""', start)
        setup = """
USER_HOME=$1 repo=$2 failure=$3
NEW_USERNAME=testuser USER_GROUP=testgroup OH_MY_ZSH_OK=true ZSH_CONFIG_OK=true
sudo() { cat >/dev/null; [[ $failure != plugins ]]; }
install_verified_repo_asset() {
    [[ $1 != "config/$failure" ]] &&
        [[ $(sha256sum "$repo/$1" | cut -d' ' -f1) = "$3" ]] &&
        cp "$repo/$1" "$2"
}
chown() { [[ $failure != owner ]]; }
zsh() { :; }
chsh() { printf '%s\\n' "$*" > "$USER_HOME/switched"; }
"""
        for failure in ("none", "plugins", ".zshrc", ".zshenv", "owner"):
            with self.subTest(failure=failure):
                home = self.root / failure
                home.mkdir()
                result = self.shell(setup + SOURCE[start:end] + '\nprintf "%s" "$ZSH_CONFIG_OK"',
                                    home, ROOT, failure)
                self.assertEqual(result.returncode, 0, result.stderr)
                good = failure == "none"
                self.assertEqual(result.stdout, "true" if good else "false")
                self.assertEqual((home / "switched").exists(), good)
                if good:
                    self.assertEqual((home / "switched").read_text().strip(), "-s zsh testuser")

    def test_ufw_preserves_firewall_when_ssh_config_cannot_be_read(self):
        section = SOURCE.split("# CONFIGURE UFW\n# ============================================", 1)[1]
        section = section.split("# Configure ICMP blocking in UFW", 1)[0]
        for status, ports in ((1, ""), (0, ""), (1, "port 7384")):
            result = self.shell("""
CONFIGURE_UFW=y SSH_PORT=22 CUSTOM_PORTS=''
ufw() { printf 'UFW mutation\\n'; }
sshd() { printf '%s\\n' "$ports"; return "$status"; }
status=$1 ports=$2
""" + section, status, ports)
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn("UFW mutation", result.stdout)

    def test_custom_ufw_sources_preserve_installed_script_on_preparation_failures(self):
        section = SOURCE.split("# INSTALL CUSTOM UFW DOCKER RULES\n", 1)[1]
        section = section.split("# RESTORE VERACRYPT SNAPSHOT TO /OPT\n", 1)[0]
        helpers = "\n".join(re.search(rf"(?ms)^{name}\(\) \{{\n.*?^\}}$", SOURCE)[0]
                            for name in ("valid_uint", "write_file_atomic"))
        original = "#!/bin/bash\n# Previous working script\nexit 0\n"
        cases = [(failure, "SSH_PORT=22") for failure in
                 ("backup", "stage", "sed", "chmod", "write", "none")]
        cases += [("none", 'SSH_PORT=${SSH_PORT:-22}'),
                  ("unsupported-port", "SSH_PORT=2200")]
        for source in ("1", "2"):
            for index, (failure, assignment) in enumerate(cases):
                with self.subTest(source=source, failure=failure, assignment=assignment):
                    directory = self.root / f"ufw-{source}-{index}"
                    (directory / "opt").mkdir(parents=True)
                    installed = directory / "opt/ufw-docker-rules-v4.sh"
                    installed.write_text(original)
                    fixture = directory / "fixture.sh"
                    fixture.write_text("#!/bin/bash\n" + assignment +
                                       '\nprintf "%s\\n" "$SSH_PORT" > "$TEST_EXECUTION"\n')
                    invocation = """
testroot=$1 failure=$2 INSTALL_UFW_CUSTOM_RULES=y UFW_INSTALL_SOURCE=$3
UFW_RULES_VERSION=4 UFW_SSH_PORT=7384 UFW_CUSTOM_RULES_PASSWORD=test-fixture
SYSTEM_SETUP_REPOSITORY_REF=main SYSTEM_SETUP_TEMP_FILES=()
export TEST_EXECUTION="$testroot/executed"
validate_shell_script() { bash -n "$1"; }
create_temp_dir() { SYSTEM_SETUP_CREATED_TEMP_DIR=$(mktemp -d "$testroot/work.XXXXXX"); }
download_verified_url() {
    case "$2" in
        *.7z) printf 'synthetic archive fixture\\n' > "$2" ;;
        *) command cp "$testroot/fixture.sh" "$2" ;;
    esac
}
extract_7z_archive() { command cp "$testroot/fixture.sh" "$2/$UFW_SCRIPT_NAME"; }
apt-get() { return 0; }
cp() {
    if [ "$failure" = backup ] && [[ "${*: -1}" == *.backup.* ]]; then return 1; fi
    if [ "$failure" = stage ] && [[ "${*: -1}" == *.candidate.* ]]; then return 1; fi
    command cp "$@"
}
sed() { [ "$failure" != sed ] && command sed "$@"; }
chmod() { [ "$failure" != chmod ] && command chmod "$@"; }
chown() { return 0; }
mv() { [ "$failure" != write ] && command mv "$@"; }
""" + helpers + "\n" + section.replace("/opt/", str(directory / "opt") + "/")
                    result = self.shell(invocation, directory, failure, source)
                    marker = directory / "executed"
                    if failure == "none":
                        self.assertEqual(result.returncode, 0, result.stderr)
                        self.assertEqual(marker.read_text(), "7384\n")
                        self.assertIn("SSH_PORT=7384\n", installed.read_text())
                        self.assertEqual(installed.stat().st_mode & 0o777, 0o755)
                        self.assertEqual(next(installed.parent.glob("*.backup.*")).read_text(), original)
                    else:
                        self.assertFalse(marker.exists(), result.stdout + result.stderr)
                        self.assertEqual(installed.read_text(), original)
                        self.assertIn("ERROR:", result.stderr)

    def test_interfaces_stanzas_survive_comments_and_include_boundaries(self):
        section = SOURCE.split("# COMMENT IPv6 IN /etc/network/interfaces\n", 1)[1]
        transform = re.search(r"(?s)awk '\n(.*?)\n            ' \"\$INTERFACES_FILE\"", section)[1]
        fixture = """auto eth0
iface eth0 inet6 static
    address 2001:db8::10/64

    # Keep following options in this stanza.
    gateway 2001:db8::1
source /etc/network/interfaces.d/*
allow-hotplug eth1
iface eth1 inet static
    address 192.0.2.2/24

    # DNS is still part of the IPv4 stanza.
    dns-nameservers 2001:db8::53 192.0.2.53
"""
        result = subprocess.run(["awk", transform], input=fixture, text=True,
                                capture_output=True, check=True)
        self.assertIn("#    gateway 2001:db8::1", result.stdout)
        self.assertIn("\nsource /etc/network/interfaces.d/*\n", result.stdout)
        self.assertIn("\nallow-hotplug eth1\n", result.stdout)
        self.assertIn("\n    address 192.0.2.2/24\n", result.stdout)
        self.assertIn("\n    dns-nameservers 192.0.2.53\n", result.stdout)
        again = subprocess.run(["awk", transform], input=result.stdout, text=True,
                               capture_output=True, check=True)
        self.assertEqual(again.stdout, result.stdout)

    def test_crontab_contents_are_not_echoed(self):
        section = SOURCE.split("# CONFIGURE CRONTAB\n", 1)[1].split("# INSTALL CUSTOM MOTD", 1)[0]
        marker = "synthetic-confidential-cron-argument"
        existing = self.root / "original"
        existing.write_text(f"0 1 * * * test-command {marker}\n")
        installed = self.root / "installed"
        result = self.shell("""
CONFIGURE_CRONTAB=y CRONTAB_TASKS='0 2 * * * /bin/true'
TMPDIR=$1
create_temp_dir() { SYSTEM_SETUP_CREATED_TEMP_DIR=$TMPDIR; }
strip_managed_block() { cat "$1"; }
crontab() {
    if [ "$1" = -l ]; then cat "$TMPDIR/original";
    else cat > "$TMPDIR/installed"; fi
}
""" + section, self.root)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn(marker, result.stdout + result.stderr)
        self.assertIn(marker, installed.read_text())

    def test_docker_backup_and_write_failures_preserve_previous_config(self):
        section = SOURCE.split("# Create daemon.json to disable Docker iptables management", 1)[1]
        section = section.split("# Verify Docker installation", 1)[0]
        directory = self.root / "docker"
        directory.mkdir()
        config = directory / "daemon.json"
        original = '{"log-driver": "local", "iptables": true}\n'
        section = section.replace("/etc/docker", str(directory))
        for failure in ("backup", "write"):
            config.write_text(original)
            result = self.shell("""
DOCKER_INSTALLED=yes DOCKER_DISABLE_IPTABLES=y failure=$1
cp() { [ "$failure" != backup ] && command cp "$@"; }
write_file_atomic() { return 1; }
systemctl() { printf 'SYSTEMCTL:%s\\n' "$*"; }
""" + section, failure)
            self.assertEqual(config.read_text(), original)
            self.assertNotIn("SYSTEMCTL:restart", result.stdout)
            self.assertIn("ERROR:", result.stderr)

    def test_nginx_recovery_retries_requested_packages_and_rolls_back(self):
        section = SOURCE.split("# On an IPv6-disabled host a leftover", 1)[1]
        section = section.split("# Always re-enable service autostart", 1)[0]
        section = section[section.index('if [ "$NGINX_IPV6_GUARD"'):]
        section = section.rsplit("            fi", 1)[0]
        for failure in ("packages", "config", "start", "none"):
            result = self.shell("""
NGINX_IPV6_GUARD=y NGINX_PKGS='nginx requested-module' NGINX_BK=/synthetic-backup
failure=$1
nginx_strip_ipv6_listen() { :; }
dpkg() { return 0; }
apt-get() {
    printf 'APT:%s\\n' "$*"
    [[ "$*" != *requested-module* ]] || [ "$failure" != packages ]
}
nginx() { [ "$failure" != config ]; }
systemctl() { [ "$1" != restart ] || [ "$failure" != start ]; }
nginx_restore_migration() { printf 'ROLLBACK\\n'; }
""" + section + '\nprintf "RUNTIME=%s" "${NGINX_RUNTIME_OK:-false}"', failure)
            self.assertIn("RUNTIME=" + ("true" if failure == "none" else "false"), result.stdout)
            self.assertIn("requested-module", result.stdout)
            if failure == "none":
                self.assertNotIn("ROLLBACK", result.stdout)
                self.assertNotIn("ERROR:", result.stderr)
            else:
                self.assertIn("ROLLBACK", result.stdout)
                self.assertIn("ERROR:", result.stderr)

    def test_resolved_loopback_listener_matches_selected_address(self):
        body = re.search(r"(?ms)^configure_systemd_resolved\(\) \{\n.*?^\}$", SOURCE)[0]
        # Stop at the first attempted mutation; this test exercises preflight.
        for address, listener, accepted in (
            ("127.0.1.1", "127.0.1.1:53", True),
            ("127.0.1.1", "127.0.0.1:53", False),
            ("127.0.1.1", "0.0.0.0:53", True),
            ("::1", "[::1]:53", True),
            ("::1", "127.0.0.1:53", False),
            ("127.0.0.53", "0.0.0.0:53", False),
        ):
            result = self.shell("""
RESOLVED_DNS=$1 listener=$2 RESOLVED_DNS_OVER_TLS=n RESOLVED_STUB_LISTENER_OFF=n
is_yes() { [ "$1" = y ]; }
ss() { printf 'udp UNCONN 0 0 %s *:*\\n' "$listener"; }
install() { printf 'PREFLIGHT-PASSED\\n'; return 1; }
""" + body + "\nconfigure_systemd_resolved", address, listener)
            self.assertEqual("PREFLIGHT-PASSED" in result.stdout, accepted,
                             (address, listener, result.stderr))

    def test_resolved_tls_keeps_stub_for_direct_dns_clients(self):
        body = re.search(r"(?ms)^configure_systemd_resolved\(\) \{\n.*?^\}$", SOURCE)[0]
        result = self.shell("""
RESOLVED_DNS=1.1.1.1 RESOLVED_DNS_OVER_TLS=y RESOLVED_STUB_LISTENER_OFF=y
is_yes() { [ "$1" = y ]; }
install() { return 1; }
""" + body + '\nconfigure_systemd_resolved; printf "stub-off=%s\\n" "$RESOLVED_STUB_LISTENER_OFF"')
        self.assertIn("stub-off=n", result.stdout)

    def run_rustdesk_delegation(self, docker_active=True, bad_file=None, auto_update="y"):
        """install_rustdesk_server downloads pinned, verified files and runs rustdesk-ctl."""
        body = re.search(r"(?ms)^RUSTDESK_SETUP_COMMIT=.*?^install_rustdesk_server\(\) \{\n.*?^\}$", SOURCE)[0]
        mirror = self.root / "mirror"
        entries = re.findall(r'^    "([^" ]+) ([0-9a-f]{64})"$', body, re.M)
        for path, _ in entries:
            (mirror / path).parent.mkdir(parents=True, exist_ok=True)
            (mirror / path).write_text("content of " + path)
        result = self.shell("""
mirror=$1 docker_active=$2 bad=$3 INSTALL_RUSTDESK_UPDATE=$4
TMPDIR=$5
is_yes() { [ "$1" = y ]; }
SYSTEM_SETUP_TEMP_DIRS=()
create_temp_dir() { SYSTEM_SETUP_CREATED_TEMP_DIR=$(mktemp -d "$TMPDIR/rd.XXXXXX"); }
docker() { :; }
systemctl() { [ "$docker_active" = y ]; }
download_verified_url() {
    local path=${1#https://raw.githubusercontent.com/civisrom/rustdesk-server-setup/$RUSTDESK_SETUP_COMMIT/}
    printf 'download %s %s\n' "$path" "$3"
    [ "$path" != "$bad" ] || return 1
    cp "$mirror/$path" "$2"
}
bash() { printf 'run %s\n' "$*"; [ -x "$1" ] && [ -f "$(dirname "$1")/files/docker-compose.yml" ]; }
""" + body + "\ninstall_rustdesk_server", mirror, "y" if docker_active else "n",
                            bad_file or "", auto_update, self.root)
        return result, entries

    def test_rustdesk_delegation_downloads_every_pinned_file_then_installs(self):
        result, entries = self.run_rustdesk_delegation()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual({path for path, _ in entries},
                         {"rustdesk-ctl", "files/docker-compose.yml", "files/rustdesk-compose.service",
                          "files/rustdesk-update.service", "files/rustdesk-update.timer",
                          "files/rustdesk-watchdog.service", "files/rustdesk-watchdog.timer"})
        for path, sha in entries:
            self.assertIn(f"download {path} {sha}", result.stdout)
        self.assertRegex(result.stdout, r"run \S+/rustdesk-ctl install\n")
        result, _ = self.run_rustdesk_delegation(auto_update="n")
        self.assertRegex(result.stdout, r"run \S+/rustdesk-ctl install --no-auto-update\n")

    def test_rustdesk_delegation_stops_without_docker_or_on_a_bad_file(self):
        result, _ = self.run_rustdesk_delegation(docker_active=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("download", result.stdout)
        self.assertIn("needs a running Docker", result.stderr)
        result, _ = self.run_rustdesk_delegation(bad_file="files/rustdesk-update.timer")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("run ", result.stdout)
        self.assertIn("rustdesk-server-setup/files/rustdesk-update.timer", result.stderr)

if __name__ == "__main__":
    unittest.main()
