#!/bin/bash

#############################################
# System Setup Script for Debian and Ubuntu
# Author: Enhanced Version v2.0
# Description: Initial package installation and system configuration
# Supported: Debian 12, 13 | Ubuntu 24.04 LTS, 26.04 LTS
#############################################

# Do not use global errexit: several helper tools legitimately return
# non-zero status codes to signal "changed" or "skipped". Critical failures
# are handled with explicit exit calls at the relevant decision points.
set -o pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script version
SCRIPT_VERSION="2.0"

SETUP_WARNINGS=()
SETUP_ERRORS=()
SETUP_ROLLBACKS=()

final_exit_code() {
    if [ "${#SETUP_ERRORS[@]}" -gt 0 ]; then
        return 1
    fi
    return 0
}

record_maybe_rollback() {
    local message="$1"

    if [[ "$message" =~ [Rr]estor|[Rr]ollback|[Оо]ткат ]]; then
        SETUP_ROLLBACKS+=("$message")
    fi
}

# Function to print colored messages
print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
    record_maybe_rollback "$1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    SETUP_ERRORS+=("$1")
    record_maybe_rollback "$1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    SETUP_WARNINGS+=("$1")
    record_maybe_rollback "$1"
}

print_header() {
    echo -e "${BLUE}$1${NC}"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

prompt_read() {
    if ! IFS= read "$@"; then
        print_error "Input ended before configuration was complete; setup cancelled"
        exit 1
    fi
}

report_setup_result() {
    local label="$1" result="${2:-false}"
    if [ "$result" = true ]; then
        print_message "- $label: completed and verified"
    else
        print_message "- $label: FAILED, skipped or incomplete; see execution log"
    fi
}

install_user_public_key() {
    local username="$1" key="$2" user_home key_tmp auth
    user_home=$(getent passwd "$username" | cut -d: -f6)
    id -u "$username" >/dev/null 2>&1 || return 1
    [ -n "$user_home" ] && [ -d "$user_home" ] || return 1
    key_tmp=$(mktemp) || return 1
    printf '%s\n' "$key" > "$key_tmp"
    if ! ssh-keygen -l -f "$key_tmp" >/dev/null 2>&1; then
        rm -f -- "$key_tmp"
        print_error "Invalid SSH public key for $username"
        return 1
    fi
    rm -f -- "$key_tmp"
    # Perform writes as the account owner: a symlink in an existing user's
    # home must not turn this into a root-owned arbitrary file write.
    sudo -u "$username" mkdir -p "$user_home/.ssh" || return 1
    sudo -u "$username" chmod 700 "$user_home/.ssh" || return 1
    auth="$user_home/.ssh/authorized_keys"
    sudo -u "$username" touch "$auth" || return 1
    sudo -u "$username" chmod 600 "$auth" || return 1
    if ! sudo -u "$username" grep -Fxq -- "$key" "$auth"; then
        sudo -u "$username" cp -p -- "$auth" "${auth}.backup.$(date +%Y%m%d-%H%M%S)~" || return 1
        printf '%s\n' "$key" | sudo -u "$username" tee -a "$auth" >/dev/null || return 1
    fi
}

strip_managed_block() {
    local source_file="$1" block_name="$2"
    awk -v begin="# BEGIN system-setup.sh managed $block_name" \
        -v end="# END system-setup.sh managed $block_name" '
        $0 == begin { if (skip) exit 2; skip=1; next }
        $0 == end { if (!skip) exit 2; skip=0; next }
        !skip { print }
        END { if (skip) exit 2 }
    ' "$source_file"
}

repository_has_release() {
    local url="$1" codename="$2" metadata
    metadata=$(mktemp) || return 1
    if download_url_ipv4 "$url" "$metadata" && grep -Fxq "Codename: $codename" "$metadata"; then
        rm -f -- "$metadata"
        return 0
    fi
    rm -f -- "$metadata"
    return 1
}

prepare_grub_ipv6() {
    python3 - "$1" <<'PYGRUB'
import re
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    lines = stream.read().splitlines(keepends=True)
names = ("GRUB_CMDLINE_LINUX_DEFAULT", "GRUB_CMDLINE_LINUX")
seen = set()
result = []
for line in lines:
    key = re.match(r"\s*(GRUB_CMDLINE_LINUX(?:_DEFAULT)?)=", line)
    if not key:
        result.append(line)
        continue
    name = key[1]
    value = re.fullmatch(r'''(\s*\w+=)(?:"((?:\\.|[^"\\])*)"|'([^']*)'|([^\s#'"\\]*))([ \t]*(?:#.*)?)\n?''', line)
    if name in seen or not value:
        print("Ambiguous GRUB command line; configuration was left unchanged", file=sys.stderr)
        sys.exit(1)
    seen.add(name)
    raw = next(v for v in value.groups()[1:4] if v is not None)
    # Preserve shell expansions in double quotes and literal single-quoted data.
    quote = "'" if value[3] is not None else '"'
    if "ipv6.disable=1" not in raw.split():
        raw = (raw + " ipv6.disable=1").strip()
    result.append(value[1] + quote + raw + quote + value[5] + "\n")
for name in names:
    if name not in seen:
        if result and not result[-1].endswith("\n"):
            result[-1] += "\n"
        result.append(name + '="ipv6.disable=1"\n')
sys.stdout.write("".join(result))
PYGRUB
}

# Password comes from stdin. A bare -p means an empty password in modern 7z,
# preventing its normal password prompt from reading the supplied input.
extract_7z_archive() {
    local archive="$1" destination="$2" log_file result
    log_file=$(mktemp) || return 1
    if 7z x -y -o"$destination" "$archive" >"$log_file" 2>&1; then
        rm -f -- "$log_file"
        return 0
    else
        result=$?
    fi
    print_error "7z extraction failed (exit code: $result)"
    tail -n 20 "$log_file" >&2
    rm -f -- "$log_file"
    return "$result"
}

# Select version, filename and digest from the same official metadata response.
select_go_archive() {
    python3 - "$1" "$2" <<'PY'
import json
import re
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as stream:
        releases = json.load(stream)
    stable = [r for r in releases if r.get("stable") is True
              and re.fullmatch(r"go\d+\.\d+\.\d+", r["version"])]
    release = max(stable, key=lambda r: tuple(map(int, r["version"][2:].split("."))))
    filename = f'{release["version"]}.linux-{sys.argv[2]}.tar.gz'
    matches = [f for f in release["files"] if f.get("filename") == filename
               and f.get("os") == "linux" and f.get("arch") == sys.argv[2]
               and f.get("kind") == "archive"]
    if len(matches) != 1 or not re.fullmatch(r"[0-9a-fA-F]{64}", matches[0]["sha256"]):
        raise ValueError("missing or invalid archive checksum")
    print(release["version"], filename, matches[0]["sha256"].lower())
except (OSError, ValueError, KeyError, TypeError) as error:
    print(f"Cannot select a verified Go archive: {error}", file=sys.stderr)
    sys.exit(1)
PY
}

add_supported_ubuntu_ppa() {
    local ppa="$1" release_file
    release_file=$(mktemp) || return 1
    # Do not add an unsupported suite: it would break later apt-get updates,
    # including the update performed by the swap installer.
    if ! download_url_ipv4 "https://ppa.launchpadcontent.net/${ppa#ppa:}/ubuntu/dists/${VERSION_CODENAME}/Release" "$release_file" ||
       ! grep -Fxq "Codename: $VERSION_CODENAME" "$release_file"; then
        rm -f -- "$release_file"
        print_warning "Skipping $ppa: no verified Release metadata for $VERSION_CODENAME"
        print_warning "If this PPA was added by an earlier run, disable its source before running apt-get update"
        return 1
    fi
    rm -f -- "$release_file"
    if add-apt-repository --no-update -y "$ppa"; then
        print_success "$ppa added for $VERSION_CODENAME"
        return 0
    fi
    print_error "Failed to add $ppa"
    return 1
}

pin_user_git_checkout() {
    local username="$1" checkout_dir="$2" commit="$3"
    sudo -u "$username" git -C "$checkout_dir" fetch --depth=1 origin "$commit" &&
        sudo -u "$username" git -C "$checkout_dir" checkout --detach "$commit"
}

# Validate global effective values, not just syntax. Earlier drop-ins can
# otherwise silently override the choices shown in the final summary.
verify_sshd_parameters() {
    local managed_file="$1" effective parameter expected actual
    effective=$(sshd -T) || return 1
    while read -r parameter expected; do
        [ -n "$parameter" ] && [[ "$parameter" != \#* ]] || continue
        actual=$(awk -v key="${parameter,,}" '$1 == key {$1=""; sub(/^ /, ""); print}' <<< "$effective")
        # sshd may output an accumulating directive on several lines.
        actual=$(xargs <<< "$actual")
        if [ "$actual" != "$expected" ]; then
            print_error "Effective SSH $parameter is '$actual'; requested '$expected'. Resolve conflicting drop-ins or Match settings"
            return 1
        fi
    done < "$managed_file"
}

remove_sshd_accumulating_parameters() {
    local config="$1" temporary
    temporary=$(mktemp) || return 1
    # Port and AllowUsers accumulate instead of using the first value. Move
    # selected global settings from the main file into our managed drop-in.
    if awk -v change_port="${SSH_PORT:-}" -v change_users="${SSH_ALLOW_USERS:-}" '
        tolower($1) == "match" { in_match=1 }
        !in_match && tolower($1) == "port" && change_port != "" { next }
        !in_match && tolower($1) == "allowusers" && change_users != "" { next }
        { print }
    ' "$config" > "$temporary" && write_file_atomic "$config" < "$temporary"; then
        rm -f -- "$temporary"
        return 0
    fi
    rm -f -- "$temporary"
    return 1
}

# True when the kernel has IPv6 disabled (module absent or sysctl disable_ipv6=1).
# On such hosts nginx cannot bind "listen [::]:80/443" and aborts on start / -t,
# which in turn aborts the nginx package install (postinst service start).
nginx_ipv6_is_disabled() {
    [ ! -f /proc/net/if_inet6 ] && return 0
    [ "$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null)" = "1" ] && return 0
    return 1
}

# Strip IPv6 "listen [::]:..." directives shipped in the distro default site /
# conf.d files. On IPv6-disabled hosts these break "nginx -t" and the service.
nginx_strip_ipv6_listen() {
    local f
    for f in /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default \
             /etc/nginx/conf.d/default.conf /etc/nginx/conf.d/*.conf; do
        [ -f "$f" ] || continue
        sed -i -E '/^[[:space:]]*listen[[:space:]]+\[::\]:/d' "$f"
    done
}

# Restore the exact nginx package set and configuration captured immediately
# before a repository migration. This is best-effort but materially safer than
# leaving a partially removed web server after the replacement transaction fails.
nginx_restore_migration() {
    local backup_dir="$1"
    local package_file="$backup_dir/packages.txt"
    local archive="$backup_dir/etc-nginx.tar.gz"
    local package version current
    local -a old_specs=()
    local -a old_names=()
    local -a extra_packages=()

    [ -s "$package_file" ] || return 1

    while read -r package version; do
        [ -n "$package" ] && [ -n "$version" ] || continue
        old_names+=("$package")
        old_specs+=("${package}=${version}")
    done < "$package_file"
    [ "${#old_specs[@]}" -gt 0 ] || return 1

    # Confirm that every exact previous version is still obtainable before
    # removing anything from the failed replacement transaction.
    apt-get install -s -y --allow-downgrades "${old_specs[@]}" >/dev/null 2>&1 || return 1

    while read -r current; do
        [ -n "$current" ] || continue
        if ! printf '%s\n' "${old_names[@]}" | grep -Fxq -- "$current"; then
            extra_packages+=("$current")
        fi
    done < <(dpkg-query -W -f='${Package} ${Status}\n' 'nginx*' 'libnginx-mod-*' 2>/dev/null \
        | awk '/ install ok installed$/{print $1}' | sort -u)

    if [ "${#extra_packages[@]}" -gt 0 ]; then
        apt-get purge -y "${extra_packages[@]}" || return 1
    fi
    apt-get install -y --allow-downgrades \
        -o Dpkg::Options::=--force-confold \
        -o Dpkg::Options::=--force-confdef \
        "${old_specs[@]}" || return 1

    if [ -s "$archive" ]; then
        tar xzf "$archive" -C / || return 1
    fi
    dpkg --configure -a || return 1
    nginx -t || return 1
    systemctl enable nginx 2>/dev/null && systemctl restart nginx 2>/dev/null || return 1
}

# Stop Debian maintainer scripts from (re)starting services during apt, while
# preserving any administrator-provided policy and restoring it on every exit.
NGINX_POLICY_RC_BACKUP=""
NGINX_POLICY_RC_BACKUP_DIR=""
NGINX_POLICY_RC_WAS_PRESENT=false
NGINX_POLICY_RC_GUARD_ACTIVE=false

nginx_block_service_autostart() {
    local policy_file="/usr/sbin/policy-rc.d"

    if [ "$NGINX_POLICY_RC_GUARD_ACTIVE" = true ]; then
        return 0
    fi

    if [ -e "$policy_file" ] || [ -L "$policy_file" ]; then
        NGINX_POLICY_RC_WAS_PRESENT=true
        NGINX_POLICY_RC_BACKUP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/policy-rc.d.XXXXXX") || return 1
        NGINX_POLICY_RC_BACKUP="${NGINX_POLICY_RC_BACKUP_DIR}/policy-rc.d"
        cp -a -- "$policy_file" "$NGINX_POLICY_RC_BACKUP" || return 1
    else
        NGINX_POLICY_RC_WAS_PRESENT=false
    fi

    printf '#!/bin/sh\nexit 101\n' | write_file_atomic "$policy_file" 0755 root:root || return 1
    NGINX_POLICY_RC_GUARD_ACTIVE=true
}
nginx_unblock_service_autostart() {
    local policy_file="/usr/sbin/policy-rc.d"

    [ "$NGINX_POLICY_RC_GUARD_ACTIVE" = true ] || return 0

    if [ "$NGINX_POLICY_RC_WAS_PRESENT" = true ] && [ -n "$NGINX_POLICY_RC_BACKUP" ]; then
        rm -f -- "$policy_file"
        cp -a -- "$NGINX_POLICY_RC_BACKUP" "$policy_file" || return 1
    else
        rm -f -- "$policy_file"
    fi

    if [ -n "$NGINX_POLICY_RC_BACKUP_DIR" ]; then
        rm -rf -- "$NGINX_POLICY_RC_BACKUP_DIR"
    fi
    NGINX_POLICY_RC_BACKUP=""
    NGINX_POLICY_RC_BACKUP_DIR=""
    NGINX_POLICY_RC_GUARD_ACTIVE=false
}

print_recorded_items() {
    local title="$1"
    shift

    [ "$#" -gt 0 ] || return 0

    echo -e "${GREEN}[INFO]${NC} $title"
    local item
    for item in "$@"; do
        printf '  - %s\n' "$item"
    done
}

ensure_downloader_available() {
    if command -v curl &>/dev/null || command -v wget &>/dev/null; then
        return 0
    fi

    print_warning "Neither curl nor wget is installed; installing curl and ca-certificates..."
    if command -v apt-get &>/dev/null; then
        apt-get update -qq || print_warning "apt-get update failed while preparing downloader install"
        if apt-get install -y -qq curl ca-certificates; then
            print_message "curl installed successfully"
            return 0
        fi
    fi

    print_error "curl or wget is required for downloads"
    return 1
}

download_url_ipv4() {
    local url="$1"
    local output="$2"
    local max_time="${3:-300}"

    ensure_downloader_available || return 1

    if command -v curl &>/dev/null; then
        if curl --ipv4 -fsSL --connect-timeout 15 --max-time "$max_time" --retry 3 --retry-delay 2 "$url" -o "$output"; then
            return 0
        fi
        print_warning "curl IPv4 download failed for $url; trying wget"
    fi

    if command -v wget &>/dev/null; then
        if wget -4 -q --show-progress --timeout=15 --dns-timeout=15 --connect-timeout=15 --read-timeout=60 --tries=3 "$url" -O "$output"; then
            return 0
        fi
        print_warning "wget IPv4 download failed for $url"
    fi

    return 1
}

SYSTEM_SETUP_TEMP_FILES=()
SYSTEM_SETUP_REPOSITORY_REF="${SYSTEM_SETUP_REPOSITORY_COMMIT:-main}"
if [ "$SYSTEM_SETUP_REPOSITORY_REF" != "main" ] && \
   ! [[ "$SYSTEM_SETUP_REPOSITORY_REF" =~ ^[0-9a-f]{40}$ ]]; then
    SYSTEM_SETUP_REPOSITORY_REF="main"
fi

download_verified_url() {
    local url="$1"
    local output="$2"
    local expected_sha256="$3"
    local max_time="${4:-300}"
    local temp_file actual_sha256

    if ! [[ "$expected_sha256" =~ ^[0-9a-fA-F]{64}$ ]]; then
        print_error "Invalid pinned SHA256 for $url"
        return 1
    fi
    temp_file=$(mktemp "${output}.download.XXXXXX") || return 1
    SYSTEM_SETUP_TEMP_FILES+=("$temp_file")
    chmod 0600 "$temp_file"

    if ! download_url_ipv4 "$url" "$temp_file" "$max_time"; then
        rm -f -- "$temp_file"
        return 1
    fi
    actual_sha256=$(sha256sum "$temp_file" | awk '{print $1}')
    if [ "$actual_sha256" != "$expected_sha256" ]; then
        print_error "SHA256 mismatch for $url"
        rm -f -- "$temp_file"
        return 1
    fi
    mv -f -- "$temp_file" "$output"
}

install_verified_repo_asset() {
    local relative_path="$1"
    local output="$2"
    local expected_sha256="$3"
    local mode="${4:-0644}"
    local source_dir local_asset temp_file actual_sha256

    source_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd) || source_dir=""
    local_asset="${source_dir}/${relative_path}"

    if [ -n "$source_dir" ] && [ -f "$local_asset" ]; then
        actual_sha256=$(sha256sum "$local_asset" | awk '{print $1}')
        if [ "$actual_sha256" != "$expected_sha256" ]; then
            print_error "Local asset SHA256 mismatch: $relative_path"
            return 1
        fi
        temp_file=$(mktemp "${output}.install.XXXXXX") || return 1
        SYSTEM_SETUP_TEMP_FILES+=("$temp_file")
        install -m "$mode" -o root -g root "$local_asset" "$temp_file" || return 1
        mv -f -- "$temp_file" "$output"
    else
        download_verified_url \
            "https://raw.githubusercontent.com/civisrom/debian-ubuntu-setup/${SYSTEM_SETUP_REPOSITORY_REF}/${relative_path}" \
            "$output" "$expected_sha256" || return 1
        chmod "$mode" "$output"
        chown root:root "$output"
    fi
}

# Helper function to check if variable is yes
is_yes() {
    [ "$1" = "y" ] || [ "$1" = "Y" ]
}

# Ubuntu's apt-daily / unattended-upgrades timers take the APT locks a few
# minutes into a boot. Without a timeout apt aborts immediately ("Could not
# get lock ... It is held by process N"), which failed unrelated package steps
# and the installers this script downloads and runs.
APT_LOCK_WAIT_SECONDS=600
APT_LOCK_FILES=(/var/lib/dpkg/lock-frontend /var/lib/dpkg/lock
                /var/lib/apt/lists/lock /var/cache/apt/archives/lock)

# Applies to this script's own apt calls and, because APT_CONFIG is inherited,
# to child installers too. APT_CONFIG is merged with the system configuration
# rather than replacing it.
configure_apt_lock_timeout() {
    local config
    config=$(mktemp "${TMPDIR:-/tmp}/system-setup-apt.XXXXXX") || return 1
    SYSTEM_SETUP_TEMP_FILES+=("$config")
    if [ -n "${APT_CONFIG:-}" ] && [ -r "$APT_CONFIG" ]; then
        cat -- "$APT_CONFIG" > "$config" || return 1
    fi
    printf 'DPkg::Lock::Timeout "%s";\n' "$APT_LOCK_WAIT_SECONDS" >> "$config" || return 1
    chmod 0644 "$config" || return 1
    export APT_CONFIG="$config"
}

# Block until the locks are free before handing control to a child installer,
# so a busy package manager is reported instead of looking like a hang.
wait_for_apt_locks() {
    local deadline=$((SECONDS + APT_LOCK_WAIT_SECONDS)) lock reported=false
    command -v flock >/dev/null 2>&1 || return 0
    for lock in "${APT_LOCK_FILES[@]}"; do
        [ -e "$lock" ] || continue
        while ! flock -n "$lock" true 2>/dev/null; do
            if [ "$SECONDS" -ge "$deadline" ]; then
                print_error "APT lock still held after ${APT_LOCK_WAIT_SECONDS}s: $lock"
                return 1
            fi
            if [ "$reported" = false ]; then
                print_message "Waiting for another package manager to release the APT locks..."
                reported=true
            fi
            sleep 5
        done
    done
    [ "$reported" = true ] && print_message "APT locks released; continuing"
    return 0
}

SYSTEM_SETUP_TEMP_DIRS=()
SYSTEM_SETUP_CREATED_TEMP_DIR=""

create_temp_dir() {
    local prefix="${1:-system-setup}"
    local temp_dir

    SYSTEM_SETUP_CREATED_TEMP_DIR=""
    temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/${prefix}.XXXXXX") || {
        print_error "Failed to create temporary directory"
        return 1
    }
    SYSTEM_SETUP_TEMP_DIRS+=("$temp_dir")
    SYSTEM_SETUP_CREATED_TEMP_DIR="$temp_dir"
}

cleanup_temp_dirs() {
    local temp_dir temp_file

    for temp_dir in "${SYSTEM_SETUP_TEMP_DIRS[@]:-}"; do
        if [ -n "$temp_dir" ] && [ -d "$temp_dir" ]; then
            rm -rf -- "$temp_dir" 2>/dev/null || true
        fi
    done

    for temp_file in "${SYSTEM_SETUP_TEMP_FILES[@]:-}"; do
        [ -n "$temp_file" ] && rm -f -- "$temp_file" 2>/dev/null || true
    done

    nginx_unblock_service_autostart 2>/dev/null || true
}
trap cleanup_temp_dirs EXIT

validate_shell_script() {
    local script_path="$1"
    local shell_bin="${2:-bash}"

    if [ ! -s "$script_path" ]; then
        print_error "Downloaded script is missing or empty: $script_path"
        return 1
    fi

    if ! "$shell_bin" -n "$script_path"; then
        print_error "Downloaded script failed syntax check: $script_path"
        return 1
    fi
}

# Atomically replace a file with the given content (read from stdin).
# Preserves owner/mode of an existing target; falls back to root:root 0644 for new files.
write_file_atomic() {
    local target="$1"
    local mode="${2:-}"
    local owner="${3:-}"
    local tmp

    tmp=$(mktemp "${target}.XXXXXX") || {
        print_error "Failed to create temporary file for $target"
        return 1
    }

    if ! cat > "$tmp"; then
        rm -f "$tmp"
        print_error "Failed to write content to temporary file for $target"
        return 1
    fi

    if [ -e "$target" ]; then
        chmod --reference="$target" "$tmp" 2>/dev/null || chmod "${mode:-0644}" "$tmp"
        chown --reference="$target" "$tmp" 2>/dev/null || chown "${owner:-root:root}" "$tmp"
    else
        chmod "${mode:-0644}" "$tmp"
        chown "${owner:-root:root}" "$tmp"
    fi

    if ! mv "$tmp" "$target"; then
        rm -f "$tmp"
        print_error "Failed to move temporary file into place: $target"
        return 1
    fi
}

# Ensure 'Include /etc/ssh/sshd_config.d/*.conf' is the FIRST active directive in sshd_config.
# Critical for sshd's "first value wins" rule: drop-ins must be parsed before any
# parameter set later in the main file. Removes duplicate Include lines anywhere
# in the file and prepends a single canonical one.
ensure_sshd_include_first() {
    local sshd_config="${1:-/etc/ssh/sshd_config}"
    local include_line="Include /etc/ssh/sshd_config.d/*.conf"
    local include_regex='^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/\*\.conf[[:space:]]*$'

    if [ ! -f "$sshd_config" ]; then
        print_error "sshd_config not found: $sshd_config"
        return 1
    fi

    local first_active
    first_active=$(awk 'NF && $1 !~ /^#/ { print; exit }' "$sshd_config")

    if [[ "$first_active" =~ ${include_regex} ]]; then
        # Already first; still strip any duplicate Include lines further down.
        if [ "$(grep -Ec "$include_regex" "$sshd_config")" -gt 1 ]; then
            {
                echo "$include_line"
                grep -Ev "$include_regex" "$sshd_config"
            } | write_file_atomic "$sshd_config" || return 1
            print_message "Removed duplicate Include directives from $sshd_config"
        fi
        return 0
    fi

    {
        echo "$include_line"
        grep -Ev "$include_regex" "$sshd_config"
    } | write_file_atomic "$sshd_config" || return 1

    print_message "Ensured 'Include /etc/ssh/sshd_config.d/*.conf' is the first active directive in $sshd_config"
}

# Ubuntu 24.04+ uses ssh.socket by default and reads Port/ListenAddress from
# sshd_config through sshd-socket-generator during systemctl daemon-reload.
# Keep socket activation where it works; fall back to persistent ssh.service
# only if the requested port is not actually listening.
SSH_SOCKET_ACTIVATION_DISABLED=false
SSH_DISABLED_SOCKET_UNITS=()
SSH_SYSTEMD_MOVED_FILES=()

systemd_unit_exists() {
    local unit="$1"

    systemctl list-unit-files "$unit" --no-legend 2>/dev/null | grep -q . || \
        systemctl cat "$unit" >/dev/null 2>&1
}

backup_and_remove_systemd_file() {
    local file="$1"
    local backup

    [ -f "$file" ] || return 0

    backup="${file}.backup.system-setup.$(date +%Y%m%d-%H%M%S)~"
    if mv "$file" "$backup"; then
        SSH_SYSTEMD_MOVED_FILES+=("${file}|${backup}")
        print_message "Moved $file to $backup"
    else
        print_warning "Failed to move $file; persistent SSH service may stay tied to socket activation"
    fi
}

disable_ssh_socket_if_active() {
    local unit
    local disabled_socket=false

    for unit in ssh.socket sshd.socket; do
        systemd_unit_exists "$unit" || continue

        if systemctl is-active --quiet "$unit" 2>/dev/null; then
            print_warning "$unit is active; it would override the Port directive in sshd_config"
            print_message "Disabling $unit so the configured SSH port takes effect"
            if systemctl disable --now "$unit" 2>/dev/null; then
                disabled_socket=true
                SSH_DISABLED_SOCKET_UNITS+=("$unit")
            else
                print_warning "Failed to disable $unit; SSH port change may not take effect"
            fi
        elif systemctl is-enabled --quiet "$unit" 2>/dev/null; then
            print_message "Disabling $unit (enabled but not active)"
            if systemctl disable "$unit" 2>/dev/null; then
                disabled_socket=true
                SSH_DISABLED_SOCKET_UNITS+=("$unit")
            else
                print_warning "Failed to disable $unit; SSH port change may not persist"
            fi
        fi
    done

    if [ "$disabled_socket" = true ]; then
        SSH_SOCKET_ACTIVATION_DISABLED=true
        print_message "SSH socket activation disabled; persistent SSH service will be enabled"
    fi

    # Some Ubuntu releases used a drop-in that keeps ssh.service tied to
    # ssh.socket. Back it up before persistent daemon fallback.
    backup_and_remove_systemd_file "/etc/systemd/system/ssh.service.d/00-socket.conf"
    backup_and_remove_systemd_file "/etc/systemd/system/sshd.service.d/00-socket.conf"
    systemctl daemon-reload 2>/dev/null || true

    return 0
}

restore_ssh_activation_state() {
    local entry file backup unit

    for entry in "${SSH_SYSTEMD_MOVED_FILES[@]:-}"; do
        [ -n "$entry" ] || continue
        file="${entry%%|*}"
        backup="${entry#*|}"
        if [ -e "$backup" ] || [ -L "$backup" ]; then
            mv -f -- "$backup" "$file" || print_warning "Failed to restore $file"
        fi
    done

    systemctl daemon-reload 2>/dev/null || true
    for unit in "${SSH_DISABLED_SOCKET_UNITS[@]:-}"; do
        [ -n "$unit" ] || continue
        systemctl enable --now "$unit" 2>/dev/null || print_warning "Failed to restore $unit"
    done

    SSH_SYSTEMD_MOVED_FILES=()
    SSH_DISABLED_SOCKET_UNITS=()
    SSH_SOCKET_ACTIVATION_DISABLED=false
}

ssh_port_is_listening() {
    local port="$1"

    if command -v ss >/dev/null 2>&1; then
        ss -H -ltn "sport = :${port}" 2>/dev/null | grep -q .
        return $?
    fi

    if command -v netstat >/dev/null 2>&1; then
        netstat -ltn 2>/dev/null | awk -v p=":${port}" '$4 ~ p "$" { found=1 } END { exit found ? 0 : 1 }'
        return $?
    fi

    return 1
}

restart_ssh_daemon_service() {
    local unit

    for unit in ssh.service sshd.service; do
        systemd_unit_exists "$unit" || continue

        print_message "Enabling persistent SSH service: $unit"
        systemctl enable "$unit" 2>/dev/null || \
            print_warning "Failed to enable $unit; SSH may not survive reboot"

        if systemctl restart "$unit" 2>/dev/null || systemctl start "$unit" 2>/dev/null; then
            print_message "SSH service started/restarted ($unit)"
            return 0
        fi

        print_warning "Failed to start/restart $unit"
    done

    if service ssh restart 2>/dev/null; then
        print_message "SSH service restarted (service ssh)"
        return 0
    fi

    if service sshd restart 2>/dev/null; then
        print_message "SSH service restarted (service sshd)"
        return 0
    fi

    return 1
}

restart_ssh_listener() {
    local port="${1:-22}"
    local unit
    local socket_handled=false

    systemctl daemon-reload 2>/dev/null || true

    if [ "${SSH_SOCKET_ACTIVATION_DISABLED:-false}" = true ]; then
        print_message "Starting SSH through persistent daemon mode"
        if restart_ssh_daemon_service; then
            if ssh_port_is_listening "$port"; then
                print_success "SSH is listening on port $port"
                return 0
            else
                print_warning "SSH service restarted, but port $port is not listening yet"
                print_warning "Check on the server: systemctl status ssh.service sshd.service; journalctl -u ssh.service -u sshd.service"
            fi
            return 1
        fi

        return 1
    fi

    # Ubuntu 24.04/26.04 commonly uses ssh.socket as the primary listener.
    for unit in ssh.socket sshd.socket; do
        systemd_unit_exists "$unit" || continue

        if systemctl is-active --quiet "$unit" 2>/dev/null || \
           systemctl is-enabled --quiet "$unit" 2>/dev/null; then
            socket_handled=true
            print_message "Restarting SSH socket listener: $unit"
            if systemctl enable "$unit" 2>/dev/null; then
                :
            else
                print_warning "Failed to enable $unit"
            fi

            if systemctl restart "$unit" 2>/dev/null || systemctl start "$unit" 2>/dev/null; then
                print_message "SSH socket restarted ($unit)"
                if ssh_port_is_listening "$port"; then
                    print_success "SSH socket is listening on port $port"
                    return 0
                fi
            else
                print_warning "Failed to restart $unit"
            fi
        fi
    done

    if [ "$socket_handled" = true ]; then
        print_warning "SSH socket was handled, but port $port is not listening; falling back to persistent SSH service"
        disable_ssh_socket_if_active
    fi

    if restart_ssh_daemon_service; then
        if ssh_port_is_listening "$port"; then
            print_success "SSH is listening on port $port"
            return 0
        else
            print_warning "SSH service restarted, but port $port is not listening yet"
            print_warning "Check on the server: systemctl status ssh.service sshd.service ssh.socket sshd.socket"
        fi
        return 1
    fi

    return 1
}

# Warn if any sshd_config.d drop-in that is lexicographically earlier than ours
# defines parameters we also set: by "first value wins", the earlier file's
# value will override ours and our selection will be silently ignored.
warn_sshd_dropin_conflicts() {
    local our_dropin="$1"
    local dropin_dir
    dropin_dir=$(dirname -- "$our_dropin")
    local our_basename
    our_basename=$(basename -- "$our_dropin")

    [ -d "$dropin_dir" ] || return 0
    [ -f "$our_dropin" ] || return 0

    local our_params
    our_params=$(awk 'NF && $1 !~ /^#/ {print $1}' "$our_dropin" | sort -u)
    [ -z "$our_params" ] && return 0

    local earlier
    for earlier in "$dropin_dir"/*.conf; do
        [ -f "$earlier" ] || continue
        local earlier_basename
        earlier_basename=$(basename -- "$earlier")
        # Only files that sort BEFORE ours will be parsed first.
        [[ "$earlier_basename" < "$our_basename" ]] || continue

        local param
        for param in $our_params; do
            if grep -qE "^[[:space:]]*${param}[[:space:]]" "$earlier"; then
                local earlier_value our_value
                earlier_value=$(grep -E "^[[:space:]]*${param}[[:space:]]" "$earlier" | head -1 | sed -E "s/^[[:space:]]*${param}[[:space:]]+//")
                our_value=$(grep -E "^[[:space:]]*${param}[[:space:]]" "$our_dropin" | head -1 | sed -E "s/^[[:space:]]*${param}[[:space:]]+//")
                if [ "$earlier_value" != "$our_value" ]; then
                    print_warning "sshd parameter '${param}' is also set in ${earlier_basename} ('${earlier_value}'); that value will WIN over ${our_basename} ('${our_value}')"
                fi
            fi
        done
    done

    return 0
}

default_codename_for_release() {
    local os="$1"
    local version="$2"

    case "${os}:${version}" in
        debian:12) echo "bookworm" ;;
        debian:13) echo "trixie" ;;
        ubuntu:24.04) echo "noble" ;;
        ubuntu:26.04) echo "resolute" ;;
        *) echo "" ;;
    esac
}

# Reusable DNS recovery function
# Called after any operation that may break DNS (IPv6 disable, resolv.conf edits)
# Handles both systemd-resolved and classic resolv.conf setups
ensure_dns_works() {
    local caller_context="${1:-unknown}"
    local RESOLV_FILE="/etc/resolv.conf"
    local resolv_is_symlink=false

    if [ -L "$RESOLV_FILE" ]; then
        resolv_is_symlink=true

    fi

    # Step 1: Configure systemd-resolved with IPv4 upstream DNS (if active)
    # Writing to resolv.conf alone is insufficient when systemd-resolved manages it,
    # because resolved ignores resolv.conf and uses its own config for upstream DNS
    if systemctl is-active systemd-resolved &>/dev/null; then
        local RESOLVED_CONF="/etc/systemd/resolved.conf"
        local RESOLVED_DROP="/etc/systemd/resolved.conf.d"

        # Check if upstream DNS already has IPv4 public DNS configured
        if ! grep -qE "^DNS=.*1\.1\.1\.1" "$RESOLVED_CONF" 2>/dev/null && \
           ! grep -qE "^DNS=.*1\.1\.1\.1" "$RESOLVED_DROP"/*.conf 2>/dev/null; then

            mkdir -p "$RESOLVED_DROP"
            cat > "${RESOLVED_DROP}/ipv4-dns.conf" << 'DNSEOF'
[Resolve]
DNS=1.1.1.1 8.8.8.8
FallbackDNS=1.0.0.1 8.8.4.4
DNSEOF
            print_message "[$caller_context] Configured systemd-resolved with IPv4 DNS"
        fi

        systemctl restart systemd-resolved
        sleep 1

        # Flush caches
        resolvectl flush-caches 2>/dev/null || true
    fi

    # Step 2: Ensure resolv.conf has real IPv4 nameservers (not just 127.0.0.53 stub).
    # Do not replace systemd-resolved-managed symlinks; doing so silently disables
    # resolved integration on Ubuntu/Debian systems using the recommended layout.
    if [ "$resolv_is_symlink" = true ]; then
        print_message "[$caller_context] resolv.conf is manager-owned; leaving symlink intact"
    elif [ -f "$RESOLV_FILE" ]; then
        # Check for real (non-loopback) IPv4 nameservers
        if ! grep -qE "^[[:space:]]*nameserver[[:space:]]+(1\.1\.1\.1|8\.8\.8\.8|1\.0\.0\.1|8\.8\.4\.4)" "$RESOLV_FILE"; then
            cp "$RESOLV_FILE" "${RESOLV_FILE}.backup.dns.$(date +%Y%m%d-%H%M%S)~" 2>/dev/null || true
            # Remove IPv6 nameservers (addresses containing ":")
            grep -vE "^[[:space:]]*nameserver[[:space:]]+[0-9a-fA-F]*:" "$RESOLV_FILE" > "${RESOLV_FILE}.tmp" 2>/dev/null || true
            # Add public IPv4 DNS
            echo "nameserver 1.1.1.1" >> "${RESOLV_FILE}.tmp"
            echo "nameserver 8.8.8.8" >> "${RESOLV_FILE}.tmp"
            mv "${RESOLV_FILE}.tmp" "$RESOLV_FILE"
            print_message "[$caller_context] Added 1.1.1.1 and 8.8.8.8 to resolv.conf"
        fi
    fi

    # Step 3: Verify DNS actually works (with retry)
    sleep 1
    local dns_ok=false
    for domain in deb.debian.org archive.ubuntu.com google.com; do
        if getent hosts "$domain" &>/dev/null; then
            dns_ok=true
            break
        fi
    done

    if [ "$dns_ok" = true ]; then
        print_success "[$caller_context] DNS resolution verified"
    else
        if [ "$resolv_is_symlink" = true ]; then
            print_warning "[$caller_context] DNS failed with manager-owned resolv.conf; not overwriting symlink"
        else
            print_warning "[$caller_context] DNS resolution failed, forcing direct nameservers..."
            # Last resort: overwrite resolv.conf completely with known-good DNS
            cp "$RESOLV_FILE" "${RESOLV_FILE}.backup.force.$(date +%Y%m%d-%H%M%S)~" 2>/dev/null || true
            # Preserve non-nameserver lines (search, options, etc.)
            grep -vE "^[[:space:]]*nameserver" "$RESOLV_FILE" > "${RESOLV_FILE}.tmp" 2>/dev/null || true
            echo "nameserver 1.1.1.1" >> "${RESOLV_FILE}.tmp"
            echo "nameserver 8.8.8.8" >> "${RESOLV_FILE}.tmp"
            echo "nameserver 1.0.0.1" >> "${RESOLV_FILE}.tmp"
            mv "${RESOLV_FILE}.tmp" "$RESOLV_FILE"
        fi

        # If systemd-resolved is active, stop it temporarily so resolv.conf is used directly
        if systemctl is-active systemd-resolved &>/dev/null; then
            print_warning "[$caller_context] Restarting systemd-resolved with new config..."
            systemctl restart systemd-resolved
            sleep 2
        fi

        # Final verification
        if getent hosts deb.debian.org &>/dev/null || getent hosts archive.ubuntu.com &>/dev/null; then
            print_success "[$caller_context] DNS resolution recovered"
        else
            print_warning "[$caller_context] DNS may still have issues. Continuing anyway..."
        fi
    fi
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run as root"
    exit 1
fi

configure_apt_lock_timeout || print_warning "Could not set an APT lock timeout; package steps may fail while another package manager runs"

# Detect if running interactively. When launched through a downloader wrapper,
# stdin can be a pipe even though the user has a real terminal available.
if [ -t 0 ]; then
    INTERACTIVE=true
elif { exec 9</dev/tty; } 2>/dev/null; then
    exec 0<&9 9<&-
    INTERACTIVE=true
    print_message "Attached to /dev/tty for interactive prompts"
else
    INTERACTIVE=false
    print_warning "Running in non-interactive mode with default settings"
fi

# ─── Load nftables profiles configuration ─────────────────────────────────
# Try external config first (repo checkout), fall back to embedded defaults.
# To modify profiles, edit config/nftables-profiles.conf
#
# The external file is still Bash array syntax for backwards compatibility,
# but it is treated as data-only: every non-comment line is validated before
# sourcing so arbitrary shell code cannot run from a downloaded/modified file.
_NFT_PROFILES_LOADED=false
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || _SCRIPT_DIR=""

validate_nft_profiles_config() {
    local config_file="$1"
    local line stripped value
    bash -n "$config_file" || return 1

    while IFS= read -r line || [ -n "$line" ]; do
        stripped="${line#"${line%%[![:space:]]*}"}"
        stripped="${stripped%"${stripped##*[![:space:]]}"}"

        [ -z "$stripped" ] && continue
        [[ "$stripped" =~ ^# ]] && continue
        [[ "$stripped" == "#!/usr/bin/env bash" || "$stripped" == "#!/bin/bash" ]] && continue
        [[ "$stripped" =~ ^NFT_PROFILES_COUNT=[0-9]+$ ]] && continue
        [[ "$stripped" =~ ^NFT_DEFAULT_PROFILE=[0-9]+$ ]] && continue
        [[ "$stripped" =~ ^NFT_PROFILE_(NAMES|DESCRIPTIONS|CONFIGS|LOGSCRIPTS)\+?=\($ ]] && continue
        [[ "$stripped" == ")" ]] && continue

        if [[ "$stripped" =~ ^\[[0-9]+\]=\"(.*)\"$ ]]; then
            value="${BASH_REMATCH[1]}"
            if [[ "$value" =~ [\"\$\`\;\&\|\<\>\\] ]]; then
                print_warning "Unsafe value in nftables profiles config: $config_file"
                return 1
            fi
            continue
        fi

        print_warning "Unsupported line in nftables profiles config: $stripped"
        return 1
    done < "$config_file"

    return 0
}

if [ -n "$_SCRIPT_DIR" ] && [ -f "${_SCRIPT_DIR}/config/nftables-profiles.conf" ]; then
    if validate_nft_profiles_config "${_SCRIPT_DIR}/config/nftables-profiles.conf"; then
        . "${_SCRIPT_DIR}/config/nftables-profiles.conf"
        _NFT_PROFILES_LOADED=true
    else
        print_warning "Ignoring unsafe nftables profiles config; embedded defaults will be used"
    fi
fi

# Embedded fallback — used when script is downloaded standalone (via install.sh)
if [ "$_NFT_PROFILES_LOADED" != true ]; then
    NFT_PROFILES_COUNT=7
    NFT_DEFAULT_PROFILE=4

    # ── Relay v4 family ──
    NFT_PROFILE_NAMES=( [1]="relay-v4" [2]="relay-v4-eth0" [3]="relay-v4-net0" )
    NFT_PROFILE_DESCRIPTIONS=(
        [1]="relay-v4       — relay host v4"
        [2]="relay-v4-eth0  — relay host v4 + eth0 iface"
        [3]="relay-v4-net0  — relay host v4 + net0 iface"
    )
    NFT_PROFILE_CONFIGS=(
        [1]="relay_host_nftables_v4.conf"
        [2]="relay_host_nftables_v4_eth0.conf"
        [3]="relay_host_nftables_v4_net0.conf"
    )
    NFT_PROFILE_LOGSCRIPTS=(
        [1]="relay_host_nftables_v4.sh"
        [2]="relay_host_nftables_v4_eth0.sh"
        [3]="relay_host_nftables_v4_net0.sh"
    )

    # ── GE Docker host family ──
    NFT_PROFILE_NAMES+=( [4]="ge-docker-v4" [5]="ge-docker-v4-eth0" [6]="ge-docker-v5" )
    NFT_PROFILE_NAMES+=( [7]="nl-nginx-v4" )
    NFT_PROFILE_DESCRIPTIONS+=(
        [4]="ge-docker-v4       — GE Docker host v4 (default)"
        [5]="ge-docker-v4-eth0  — GE Docker host v4 + eth0 iface"
        [6]="ge-docker-v5       — GE Docker host v5"
        [7]="nl-nginx-v4        — NL nginx host v4"
    )
    NFT_PROFILE_CONFIGS+=(
        [4]="ge_docker_host_nftables_v4.conf"
        [5]="ge_docker_host_nftables_v4_eth0.conf"
        [6]="ge_docker_host_nftables_v5.conf"
        [7]="nl_nginx_host_nftables_v4.conf"
    )
    NFT_PROFILE_LOGSCRIPTS+=(
        [4]="ge_docker_host_nftables_v4.sh"
        [5]="ge_docker_host_nftables_v4_eth0.sh"
        [6]="ge_docker_host_nftables_v5.sh"
        [7]="nl_nginx_host_nftables_v4.sh"
    )
fi
unset _NFT_PROFILES_LOADED _SCRIPT_DIR

verify_nft_profile_assets() {
    local nft_dir="${1:-/opt/nftables}"
    local missing=false
    local i conf_file log_file

    for i in $(seq 1 "$NFT_PROFILES_COUNT"); do
        conf_file="${NFT_PROFILE_CONFIGS[$i]:-}"
        log_file="${NFT_PROFILE_LOGSCRIPTS[$i]:-}"

        if [ -z "$conf_file" ] || [ ! -s "${nft_dir}/${conf_file}" ]; then
            print_warning "Missing nftables profile config: ${nft_dir}/${conf_file:-<empty>}"
            missing=true
        fi

        if [ -n "$log_file" ] && [ ! -s "${nft_dir}/logging/${log_file}" ]; then
            print_warning "Missing nftables logging script: ${nft_dir}/logging/${log_file}"
            missing=true
        fi
    done

    [ "$missing" = false ]
}

disable_ufw_firewall() {
    local preserve_runtime_rules="${1:-false}"
    local ufw_status
    local ufw_disabled_ok=true
    local ufw_enabled_state

    print_message "Step 1: Checking UFW status..."
    if ! dpkg-query -W -f='${Status}' ufw 2>/dev/null | grep -q "install ok installed"; then
        print_message "UFW is not installed — skipping"
        return 0
    fi

    print_message "UFW package is installed"
    if command -v ufw &>/dev/null; then
        ufw_status=$(ufw status 2>/dev/null | head -1 || true)
        ufw_status=${ufw_status:-unknown}
        print_message "UFW status: $ufw_status"

        if [ "$preserve_runtime_rules" = true ]; then
            print_message "Keeping the current UFW runtime rules until nftables is atomically committed"
        elif echo "$ufw_status" | grep -qiE '^Status:[[:space:]]+active([[:space:]]|$)'; then
            print_message "Disabling UFW firewall..."
            if ufw disable; then
                print_message "UFW disabled"
            else
                print_warning "ufw disable returned an error; continuing with systemd disable/mask"
            fi
        else
            print_message "UFW is not active — skipping ufw disable, continuing with systemd disable/mask"
        fi
    else
        print_warning "UFW package is installed but ufw command was not found"
    fi

    if ! command -v systemctl &>/dev/null; then
        print_error "systemctl not found; cannot fully disable/mask UFW service"
        return 1
    fi

    # Stop, disable and mask UFW to prevent any future activation.
    # mask creates a symlink to /dev/null — strongest form of disable.
    print_message "Disabling and masking UFW service..."
    if [ "$preserve_runtime_rules" != true ] && ! systemctl stop ufw.service 2>/dev/null; then
        print_warning "systemctl stop ufw.service returned an error"
    fi
    if ! systemctl disable ufw.service 2>/dev/null; then
        print_warning "systemctl disable ufw.service returned an error"
    fi
    if ! systemctl mask ufw.service 2>/dev/null; then
        print_warning "systemctl mask ufw.service returned an error; verifying final state"
    fi
    systemctl daemon-reload 2>/dev/null || true

    if [ "$preserve_runtime_rules" != true ] && systemctl is-active --quiet ufw.service 2>/dev/null; then
        print_error "UFW service is still active after disable attempt"
        ufw_disabled_ok=false
    fi

    ufw_enabled_state=$(systemctl is-enabled ufw.service 2>/dev/null || true)
    if [ "$ufw_enabled_state" != "masked" ]; then
        print_error "UFW service is not masked (state: ${ufw_enabled_state:-unknown})"
        ufw_disabled_ok=false
    fi

    if [ "$ufw_disabled_ok" = true ]; then
        if [ "$preserve_runtime_rules" = true ]; then
            print_success "UFW service: disabled and masked; runtime rules left untouched"
        else
            print_success "UFW service: stopped, disabled, masked and verified"
        fi
        return 0
    fi

    print_error "UFW was not fully disabled; nftables setup will roll back"
    return 1
}

build_nft_transaction() {
    local source_file="$1"
    local transaction_file="$2"

    {
        printf 'flush ruleset\n'
        # A shebang is valid only as the first line of a script. Once the file is
        # embedded in this transaction it is unnecessary, so strip it.
        sed '1{/^#!/d;}' "$source_file"
    } > "$transaction_file"
}

restore_live_nft_ruleset() {
    local live_backup="$1"
    local rollback_file="$2"

    [ -f "$live_backup" ] || return 1
    build_nft_transaction "$live_backup" "$rollback_file" || return 1
    nft -c -f "$rollback_file" >/dev/null 2>&1 || return 1
    nft -f "$rollback_file"
}

# Print banner
echo ""
print_header "╔═══════════════════════════════════════════════╗"
print_header "║   Debian/Ubuntu System Setup Script v${SCRIPT_VERSION}    ║"
print_header "║   Enhanced Configuration Tool                 ║"
print_header "╚═══════════════════════════════════════════════╝"
echo ""

# ============================================
# INITIAL CONFIGURATION PROMPTS
# ============================================

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION=$VERSION_ID
    DETECTED_OS="$OS"
else
    DETECTED_OS=""
fi

# If OS cannot be detected, ask user to choose (only in interactive mode)
if [ -z "$DETECTED_OS" ] || ( [ "$OS" != "debian" ] && [ "$OS" != "ubuntu" ] ); then
    if [ "$INTERACTIVE" = true ]; then
        print_warning "Cannot detect OS or OS is not supported"
        echo ""
        print_message "Please select the operating system:"
        echo "  1) Debian 12 (Bookworm)"
        echo "  2) Debian 13 (Trixie)"
        echo "  3) Ubuntu 24.04 LTS (Noble)"
        echo "  4) Ubuntu 26.04 LTS (Resolute)"
        echo ""
        prompt_read -r -p "Enter your choice [1-4]: " OS_CHOICE
        
        case $OS_CHOICE in
            1)
                OS="debian"
                VERSION="12"
                VERSION_CODENAME="bookworm"
                print_message "Selected: Debian 12 (Bookworm)"
                ;;
            2)
                OS="debian"
                VERSION="13"
                VERSION_CODENAME="trixie"
                print_message "Selected: Debian 13 (Trixie)"
                ;;
            3)
                OS="ubuntu"
                VERSION="24.04"
                VERSION_CODENAME="noble"
                print_message "Selected: Ubuntu 24.04 LTS (Noble)"
                ;;
            4)
                OS="ubuntu"
                VERSION="26.04"
                VERSION_CODENAME="resolute"
                print_message "Selected: Ubuntu 26.04 LTS (Resolute)"
                ;;
            *)
                print_error "Invalid choice. Exiting."
                exit 1
                ;;
        esac
    else
        print_error "Cannot detect OS and running in non-interactive mode"
        print_error "Please run the script locally: sudo bash system-setup.sh"
        exit 1
    fi
else
    print_message "Detected OS: $OS $VERSION"
    VERSION_CODENAME=${VERSION_CODENAME:-$(default_codename_for_release "$OS" "$VERSION")}
    VERSION_CODENAME=${VERSION_CODENAME:-unknown}
    
    # Validate OS
    if [ "$OS" != "debian" ] && [ "$OS" != "ubuntu" ]; then
        print_error "This script only supports Debian and Ubuntu"
        exit 1
    fi
    
    # Validate version
    if [ "$OS" = "debian" ]; then
        if [ "$VERSION" != "12" ] && [ "$VERSION" != "13" ]; then
            print_warning "Detected Debian version: $VERSION (officially supported: 12, 13)"
            if [ "$INTERACTIVE" = true ]; then
                prompt_read -r -p "Continue anyway? (y/N): " CONTINUE_ANYWAY
                CONTINUE_ANYWAY=${CONTINUE_ANYWAY:-n}
                if [ "$CONTINUE_ANYWAY" != "y" ] && [ "$CONTINUE_ANYWAY" != "Y" ]; then
                    exit 1
                fi
            else
                print_error "Unsupported Debian version in non-interactive mode"
                exit 1
            fi
        fi
    elif [ "$OS" = "ubuntu" ]; then
        if [ "$VERSION" != "24.04" ] && [ "$VERSION" != "26.04" ]; then
            print_warning "Detected Ubuntu version: $VERSION (officially supported: 24.04 LTS, 26.04 LTS)"
            if [ "$INTERACTIVE" = true ]; then
                prompt_read -r -p "Continue anyway? (y/N): " CONTINUE_ANYWAY
                CONTINUE_ANYWAY=${CONTINUE_ANYWAY:-n}
                if [ "$CONTINUE_ANYWAY" != "y" ] && [ "$CONTINUE_ANYWAY" != "Y" ]; then
                    exit 1
                fi
            else
                print_error "Unsupported Ubuntu version in non-interactive mode"
                exit 1
            fi
        fi
    fi
fi

echo ""

# ============================================
# INTERACTIVE CONFIGURATION SELECTION
# ============================================

print_header "═══════════════════════════════════════════════"
print_header "   Configuration Options"
print_header "═══════════════════════════════════════════════"
echo ""

if [ "$INTERACTIVE" = true ]; then
    # Ask about RustDesk installation
    print_header "───────────────────────────────────────────────"
    print_header "   RustDesk Server (Docker)"
    print_header "───────────────────────────────────────────────"
    echo ""
    print_message "Install RustDesk server in Docker?"
    print_message "  - Creates /opt/rustdesk with docker-compose.yml"
    print_message "  - Registers systemd service (rustdesk-compose.service)"
    print_message "  - Containers: hbbs (signal) + hbbr (relay)"
    prompt_read -r -p "Install RustDesk? (y/N): " INSTALL_RUSTDESK
    INSTALL_RUSTDESK=${INSTALL_RUSTDESK:-n}

    # Ask about weekly auto-update timer (only when RustDesk is being installed)
    if [ "$INSTALL_RUSTDESK" = "y" ] || [ "$INSTALL_RUSTDESK" = "Y" ]; then
        echo ""
        print_message "Install weekly auto-update for RustDesk containers?"
        print_message "  - Creates rustdesk-update.service + rustdesk-update.timer"
        print_message "  - Runs every Sunday at 04:00 (with ±1h random delay)"
        print_message "  - Resolves an immutable image digest, verifies health, and rolls back on failure"
        prompt_read -r -p "Install weekly auto-update timer? (Y/n): " INSTALL_RUSTDESK_UPDATE
        INSTALL_RUSTDESK_UPDATE=${INSTALL_RUSTDESK_UPDATE:-y}
    else
        INSTALL_RUSTDESK_UPDATE="n"
    fi

    echo ""

    # Ask about extracting opt.7z archive
    print_header "───────────────────────────────────────────────"
    print_header "   Additional Files (opt.7z)"
    print_header "───────────────────────────────────────────────"
    echo ""
    print_message "Extract additional files to /opt?"
    print_message "  - Downloads opt.7z and copies contents to /opt"
    print_message "  - Scripts in 'scripts' subfolder will be made executable"
    prompt_read -r -p "Extract opt.7z to /opt? (y/N): " EXTRACT_OPT_ARCHIVE
    EXTRACT_OPT_ARCHIVE=${EXTRACT_OPT_ARCHIVE:-n}

    if [ "$EXTRACT_OPT_ARCHIVE" = "y" ] || [ "$EXTRACT_OPT_ARCHIVE" = "Y" ]; then
        print_message "The archive is password-protected. Please enter the password:"
        prompt_read -r -s -p "Password: " OPT_ARCHIVE_PASSWORD
        echo ""
        if [ -z "$OPT_ARCHIVE_PASSWORD" ]; then
            print_warning "No password provided. opt.7z will not be extracted."
            EXTRACT_OPT_ARCHIVE="n"
        else
            print_message "Password saved. Archive will be extracted during installation."
        fi
    else
        OPT_ARCHIVE_PASSWORD=""
    fi

    echo ""

    # Ask about root password
    print_header "───────────────────────────────────────────────"
    print_header "   Users and Access"
    print_header "───────────────────────────────────────────────"
    echo ""
    print_message "Set a password for root user?"
    prompt_read -r -p "Set root password? (y/N): " SET_ROOT_PASSWORD
    SET_ROOT_PASSWORD=${SET_ROOT_PASSWORD:-n}
    
    if [ "$SET_ROOT_PASSWORD" = "y" ] || [ "$SET_ROOT_PASSWORD" = "Y" ]; then
        while true; do
            prompt_read -r -s -p "Enter new root password: " ROOT_PASSWORD
            echo ""
            prompt_read -r -s -p "Confirm root password: " ROOT_PASSWORD_CONFIRM
            echo ""
            
            if [ "$ROOT_PASSWORD" = "$ROOT_PASSWORD_CONFIRM" ]; then
                if [ -z "$ROOT_PASSWORD" ]; then
                    print_warning "Password cannot be empty"
                    continue
                fi
                print_message "Root password will be set"
                break
            else
                print_warning "Passwords do not match. Please try again."
            fi
        done
    else
        ROOT_PASSWORD=""
    fi
    
    echo ""
    
    # Ask about creating new user
    print_message "Do you want to create a new user?"
    prompt_read -r -p "Create new user? (y/N): " CREATE_USER
    CREATE_USER=${CREATE_USER:-n}
    
    if [ "$CREATE_USER" = "y" ] || [ "$CREATE_USER" = "Y" ]; then
        prompt_read -r -p "Enter username for new user: " NEW_USERNAME
        
        if [ -z "$NEW_USERNAME" ]; then
            print_error "Username cannot be empty"
            CREATE_USER="n"
        elif ! [[ "$NEW_USERNAME" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]]; then
            print_error "Invalid username: $NEW_USERNAME"
            print_error "Use a Debian-compatible username: start with a lowercase letter or underscore, then lowercase letters, digits, underscores or hyphens"
            CREATE_USER="n"
            NEW_USERNAME=""
        else
            # Check if user already exists
            if id "$NEW_USERNAME" &>/dev/null; then
                print_warning "User $NEW_USERNAME already exists"
                prompt_read -r -p "Continue with existing user? (y/N): " USE_EXISTING
                USE_EXISTING=${USE_EXISTING:-n}
                
                if [ "$USE_EXISTING" != "y" ] && [ "$USE_EXISTING" != "Y" ]; then
                    CREATE_USER="n"
                    NEW_USERNAME=""
                else
                    CREATE_USER="existing"
                fi
            else
                while true; do
                    prompt_read -r -s -p "Enter password for $NEW_USERNAME: " NEW_USER_PASSWORD
                    echo ""
                    prompt_read -r -s -p "Confirm password: " NEW_USER_PASSWORD_CONFIRM
                    echo ""
                    
                    if [ "$NEW_USER_PASSWORD" = "$NEW_USER_PASSWORD_CONFIRM" ]; then
                        if [ -z "$NEW_USER_PASSWORD" ]; then
                            print_warning "Password cannot be empty"
                            continue
                        fi
                        print_message "User $NEW_USERNAME will be created"
                        break
                    else
                        print_warning "Passwords do not match. Please try again."
                    fi
                done
            fi
        fi
    else
        NEW_USERNAME=""
        NEW_USER_PASSWORD=""
    fi
    
    echo ""
    
    # Ask about SSH key for new user
    if [ ! -z "$NEW_USERNAME" ]; then
        print_message "Do you want to configure SSH key for $NEW_USERNAME?"
        prompt_read -r -p "Configure SSH key? (y/N): " CONFIGURE_USER_SSH_KEY
        CONFIGURE_USER_SSH_KEY=${CONFIGURE_USER_SSH_KEY:-n}
        
        if [ "$CONFIGURE_USER_SSH_KEY" = "y" ] || [ "$CONFIGURE_USER_SSH_KEY" = "Y" ]; then
            echo ""
            print_message "Enter SSH public key for $NEW_USERNAME"
            print_message "Example: ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAAB..."
            prompt_read -r -p "SSH public key: " USER_SSH_KEY
            
            if [ -z "$USER_SSH_KEY" ]; then
                print_warning "No SSH key provided, skipping SSH key configuration"
                CONFIGURE_USER_SSH_KEY="n"
            fi
        else
            USER_SSH_KEY=""
        fi
    else
        CONFIGURE_USER_SSH_KEY="n"
        USER_SSH_KEY=""
    fi
    
    echo ""
    
    # Ask about zsh installation for new user
    if [ ! -z "$NEW_USERNAME" ]; then
        print_message "Do you want to install and configure zsh with Oh My Zsh for $NEW_USERNAME?"
        prompt_read -r -p "Install zsh? (y/N): " INSTALL_ZSH
        INSTALL_ZSH=${INSTALL_ZSH:-n}
    else
        INSTALL_ZSH="n"
    fi
    
    echo ""
    
    # Ask about crontab configuration
    print_message "Do you want to configure crontab for root?"
    prompt_read -r -p "Configure crontab? (y/N): " CONFIGURE_CRONTAB
    CONFIGURE_CRONTAB=${CONFIGURE_CRONTAB:-n}
    
    if [ "$CONFIGURE_CRONTAB" = "y" ] || [ "$CONFIGURE_CRONTAB" = "Y" ]; then
        echo ""
        print_message "Crontab configuration mode:"
        print_message "You can add multiple cron tasks after the environment variables"
        print_message "1) Enter tasks manually (line by line)"
        print_message "2) Paste tasks from clipboard (recommended for multiple tasks)"
        print_message "3) Skip adding tasks (only set environment variables)"
        echo ""
        prompt_read -r -p "Choose option [1-3] (default: 3): " CRONTAB_MODE
        CRONTAB_MODE=${CRONTAB_MODE:-3}
        
        case $CRONTAB_MODE in
            1)
                print_message "Enter cron tasks line by line"
                print_message "Format: minute hour day month weekday command"
                print_message "Example: 0 2 * * * /root/backup.sh"
                print_message "Press CTRL+D when finished"
                echo ""
                CRONTAB_TASKS=""
                while IFS= read -r line; do
                    if [ ! -z "$line" ]; then
                        CRONTAB_TASKS="${CRONTAB_TASKS}${line}"$'\n'
                    fi
                done
                ;;
            2)
                print_message "Paste your cron tasks from clipboard"
                print_message "After pasting, type 'END' on a new line and press ENTER to finish"
                print_message ""
                print_message "Format: minute hour day month weekday command"
                print_message "Example:"
                print_message "  0 2 * * * /root/backup.sh"
                print_message "  */5 * * * * /root/check.sh"
                print_message "  @reboot /root/startup.sh"
                print_message ""
                print_message "Paste now and type END when done:"
                echo ""
                CRONTAB_TASKS=""
                while IFS= read -r line; do
                    # Stop on END marker
                    if [ "$line" = "END" ] || [ "$line" = "end" ]; then
                        break
                    fi
                    # Add line (including empty lines if they're part of the paste)
                    CRONTAB_TASKS="${CRONTAB_TASKS}${line}"$'\n'
                done
                
                # Remove trailing newline if exists
                CRONTAB_TASKS="${CRONTAB_TASKS%$'\n'}"
                
                if [ -z "$CRONTAB_TASKS" ]; then
                    print_warning "No tasks entered"
                else
                    # Count non-empty lines
                    TASK_COUNT=$(echo "$CRONTAB_TASKS" | grep -c -v '^[[:space:]]*$')
                    print_message "Captured $TASK_COUNT cron task(s)"
                fi
                ;;
            3)
                print_message "Skipping cron tasks - only environment variables will be set"
                CRONTAB_TASKS=""
                ;;
            *)
                print_warning "Invalid option. Skipping cron tasks."
                CRONTAB_TASKS=""
                ;;
        esac
    else
        CRONTAB_TASKS=""
    fi
    
    echo ""
    
    # Ask about SSH configuration
    print_header "───────────────────────────────────────────────"
    print_header "   SSH Configuration"
    print_header "───────────────────────────────────────────────"
    echo ""
    print_message "Configure SSH (change port, AllowUsers, authentication)?"
    prompt_read -r -p "Configure SSH? (y/N): " CONFIGURE_SSH
    CONFIGURE_SSH=${CONFIGURE_SSH:-n}
    
    if [ "$CONFIGURE_SSH" = "y" ] || [ "$CONFIGURE_SSH" = "Y" ]; then
        while true; do
            prompt_read -r -p "Enter new SSH port (default 22): " SSH_PORT
            SSH_PORT=${SSH_PORT:-22}

            # Validate port number
            if [[ "$SSH_PORT" =~ ^[0-9]+$ ]] && [ "$SSH_PORT" -ge 1 ] && [ "$SSH_PORT" -le 65535 ]; then
                # Check if port is already in use
                if ss -tuln | grep -q ":${SSH_PORT} "; then
                    print_warning "Port $SSH_PORT is already in use by another service"
                    prompt_read -r -p "Continue anyway? (y/N): " CONTINUE_PORT
                    if [ "$CONTINUE_PORT" = "y" ] || [ "$CONTINUE_PORT" = "Y" ]; then
                        break
                    fi
                else
                    break
                fi
            else
                print_error "Invalid port number. Must be between 1 and 65535"
            fi
        done

        echo ""
        print_message "Enter usernames for AllowUsers (space-separated, leave empty to skip)"
        print_message "Example: user1 user2 user3"
        if [ ! -z "$NEW_USERNAME" ]; then
            print_message "Suggestion: $NEW_USERNAME"
        fi
        prompt_read -r -p "AllowUsers: " SSH_ALLOW_USERS

        # Validate users exist
        if [ ! -z "$SSH_ALLOW_USERS" ]; then
            INVALID_USERS=""
            for username in $SSH_ALLOW_USERS; do
                if [ "$username" != "$NEW_USERNAME" ] && ! id "$username" &>/dev/null; then
                    INVALID_USERS="$INVALID_USERS $username"
                fi
            done

            if [ ! -z "$INVALID_USERS" ]; then
                print_warning "The following users do not exist:$INVALID_USERS"
                print_warning "Setting AllowUsers with non-existent users may lock you out of SSH!"
                prompt_read -r -p "Continue anyway? (y/N): " CONTINUE_USERS
                if [ "$CONTINUE_USERS" != "y" ] && [ "$CONTINUE_USERS" != "Y" ]; then
                    SSH_ALLOW_USERS=""
                    print_message "AllowUsers configuration skipped"
                fi
            fi
        fi

        echo ""
        print_header "Advanced SSH Security Parameters"
        print_message "Configure additional SSH security settings"
        echo ""
        
        # PubkeyAuthentication
        print_message "PubkeyAuthentication - Enable public key authentication"
        prompt_read -r -p "Configure PubkeyAuthentication? (y/N): " CONFIG_PUBKEY
        CONFIG_PUBKEY=${CONFIG_PUBKEY:-n}
        if [ "$CONFIG_PUBKEY" = "y" ] || [ "$CONFIG_PUBKEY" = "Y" ]; then
            prompt_read -r -p "Set PubkeyAuthentication to yes or no? (Y/n): " SSH_PUBKEY_AUTH
            SSH_PUBKEY_AUTH=${SSH_PUBKEY_AUTH:-y}
            if [[ "${SSH_PUBKEY_AUTH,,}" =~ ^(y|yes)$ ]]; then
                SSH_PUBKEY_AUTH="yes"
            else
                SSH_PUBKEY_AUTH="no"
            fi
        else
            SSH_PUBKEY_AUTH=""
        fi
        
        # PasswordAuthentication
        print_message "PasswordAuthentication - Enable password authentication"
        prompt_read -r -p "Configure PasswordAuthentication? (y/N): " CONFIG_PASSWORD
        CONFIG_PASSWORD=${CONFIG_PASSWORD:-n}
        if [ "$CONFIG_PASSWORD" = "y" ] || [ "$CONFIG_PASSWORD" = "Y" ]; then
            prompt_read -r -p "Set PasswordAuthentication to yes or no? (Y/n): " SSH_PASSWORD_AUTH
            SSH_PASSWORD_AUTH=${SSH_PASSWORD_AUTH:-y}
            if [[ "${SSH_PASSWORD_AUTH,,}" =~ ^(y|yes)$ ]]; then
                SSH_PASSWORD_AUTH="yes"
            else
                SSH_PASSWORD_AUTH="no"
            fi
        else
            SSH_PASSWORD_AUTH=""
        fi
        
        # PermitEmptyPasswords - ALWAYS set to no, only ask about uncommenting
        print_message "PermitEmptyPasswords - Prevent empty password authentication (ALWAYS set to 'no')"
        prompt_read -r -p "Configure PermitEmptyPasswords? (y/N): " CONFIG_EMPTY_PASS
        CONFIG_EMPTY_PASS=${CONFIG_EMPTY_PASS:-n}
        if [ "$CONFIG_EMPTY_PASS" = "y" ] || [ "$CONFIG_EMPTY_PASS" = "Y" ]; then
            SSH_EMPTY_PASSWORDS="no"  # ALWAYS no for security
        else
            SSH_EMPTY_PASSWORDS=""
        fi
        
        # PermitRootLogin
        print_message "PermitRootLogin - Allow root user to login via SSH"
        prompt_read -r -p "Configure PermitRootLogin? (y/N): " CONFIG_ROOT_LOGIN
        CONFIG_ROOT_LOGIN=${CONFIG_ROOT_LOGIN:-n}
        if [ "$CONFIG_ROOT_LOGIN" = "y" ] || [ "$CONFIG_ROOT_LOGIN" = "Y" ]; then
            prompt_read -r -p "Set PermitRootLogin to yes or no? (Y/n): " SSH_ROOT_LOGIN
            SSH_ROOT_LOGIN=${SSH_ROOT_LOGIN:-y}
            if [[ "${SSH_ROOT_LOGIN,,}" =~ ^(y|yes)$ ]]; then
                SSH_ROOT_LOGIN="yes"
            else
                SSH_ROOT_LOGIN="no"
            fi
        else
            SSH_ROOT_LOGIN=""
        fi

        # PrintMotd
        print_message "PrintMotd - Display /etc/motd content on SSH login"
        prompt_read -r -p "Configure PrintMotd? (y/N): " CONFIG_PRINT_MOTD
        CONFIG_PRINT_MOTD=${CONFIG_PRINT_MOTD:-n}
        if [ "$CONFIG_PRINT_MOTD" = "y" ] || [ "$CONFIG_PRINT_MOTD" = "Y" ]; then
            prompt_read -r -p "Set PrintMotd to yes or no? (Y/n): " SSH_PRINT_MOTD
            SSH_PRINT_MOTD=${SSH_PRINT_MOTD:-y}
            if [[ "${SSH_PRINT_MOTD,,}" =~ ^(y|yes)$ ]]; then
                SSH_PRINT_MOTD="yes"
            else
                SSH_PRINT_MOTD="no"
            fi
        else
            SSH_PRINT_MOTD=""
        fi
    else
        SSH_PORT="22"
        SSH_ALLOW_USERS=""
        SSH_PUBKEY_AUTH=""
        SSH_PASSWORD_AUTH=""
        SSH_EMPTY_PASSWORDS=""
        SSH_ROOT_LOGIN=""
        SSH_PRINT_MOTD=""
    fi

    echo ""
    print_header "───────────────────────────────────────────────"
    print_header "   YubiKey / FIDO2 SSH Authentication"
    print_header "───────────────────────────────────────────────"
    echo ""
    print_message "Configure SSH login with a YubiKey-backed FIDO2 public key?"
    print_message "  - Installs OpenSSH/FIDO2 support packages"
    print_message "  - Adds sk-ssh-ed25519@openssh.com or sk-ecdsa-sha2-nistp256@openssh.com key to authorized_keys"
    print_message "  - Enables PubkeyAuthentication in sshd"
    prompt_read -r -p "Configure YubiKey/FIDO2 SSH? (y/N): " CONFIGURE_YUBIKEY_SSH
    CONFIGURE_YUBIKEY_SSH=${CONFIGURE_YUBIKEY_SSH:-n}

    if [ "$CONFIGURE_YUBIKEY_SSH" = "y" ] || [ "$CONFIGURE_YUBIKEY_SSH" = "Y" ]; then
        if [ -n "$NEW_USERNAME" ]; then
            YUBIKEY_SSH_DEFAULT_USER="$NEW_USERNAME"
        elif [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
            YUBIKEY_SSH_DEFAULT_USER="$SUDO_USER"
        else
            YUBIKEY_SSH_DEFAULT_USER="root"
        fi

        prompt_read -r -p "Target user for YubiKey SSH (default: ${YUBIKEY_SSH_DEFAULT_USER}): " YUBIKEY_SSH_USER
        YUBIKEY_SSH_USER=${YUBIKEY_SSH_USER:-$YUBIKEY_SSH_DEFAULT_USER}

        echo ""
        print_message "Paste the YubiKey/FIDO2 SSH public key line."
        print_message "Generate on your workstation, for example:"
        print_message "  ssh-keygen -t ed25519-sk -O resident -O verify-required -C \"${YUBIKEY_SSH_USER}@$(hostname -f 2>/dev/null || hostname)\""
        print_message "Fallback for older YubiKey firmware:"
        print_message "  ssh-keygen -t ecdsa-sk -O resident -O verify-required -C \"${YUBIKEY_SSH_USER}@$(hostname -f 2>/dev/null || hostname)\""
        print_message "Leave empty to install/configure server-side FIDO2 support without adding a key."
        prompt_read -r -p "YubiKey SSH public key: " YUBIKEY_SSH_PUBLIC_KEY

        if [ -n "$YUBIKEY_SSH_PUBLIC_KEY" ] && \
           ! [[ "$YUBIKEY_SSH_PUBLIC_KEY" =~ ^(sk-ssh-ed25519@openssh\.com|sk-ecdsa-sha2-nistp256@openssh\.com|sk-ssh-ed25519-cert-v01@openssh\.com|sk-ecdsa-sha2-nistp256-cert-v01@openssh\.com)[[:space:]] ]]; then
            print_warning "The provided key does not look like an OpenSSH FIDO2/YubiKey public key"
            print_warning "Expected key type: sk-ssh-ed25519@openssh.com or sk-ecdsa-sha2-nistp256@openssh.com"
            prompt_read -r -p "Continue anyway? (y/N): " YUBIKEY_SSH_CONTINUE_INVALID_KEY
            YUBIKEY_SSH_CONTINUE_INVALID_KEY=${YUBIKEY_SSH_CONTINUE_INVALID_KEY:-n}
            if [ "$YUBIKEY_SSH_CONTINUE_INVALID_KEY" != "y" ] && [ "$YUBIKEY_SSH_CONTINUE_INVALID_KEY" != "Y" ]; then
                YUBIKEY_SSH_PUBLIC_KEY=""
            fi
        fi

        if [ -n "$YUBIKEY_SSH_PUBLIC_KEY" ]; then
            echo ""
            print_message "Disable password authentication after configuring YubiKey SSH?"
            print_warning "Only choose YES after verifying you have another working SSH session/key path."
            prompt_read -r -p "Disable SSH password authentication? (y/N): " YUBIKEY_SSH_DISABLE_PASSWORD_AUTH
            YUBIKEY_SSH_DISABLE_PASSWORD_AUTH=${YUBIKEY_SSH_DISABLE_PASSWORD_AUTH:-n}
        else
            YUBIKEY_SSH_DISABLE_PASSWORD_AUTH="n"
        fi
    else
        YUBIKEY_SSH_USER=""
        YUBIKEY_SSH_PUBLIC_KEY=""
        YUBIKEY_SSH_DISABLE_PASSWORD_AUTH="n"
    fi
    
    # Ask about Python virtual environment
    print_header "───────────────────────────────────────────────"
    print_header "   Software Installation"
    print_header "───────────────────────────────────────────────"
    echo ""
    print_message "Create Python virtual environment?"
    prompt_read -r -p "Create Python venv? (y/N): " CREATE_VENV
    CREATE_VENV=${CREATE_VENV:-n}

    if [ "$CREATE_VENV" = "y" ] || [ "$CREATE_VENV" = "Y" ]; then
        prompt_read -r -p "Enter path for virtual environment (default: /root/skripts): " VENV_PATH
        VENV_PATH=${VENV_PATH:-/root/skripts}
    else
        VENV_PATH=""
    fi

    echo ""

    # Ask about Docker installation
    print_message "Install Docker (container runtime)?"
    prompt_read -r -p "Install Docker? (y/N): " INSTALL_DOCKER
    INSTALL_DOCKER=${INSTALL_DOCKER:-n}

    if [ "$INSTALL_DOCKER" = "y" ] || [ "$INSTALL_DOCKER" = "Y" ]; then
        echo ""
        print_message "Disable Docker iptables/ip6tables management?"
        print_message "  Creates /etc/docker/daemon.json with:"
        print_message "    {\"iptables\": false, \"ip6tables\": false, \"userland-proxy\": false}"
        print_message "  Recommended when using nftables or external firewall"
        print_message "  Docker will NOT create any iptables/nat rules"
        print_message "  userland-proxy=false uses iptables hairpin NAT (faster)"
        prompt_read -r -p "Disable Docker iptables? (y/N): " DOCKER_DISABLE_IPTABLES
        DOCKER_DISABLE_IPTABLES=${DOCKER_DISABLE_IPTABLES:-n}
    else
        DOCKER_DISABLE_IPTABLES="n"
    fi

    # Ask about Go installation
    print_message "Install the latest version of Go?"
    if [ ! -z "$NEW_USERNAME" ]; then
        print_message "  Go will be installed for user: $NEW_USERNAME"
    else
        print_message "  Note: Go installation requires a user to be created"
    fi
    prompt_read -r -p "Install Go? (y/N): " INSTALL_GO
    INSTALL_GO=${INSTALL_GO:-n}
    
    # Ask about ipset installation
    echo ""
    print_message "Install ipset from the distribution repository?"
    prompt_read -r -p "Install ipset? (y/N): " INSTALL_IPSET
    INSTALL_IPSET=${INSTALL_IPSET:-n}

    echo ""

    # Ask about rclone installation
    print_message "Install rclone (cloud storage sync tool)?"
    print_message "  Supports: S3, Google Drive, Dropbox, SFTP, and 70+ backends"
    print_message "  Installed from the distribution repository"
    prompt_read -r -p "Install rclone? (y/N): " INSTALL_RCLONE
    INSTALL_RCLONE=${INSTALL_RCLONE:-n}

    echo ""

    # Select a single firewall backend so UFW and nftables prompts are mutually exclusive.
    print_header "───────────────────────────────────────────────"
    print_header "   Firewall Backend"
    print_header "───────────────────────────────────────────────"
    echo ""
    print_message "Select firewall backend:"
    print_message "  1) nftables — replace iptables/UFW with nftables"
    print_message "  2) UFW      — configure UFW firewall"
    print_message "  3) none     — skip firewall configuration"
    prompt_read -r -p "Firewall backend [1-3] (default: 2): " FIREWALL_BACKEND_CHOICE
    FIREWALL_BACKEND_CHOICE=${FIREWALL_BACKEND_CHOICE:-2}

    case "$FIREWALL_BACKEND_CHOICE" in
        1) FIREWALL_BACKEND="nftables" ;;
        2) FIREWALL_BACKEND="ufw" ;;
        3) FIREWALL_BACKEND="none" ;;
        *)
            print_warning "Invalid firewall backend choice: '$FIREWALL_BACKEND_CHOICE', using UFW"
            FIREWALL_BACKEND="ufw"
            ;;
    esac

    echo ""

    # Ask about UFW configuration
    if [ "$FIREWALL_BACKEND" = "ufw" ]; then
    CONFIGURE_UFW="y"
    ENABLE_NFTABLES="n"
    INSTALL_NFTABLES_CONF="n"
    NFTABLES_PROFILE=""
    NFTABLES_LOG_SCRIPT=""
    INSTALL_NFTABLES_LOGGING="n"
    INSTALL_NFT_DOCKER_WATCH="n"

    print_header "───────────────────────────────────────────────"
    print_header "   Firewall (UFW)"
    print_header "───────────────────────────────────────────────"
    echo ""
    print_message "UFW selected as firewall backend"

    print_message "Install ufw-docker (UFW integration for Docker)?"
    print_message "  Note: Can be installed even without Docker"
    prompt_read -r -p "Install ufw-docker? (y/N): " INSTALL_UFW_DOCKER
    INSTALL_UFW_DOCKER=${INSTALL_UFW_DOCKER:-n}

    # Ask about ICMP blocking (only if UFW is enabled)
    if [ "$CONFIGURE_UFW" = "y" ] || [ "$CONFIGURE_UFW" = "Y" ]; then
        echo ""
        print_message "Block ICMP (ping) requests?"
        print_message "  Note: Server will not respond to ping"
        prompt_read -r -p "Block ICMP? (y/N): " BLOCK_ICMP
        BLOCK_ICMP=${BLOCK_ICMP:-n}
        
        # Ask about custom UFW Docker rules
        echo ""
        print_message "Do you want to install custom UFW Docker rules script?"
        print_message "Available versions:"
        print_message "  v4 - ufw-docker-rules-v4.sh (standard version)"
        print_message "  v6 - ufw-docker-rules-v6.sh (enhanced with RustDesk support, recommended)"
        print_message "Both versions support custom SSH port configuration"
        print_message "Both versions available from archive or repository"
        print_message "Note: The script will run AFTER all other installations complete"
        prompt_read -r -p "Install custom UFW Docker rules? (y/N): " INSTALL_UFW_CUSTOM_RULES
        INSTALL_UFW_CUSTOM_RULES=${INSTALL_UFW_CUSTOM_RULES:-n}

        if [ "$INSTALL_UFW_CUSTOM_RULES" = "y" ] || [ "$INSTALL_UFW_CUSTOM_RULES" = "Y" ]; then
            echo ""
            print_message "Select version:"
            print_message "  4 - Standard version"
            print_message "  6 - Enhanced version with RustDesk support (recommended)"
            prompt_read -r -p "Enter version (4 or 6, default: 6): " UFW_RULES_VERSION
            UFW_RULES_VERSION=${UFW_RULES_VERSION:-6}

            if [ "$UFW_RULES_VERSION" != "4" ] && [ "$UFW_RULES_VERSION" != "6" ]; then
                print_warning "Invalid version. Using v6 as default."
                UFW_RULES_VERSION="6"
            fi

            print_message "Selected version: v${UFW_RULES_VERSION}"

            # Ask about installation source
            echo ""
            print_message "Select installation source:"
            print_message "  1 - Install from password-protected archive (ufw-docker-rules-v4.7z)"
            print_message "      Archive contains both v4 and v6 scripts"
            print_message "  2 - Install from public repository (https://raw.githubusercontent.com/civisrom/ufw-rules-docker/...)"
            prompt_read -r -p "Choose source (1 or 2, default: 1): " UFW_INSTALL_SOURCE
            UFW_INSTALL_SOURCE=${UFW_INSTALL_SOURCE:-1}

            if [ "$UFW_INSTALL_SOURCE" = "1" ]; then
                echo ""
                print_message "The archive is password-protected. Please enter the password:"
                prompt_read -r -s -p "Password: " UFW_CUSTOM_RULES_PASSWORD
                echo ""
                if [ -z "$UFW_CUSTOM_RULES_PASSWORD" ]; then
                    print_warning "No password provided. Custom UFW rules will not be installed."
                    INSTALL_UFW_CUSTOM_RULES="n"
                    UFW_SSH_PORT=""
                else
                    echo ""
                    print_message "Enter SSH port for UFW rules:"
                    print_message "This port will be used instead of the default in the script"
                    prompt_read -r -p "SSH Port (default: 22): " UFW_SSH_PORT
                    UFW_SSH_PORT=${UFW_SSH_PORT:-22}

                    if ! [[ "$UFW_SSH_PORT" =~ ^[0-9]+$ ]] || [ "$UFW_SSH_PORT" -lt 1 ] || [ "$UFW_SSH_PORT" -gt 65535 ]; then
                        print_warning "Invalid port number. Using default port 22."
                        UFW_SSH_PORT="22"
                    fi

                    print_message "SSH port set to: $UFW_SSH_PORT"
                fi
            else
                # Repository installation - no password needed
                UFW_CUSTOM_RULES_PASSWORD=""
                print_message "Will install from public repository (no password required)"

                # Ask for SSH port to override default in script
                echo ""
                print_message "Enter SSH port for UFW rules:"
                print_message "This port will be used instead of the default in the script"
                print_message "Note: This keeps your actual SSH port private"
                prompt_read -r -p "SSH Port (default: 22): " UFW_SSH_PORT
                UFW_SSH_PORT=${UFW_SSH_PORT:-22}

                # Validate port number
                if ! [[ "$UFW_SSH_PORT" =~ ^[0-9]+$ ]] || [ "$UFW_SSH_PORT" -lt 1 ] || [ "$UFW_SSH_PORT" -gt 65535 ]; then
                    print_warning "Invalid port number. Using default port 22."
                    UFW_SSH_PORT="22"
                fi

                print_message "SSH port set to: $UFW_SSH_PORT"
            fi
        else
            UFW_RULES_VERSION="6"
            UFW_INSTALL_SOURCE="1"
            UFW_SSH_PORT=""
        fi
    else
        BLOCK_ICMP="n"
        INSTALL_UFW_CUSTOM_RULES="n"
        UFW_RULES_VERSION="6"
        UFW_INSTALL_SOURCE="1"
        UFW_SSH_PORT=""
    fi
    else
        CONFIGURE_UFW="n"
        BLOCK_ICMP="n"
        INSTALL_UFW_CUSTOM_RULES="n"
        UFW_RULES_VERSION="6"
        UFW_INSTALL_SOURCE="1"
        UFW_SSH_PORT=""
        UFW_CUSTOM_RULES_PASSWORD=""
        INSTALL_UFW_DOCKER="n"
    fi

    # Ask about nftables
    if [ "$FIREWALL_BACKEND" = "nftables" ]; then
    ENABLE_NFTABLES="y"
    CONFIGURE_UFW="n"
    BLOCK_ICMP="n"
    INSTALL_UFW_CUSTOM_RULES="n"
    UFW_RULES_VERSION="6"
    UFW_INSTALL_SOURCE="1"
    UFW_SSH_PORT=""
    UFW_CUSTOM_RULES_PASSWORD=""
    INSTALL_UFW_DOCKER="n"

    echo ""
    print_header "───────────────────────────────────────────────"
    print_header "   nftables Firewall"
    print_header "───────────────────────────────────────────────"
    echo ""
    print_message "nftables selected as firewall backend"
    print_message "  - Replaces iptables/UFW with nftables"
    print_message "  - Disables and masks UFW if installed"
    print_message "  - Flushes all iptables rules"
    print_message "  - Installs and enables nftables service"

    if [ "$ENABLE_NFTABLES" = "y" ] || [ "$ENABLE_NFTABLES" = "Y" ]; then
        # Warn about UFW conflict and auto-disable UFW options
        if [ "$CONFIGURE_UFW" = "y" ] || [ "$CONFIGURE_UFW" = "Y" ]; then
            print_warning "nftables selected — UFW configuration will be skipped"
            CONFIGURE_UFW="n"
            BLOCK_ICMP="n"
            INSTALL_UFW_CUSTOM_RULES="n"
            INSTALL_UFW_DOCKER="n"
            CUSTOM_PORTS=""
        fi

        # Ask about nftables config profile
        # Profiles are loaded from config/nftables-profiles.conf (or embedded fallback)
        # Config files are installed from opt.7z archive at execution time
        echo ""
        print_message "Install nftables configuration profile?"
        if [ "$EXTRACT_OPT_ARCHIVE" != "y" ] && [ "$EXTRACT_OPT_ARCHIVE" != "Y" ]; then
            print_warning "opt.7z extraction not selected — config files must already exist in /opt/nftables/"
        fi
        print_message "  Available profiles:"
        # Generate menu dynamically from NFT_PROFILE_DESCRIPTIONS array
        _prev_group=""
        for _i in $(seq 1 "$NFT_PROFILES_COUNT"); do
            # Insert group headers between basic (1-3) and v2 (4+) profiles
            if [ "$_i" -le 3 ] && [ "$_prev_group" != "basic" ]; then
                print_message "    ── Basic profiles ──"
                _prev_group="basic"
            elif [ "$_i" -eq 4 ] && [ "$_prev_group" != "v2" ]; then
                echo ""
                print_message "    ── v2 profiles (advanced) ──"
                _prev_group="v2"
            fi
            print_message "    ${_i}) ${NFT_PROFILE_DESCRIPTIONS[$_i]}"
        done
        unset _i _prev_group
        echo ""
        prompt_read -r -p "Install nftables config profile? (y/N): " INSTALL_NFTABLES_CONF
        INSTALL_NFTABLES_CONF=${INSTALL_NFTABLES_CONF:-n}

        if [ "$INSTALL_NFTABLES_CONF" = "y" ] || [ "$INSTALL_NFTABLES_CONF" = "Y" ]; then
            prompt_read -r -p "Select profile [1-${NFT_PROFILES_COUNT}] (default: ${NFT_DEFAULT_PROFILE}): " NFTABLES_PROFILE_NUM
            NFTABLES_PROFILE_NUM=${NFTABLES_PROFILE_NUM:-$NFT_DEFAULT_PROFILE}

            # Validate selection: must be numeric AND within defined profile range.
            # Non-numeric input would be evaluated as bash arithmetic when used as an
            # array subscript, which can produce noisy errors under `set -e`.
            if ! [[ "$NFTABLES_PROFILE_NUM" =~ ^[1-9][0-9]{0,2}$ ]] \
               || [ "$NFTABLES_PROFILE_NUM" -lt 1 ] \
               || [ "$NFTABLES_PROFILE_NUM" -gt "$NFT_PROFILES_COUNT" ] \
               || [ -z "${NFT_PROFILE_NAMES[$NFTABLES_PROFILE_NUM]+x}" ]; then
                print_warning "Invalid selection: '${NFTABLES_PROFILE_NUM}', using default (${NFT_DEFAULT_PROFILE})"
                NFTABLES_PROFILE_NUM=$NFT_DEFAULT_PROFILE
            fi

            # Set variables from profile arrays
            NFTABLES_PROFILE="${NFT_PROFILE_NAMES[$NFTABLES_PROFILE_NUM]}"
            NFTABLES_CONF_FILE="${NFT_PROFILE_CONFIGS[$NFTABLES_PROFILE_NUM]}"
            NFTABLES_LOG_SCRIPT="${NFT_PROFILE_LOGSCRIPTS[$NFTABLES_PROFILE_NUM]:-}"
            print_message "Selected: ${NFTABLES_PROFILE} (${NFTABLES_CONF_FILE})"

            # Ask about logging script (only if profile has one)
            if [ -n "$NFTABLES_LOG_SCRIPT" ]; then
                echo ""
                print_message "Install nftables logging script for '${NFTABLES_PROFILE}' profile?"
                print_message "  Script: ${NFTABLES_LOG_SCRIPT}"
                print_message "  Configures rsyslog/journald rules for nftables log messages"
                prompt_read -r -p "Install logging script? (Y/n): " INSTALL_NFTABLES_LOGGING
                INSTALL_NFTABLES_LOGGING=${INSTALL_NFTABLES_LOGGING:-y}
            else
                INSTALL_NFTABLES_LOGGING="n"
            fi
        else
            NFTABLES_PROFILE=""
            INSTALL_NFTABLES_LOGGING="n"
        fi
    else
        INSTALL_NFTABLES_CONF="n"
        NFTABLES_PROFILE=""
        INSTALL_NFTABLES_LOGGING="n"
    fi

    # Ask about nft-docker-watch (nftables + Docker integration)
    if ([ "$ENABLE_NFTABLES" = "y" ] || [ "$ENABLE_NFTABLES" = "Y" ]) && \
       ([ "$INSTALL_DOCKER" = "y" ] || [ "$INSTALL_DOCKER" = "Y" ]); then
        echo ""
        print_message "Install nft-docker-watch service?"
        print_message "  Applies nftables rules after Docker starts and on every Docker restart"
        print_message "  Creates systemd service + drop-in trigger for docker.service"
        print_message "  Includes: validation, backup, rollback, verification"
        prompt_read -r -p "Install nft-docker-watch? (Y/n): " INSTALL_NFT_DOCKER_WATCH
        INSTALL_NFT_DOCKER_WATCH=${INSTALL_NFT_DOCKER_WATCH:-y}
    else
        INSTALL_NFT_DOCKER_WATCH="n"
    fi
    else
        ENABLE_NFTABLES="n"
        INSTALL_NFTABLES_CONF="n"
        NFTABLES_PROFILE=""
        NFTABLES_CONF_FILE=""
        NFTABLES_LOG_SCRIPT=""
        INSTALL_NFTABLES_LOGGING="n"
        INSTALL_NFT_DOCKER_WATCH="n"
    fi

    # Ask about sysctl configuration
    echo ""
    print_header "───────────────────────────────────────────────"
    print_header "   System Parameters (sysctl)"
    print_header "───────────────────────────────────────────────"
    echo ""
    print_message "Optimize system parameters (sysctl)?"
    print_message "Includes: IPv6 disable, network tuning, BBR congestion control"
    prompt_read -r -p "Configure sysctl? (Y/n): " CONFIGURE_SYSCTL
    CONFIGURE_SYSCTL=${CONFIGURE_SYSCTL:-y}

    if [ "$CONFIGURE_SYSCTL" = "y" ] || [ "$CONFIGURE_SYSCTL" = "Y" ]; then
        echo ""
        print_message "Choose sysctl configuration mode:"
        print_message "  1) Basic — static parameters (IPv6 disable, BBR, TCP/UDP tuning, security)"
        print_message "  2) Full  — run Linux NetworkOptimizer (bbr.sh) with adaptive RAM-based profiles"
        prompt_read -r -p "Select mode [1/2] (default: 1): " SYSCTL_MODE
        SYSCTL_MODE=${SYSCTL_MODE:-1}

        # Validate input
        if [ "$SYSCTL_MODE" != "1" ] && [ "$SYSCTL_MODE" != "2" ]; then
            print_warning "Invalid choice '$SYSCTL_MODE', using default: 1 (basic)"
            SYSCTL_MODE="1"
        fi

        # Set RUN_BBR_OPTIMIZER based on mode for backward compatibility
        if [ "$SYSCTL_MODE" = "2" ]; then
            RUN_BBR_OPTIMIZER="y"
        else
            RUN_BBR_OPTIMIZER="n"
        fi

        # BBR optimizer sub-options (only for full mode)
        if [ "$SYSCTL_MODE" = "2" ]; then
            echo ""
            print_message "Linux NetworkOptimizer (bbr.sh) options:"
            print_message "(Network tuning via sysctl is always applied by BBR with adaptive RAM profiles)"
            echo ""

            # Force IPv4 for APT
            print_message "1. Force IPv4 for APT (recommended for IPv6 connectivity issues)"
            prompt_read -r -p "   Enable force_ipv4_apt? (Y/n): " BBR_FORCE_IPV4
            BBR_FORCE_IPV4=${BBR_FORCE_IPV4:-y}

            # Full system update
            print_message "2. Full system update and upgrade (apt update && upgrade)"
            prompt_read -r -p "   Enable full_update_upgrade? (Y/n): " BBR_FULL_UPDATE
            BBR_FULL_UPDATE=${BBR_FULL_UPDATE:-y}

            # Fix /etc/hosts
            print_message "3. Fix /etc/hosts file (add hostname loopback entry 127.0.1.1)"
            prompt_read -r -p "   Enable fix_etc_hosts? (Y/n): " BBR_FIX_HOSTS
            BBR_FIX_HOSTS=${BBR_FIX_HOSTS:-y}

            # Fix DNS (skip if systemd-resolved is configured separately)
            if [ "$CONFIGURE_RESOLVED" = "y" ] || [ "$CONFIGURE_RESOLVED" = "Y" ]; then
                print_message "4. Fix DNS — SKIPPED (systemd-resolved is configured separately)"
                BBR_FIX_DNS="n"
            else
                print_message "4. Fix DNS (set Cloudflare 1.1.1.1/1.0.0.1 + Google 8.8.8.8/8.8.4.4)"
                prompt_read -r -p "   Enable fix_dns? (Y/n): " BBR_FIX_DNS
                BBR_FIX_DNS=${BBR_FIX_DNS:-y}
            fi

            echo ""
            print_message "BBR adaptive network tuning + selected options will be applied after main setup"
        else
            BBR_FORCE_IPV4="n"
            BBR_FULL_UPDATE="n"
            BBR_FIX_HOSTS="n"
            BBR_FIX_DNS="n"
        fi

        # IP forwarding (for both modes)
        echo ""
        print_message "Enable IP forwarding (net.ipv4.ip_forward = 1)?"
        print_message "Required for: Docker networks, NAT, VPN, routing between interfaces"
        print_message "If unsure — choose Y (recommended for servers with Docker)"
        prompt_read -r -p "Enable IP forwarding? (Y/n): " ENABLE_IP_FORWARD
        ENABLE_IP_FORWARD=${ENABLE_IP_FORWARD:-y}

        # Systemd service for sysctl enforcement
        echo ""
        print_message "Install systemd service for sysctl enforcement?"
        print_message "Creates disable-ipv6.service that reapplies the selected sysctl file after network is online"
        print_message "Ensures sysctl settings are always applied on boot"
        prompt_read -r -p "Install sysctl enforcement service? (Y/n): " INSTALL_SYSCTL_SERVICE
        INSTALL_SYSCTL_SERVICE=${INSTALL_SYSCTL_SERVICE:-y}
    else
        SYSCTL_MODE=""
        RUN_BBR_OPTIMIZER="n"
        ENABLE_IP_FORWARD="n"
        INSTALL_SYSCTL_SERVICE="n"
        BBR_FORCE_IPV4="n"
        BBR_FULL_UPDATE="n"
        BBR_FIX_HOSTS="n"
        BBR_FIX_DNS="n"
    fi

    # Ask about systemd-resolved configuration
    echo ""
    print_message "Configure systemd-resolved DNS resolver?"
    print_message "  - Installs libnss-resolve (NSS module for systemd-resolved)"
    print_message "  - Configures /etc/systemd/resolved.conf"
    print_message "  - Creates symlink /etc/resolv.conf -> /run/systemd/resolve/resolv.conf"
    print_message "  - Enables and starts systemd-resolved service"
    prompt_read -r -p "Configure systemd-resolved? (y/N): " CONFIGURE_RESOLVED
    CONFIGURE_RESOLVED=${CONFIGURE_RESOLVED:-n}

    if [ "$CONFIGURE_RESOLVED" = "y" ] || [ "$CONFIGURE_RESOLVED" = "Y" ]; then
        echo ""
        print_message "Enter primary DNS server for systemd-resolved:"
        print_message "  1.1.1.1   — Cloudflare (default)"
        print_message "  8.8.8.8   — Google"
        print_message "  9.9.9.9   — Quad9"
        print_message "  127.0.0.1 — local DNS resolver (only if one is already installed)"
        prompt_read -r -p "DNS server (default: 1.1.1.1): " RESOLVED_DNS
        RESOLVED_DNS=${RESOLVED_DNS:-1.1.1.1}

        echo ""
        print_message "Disable DNS stub listener (DNSStubListener=no)?"
        print_message "  Recommended when using a local DNS resolver on port 53"
        print_message "  Frees port 53 for your local resolver (unbound, pihole, etc.)"
        prompt_read -r -p "Disable DNSStubListener? (Y/n): " RESOLVED_STUB_LISTENER_OFF
        RESOLVED_STUB_LISTENER_OFF=${RESOLVED_STUB_LISTENER_OFF:-y}

        echo ""
        print_message "Enable DNS over TLS (DoT)?"
        print_message "  Encrypts DNS queries to upstream resolver"
        print_message "  Note: Upstream DNS server must support DoT"
        prompt_read -r -p "Enable DNSOverTLS? (y/N): " RESOLVED_DNS_OVER_TLS
        RESOLVED_DNS_OVER_TLS=${RESOLVED_DNS_OVER_TLS:-n}
    else
        RESOLVED_DNS=""
        RESOLVED_STUB_LISTENER_OFF=""
        RESOLVED_DNS_OVER_TLS=""
    fi

    if { [ "$CONFIGURE_RESOLVED" = "y" ] || [ "$CONFIGURE_RESOLVED" = "Y" ]; } && \
       { [ "${BBR_FIX_DNS:-n}" = "y" ] || [ "${BBR_FIX_DNS:-n}" = "Y" ]; }; then
        print_warning "systemd-resolved selected; disabling BBR fix_dns to avoid conflicting DNS rewrites"
        BBR_FIX_DNS="n"
    fi

    # Ask about IPv6 disable via GRUB (Debian and Ubuntu)
    if { [ "$OS" = "debian" ] || [ "$OS" = "ubuntu" ]; } && command -v update-grub >/dev/null 2>&1; then
        echo ""
        print_message "Do you want to disable IPv6 at kernel level (GRUB)?"
        print_message "Adds 'ipv6.disable=1' to BOTH GRUB_CMDLINE_LINUX_DEFAULT"
        print_message "and GRUB_CMDLINE_LINUX (so recovery boot is also covered)."
        print_message "Note: This is in addition to sysctl IPv6 disable and requires reboot"
        prompt_read -r -p "Disable IPv6 via GRUB? (y/N): " DISABLE_IPV6_GRUB
        DISABLE_IPV6_GRUB=${DISABLE_IPV6_GRUB:-n}
    else
        DISABLE_IPV6_GRUB="n"
    fi
    
    # Ask about repository configuration
    if [ "$OS" = "debian" ] || [ "$OS" = "ubuntu" ]; then
        print_message "Do you want to configure ${OS^} repositories?"
        prompt_read -r -p "Configure repositories? (Y/n): " CONFIGURE_REPOS
        CONFIGURE_REPOS=${CONFIGURE_REPOS:-y}
    fi
    
    # Ask about Ubuntu PPA repositories (only for Ubuntu)
    if [ "$OS" = "ubuntu" ]; then
        echo ""
        print_message "Do you want to add additional PPA repositories for Ubuntu?"
        print_message "Available PPAs:"
        print_message "  1. ppa:ondrej/php - Latest PHP builds"
        print_message "  2. ppa:git-core/ppa - Latest Git version"
        print_message "  3. ppa:ubuntu-toolchain-r/test - Latest GCC toolchain"
        prompt_read -r -p "Add PPA repositories? (y/N): " ADD_UBUNTU_PPAS
        ADD_UBUNTU_PPAS=${ADD_UBUNTU_PPAS:-n}
        
        # Initialize PPA selection flags
        ADD_PPA_PHP="n"
        ADD_PPA_GIT="n"
        ADD_PPA_TOOLCHAIN="n"
        INSTALL_PHP_CLI="n"
        INSTALL_PHP_EXTENSIONS="n"
        
        if [ "$ADD_UBUNTU_PPAS" = "y" ] || [ "$ADD_UBUNTU_PPAS" = "Y" ]; then
            echo ""
            print_message "Select which PPAs to add:"
            echo ""

            # Ondrej PHP PPA
            print_message "1. ppa:ondrej/php - Latest PHP builds"
            prompt_read -r -p "   Add Ondrej PHP PPA? (y/N): " ADD_PPA_PHP
            ADD_PPA_PHP=${ADD_PPA_PHP:-n}

            if [ "$ADD_PPA_PHP" = "y" ] || [ "$ADD_PPA_PHP" = "Y" ]; then
                prompt_read -r -p "   Install PHP CLI (php-cli)? (y/N): " INSTALL_PHP_CLI
                INSTALL_PHP_CLI=${INSTALL_PHP_CLI:-n}

                if [ "$INSTALL_PHP_CLI" = "y" ] || [ "$INSTALL_PHP_CLI" = "Y" ]; then
                    prompt_read -r -p "   Install PHP extensions (mbstring, xml, curl, mysql)? (y/N): " INSTALL_PHP_EXTENSIONS
                    INSTALL_PHP_EXTENSIONS=${INSTALL_PHP_EXTENSIONS:-n}
                fi
            fi

            # Git Core PPA
            print_message "2. ppa:git-core/ppa - Latest stable Git releases"
            prompt_read -r -p "   Add Git Core PPA? (y/N): " ADD_PPA_GIT
            ADD_PPA_GIT=${ADD_PPA_GIT:-n}
            
            # Ubuntu Toolchain PPA
            print_message "3. ppa:ubuntu-toolchain-r/test - Latest GCC, G++, and toolchain"
            prompt_read -r -p "   Add Ubuntu Toolchain PPA? (y/N): " ADD_PPA_TOOLCHAIN
            ADD_PPA_TOOLCHAIN=${ADD_PPA_TOOLCHAIN:-n}
        fi
        
    else
        ADD_UBUNTU_PPAS="n"
        ADD_PPA_PHP="n"
        ADD_PPA_GIT="n"
        ADD_PPA_TOOLCHAIN="n"
        INSTALL_PHP_CLI="n"
        INSTALL_PHP_EXTENSIONS="n"
    fi

    # Ask about upstream Nginx repositories (available for both Debian and Ubuntu)
    if [ "$OS" = "debian" ] || [ "$OS" = "ubuntu" ]; then
        # Offer COMPLETE removal of an existing nginx first (mutually exclusive
        # with installing). Only asked when nginx is actually present.
        REMOVE_NGINX="n"
        if command -v nginx >/dev/null 2>&1 || \
           dpkg-query -W -f='${Status}' nginx 2>/dev/null | grep -q "install ok installed"; then
            echo ""
            print_warning "An existing nginx installation was detected."
            print_message "Complete removal will back up /etc/nginx, then PURGE all nginx"
            print_message "packages and modules and delete configs, binaries, unused"
            print_message "dependencies, module symlinks and leftover directories."
            prompt_read -r -p "Completely REMOVE nginx (purge everything)? (y/N): " REMOVE_NGINX
            REMOVE_NGINX=${REMOVE_NGINX:-n}
        fi

        if [ "$REMOVE_NGINX" = "y" ] || [ "$REMOVE_NGINX" = "Y" ]; then
            # Removal mode — skip all repo/install questions.
            ADD_NGINX_ORG="n"; ADD_NGINX_MYGUARD="n"; ADD_NGINX_MODULES="n"
            INSTALL_NGINX="n"; NGINX_INSTALL_VARIANT=""; NGINX_CUSTOM_PKGS=""; MIGRATE_NGINX="n"
        else
        echo ""
        print_message "Do you want to add an upstream Nginx repository?"
        print_message "Available Nginx repositories (Debian & Ubuntu):"
        print_message "  1. nginx.org         - Official Nginx stable packages (https://nginx.org/en/linux_packages.html)"
        print_message "  2. deb.myguard.nl    - Third-party Nginx builds (https://deb.myguard.nl/)"
        print_message "  3. nginx-modules.com - Dynamic modules for Nginx stable (https://www.nginx-modules.com/)"
        print_warning "Pick only ONE Nginx package source (1 or 2); option 3 only adds modules and pairs with the official nginx.org repo."

        # Official nginx.org repository
        prompt_read -r -p "   Add official nginx.org repository? (y/N): " ADD_NGINX_ORG
        ADD_NGINX_ORG=${ADD_NGINX_ORG:-n}

        # Third-party deb.myguard.nl repository
        prompt_read -r -p "   Add third-party deb.myguard.nl Nginx repository? (y/N): " ADD_NGINX_MYGUARD
        ADD_NGINX_MYGUARD=${ADD_NGINX_MYGUARD:-n}

        # nginx-modules.com (Blendbyte) dynamic modules repository
        prompt_read -r -p "   Add nginx-modules.com (Blendbyte) modules repository? (y/N): " ADD_NGINX_MODULES
        ADD_NGINX_MODULES=${ADD_NGINX_MODULES:-n}

        if { [ "$ADD_NGINX_ORG" = "y" ] || [ "$ADD_NGINX_ORG" = "Y" ]; } && \
           { [ "$ADD_NGINX_MYGUARD" = "y" ] || [ "$ADD_NGINX_MYGUARD" = "Y" ]; }; then
            print_warning "Both Nginx package repositories selected: deb.myguard.nl has the higher APT pin priority and will win."
        fi
        if { [ "$ADD_NGINX_MODULES" = "y" ] || [ "$ADD_NGINX_MODULES" = "Y" ]; } && \
           { [ "$ADD_NGINX_ORG" != "y" ] && [ "$ADD_NGINX_ORG" != "Y" ]; }; then
            print_warning "nginx-modules.com modules are built for the official nginx.org build; enabling nginx.org (option 1) too is recommended."
        fi

        # Offer to install nginx now, with a flexible choice of module set.
        INSTALL_NGINX="n"
        NGINX_INSTALL_VARIANT=""
        NGINX_CUSTOM_PKGS=""
        if { [ "$ADD_NGINX_ORG" = "y" ] || [ "$ADD_NGINX_ORG" = "Y" ]; } || \
           { [ "$ADD_NGINX_MYGUARD" = "y" ] || [ "$ADD_NGINX_MYGUARD" = "Y" ]; }; then
            echo ""
            prompt_read -r -p "Install nginx now from the selected repository? (y/N): " INSTALL_NGINX
            INSTALL_NGINX=${INSTALL_NGINX:-n}

            if [ "$INSTALL_NGINX" = "y" ] || [ "$INSTALL_NGINX" = "Y" ]; then
                echo ""
                print_message "Choose an nginx install preset (only presets for the repos you enabled are valid):"
                if [ "$ADD_NGINX_ORG" = "y" ] || [ "$ADD_NGINX_ORG" = "Y" ]; then
                    print_message "  1) nginx.org: nginx only (standard built-in modules)"
                    print_message "  2) nginx.org: nginx + official dynamic modules (njs, geoip, image-filter, xslt, perl, otel, acme)"
                fi
                if { [ "$ADD_NGINX_ORG" = "y" ] || [ "$ADD_NGINX_ORG" = "Y" ]; } && \
                   { [ "$ADD_NGINX_MODULES" = "y" ] || [ "$ADD_NGINX_MODULES" = "Y" ]; }; then
                    print_message "  3) nginx.org + ALL Blendbyte modules (brotli, modsecurity, headers-more, zstd, geoip2, ...)"
                    print_message "  4) nginx.org: EVERYTHING (nginx + official modules + ALL Blendbyte modules)"
                fi
                if [ "$ADD_NGINX_MYGUARD" = "y" ] || [ "$ADD_NGINX_MYGUARD" = "Y" ]; then
                    print_message "  5) deb.myguard.nl: nginx-full"
                    print_message "  6) deb.myguard.nl: nginx-extras (maximal module set)"
                    print_message "  8) deb.myguard.nl: nginx + curated lean modules (stream, stream-geoip2,"
                    print_message "       http-upstream-fair, http-subs-filter, http-geoip2, http-echo,"
                    print_message "       http-dav-ext, http-auth-pam) — distro-nginx-full equivalent, x-ui-pro ready"
                fi
                print_message "  7) custom (install only the package names you list below)"
                prompt_read -r -p "Preset [1-8]: " NGINX_INSTALL_VARIANT

                if [ "$NGINX_INSTALL_VARIANT" = "7" ]; then
                    # Show a copy-paste catalogue of packages available from the
                    # repositories that were enabled. Plain echo (no [INFO] prefix
                    # / colour) keeps the lines clean to copy and paste.
                    echo ""
                    print_message "Available nginx packages (copy/paste the ones you want into the prompt below):"
                    if [ "$ADD_NGINX_ORG" = "y" ] || [ "$ADD_NGINX_ORG" = "Y" ]; then
                        echo "  # nginx.org core:"
                        echo "    nginx nginx-dbg nginx-nr-agent"
                        echo "  # nginx.org dynamic modules:"
                        echo "    nginx-module-njs nginx-module-geoip nginx-module-image-filter nginx-module-xslt nginx-module-perl nginx-module-otel nginx-module-acme"
                    fi
                    if [ "$ADD_NGINX_MODULES" = "y" ] || [ "$ADD_NGINX_MODULES" = "Y" ]; then
                        echo "  # nginx-modules.com (Blendbyte) dynamic modules:"
                        echo "    nginx-module-brotli nginx-module-brotli-static nginx-module-cache-purge nginx-module-dav-ext nginx-module-fancyindex nginx-module-geoip2 nginx-module-headers-more nginx-module-modsecurity nginx-module-stream-geoip2 nginx-module-substitutions nginx-module-zstd nginx-module-zstd-static"
                    fi
                    if [ "$ADD_NGINX_MYGUARD" = "y" ] || [ "$ADD_NGINX_MYGUARD" = "Y" ]; then
                        echo "  # deb.myguard.nl base (always include these two):"
                        echo "    nginx nginx-common"
                        echo "  # deb.myguard.nl modules are named libnginx-mod-* (Debian-style). Common picks:"
                        echo "    libnginx-mod-stream libnginx-mod-stream-geoip2 libnginx-mod-http-geoip2"
                        echo "    libnginx-mod-http-headers-more-filter libnginx-mod-http-brotli libnginx-mod-http-modsecurity"
                        echo "    libnginx-mod-http-cache-purge libnginx-mod-http-fancyindex libnginx-mod-http-dav-ext"
                        echo "    libnginx-mod-http-subs-filter libnginx-mod-http-lua libnginx-mod-http-ndk"
                        echo "    libnginx-mod-http-upstream-fair libnginx-mod-mail"
                        echo "  # TIP: use 'nginx' + only the libnginx-mod-* you need — NOT nginx-full"
                        echo "  #      (its ~110 modules exceed nginx's module limit and break nginx -t)."
                        echo "  # Full list of available modules after setup:  apt-cache search '^libnginx-mod-'"
                    fi
                    echo ""
                    print_message "Enter packages separated by spaces OR commas"
                    print_message "  (e.g. 'nginx, nginx-module-njs nginx-module-brotli')."
                    prompt_read -r -p "Packages to install: " NGINX_CUSTOM_PKGS
                else
                    echo ""
                    print_message "Optionally add extra packages (space- or comma-separated), or leave empty."
                    prompt_read -r -p "Extra packages: " NGINX_CUSTOM_PKGS
                fi

                # If nginx is already installed (e.g. from the distro repos), offer
                # a safe, backed-up migration to the selected repository.
                MIGRATE_NGINX="n"
                if command -v nginx >/dev/null 2>&1 || \
                   dpkg-query -W -f='${Status}' nginx 2>/dev/null | grep -q "install ok installed"; then
                    echo ""
                    print_warning "An existing nginx installation was detected: $(nginx -v 2>&1 | sed 's#.*/##' || echo unknown)"
                    print_warning "Migrating changes the package source. For nginx.org (presets 1-4) this:"
                    print_warning "  - removes distro nginx-common/nginx-core and all distro libnginx-mod-*;"
                    print_warning "  - switches layout (no sites-enabled/modules-enabled; modules via load_module)."
                    print_warning "deb.myguard.nl (presets 5-6) is Debian-style and upgrades mostly in place."
                    print_message "Before any change the script backs up /etc/nginx and the package list to"
                    print_message "/var/backups, stops nginx, swaps packages (keeping your configs), runs"
                    print_message "'nginx -t', and only starts nginx if the config test passes."
                    prompt_read -r -p "Migrate existing nginx to the selected repository? (y/N): " MIGRATE_NGINX
                    MIGRATE_NGINX=${MIGRATE_NGINX:-n}
                fi
            fi
        fi
        fi
    else
        REMOVE_NGINX="n"
        ADD_NGINX_ORG="n"
        ADD_NGINX_MYGUARD="n"
        ADD_NGINX_MODULES="n"
        INSTALL_NGINX="n"
        NGINX_INSTALL_VARIANT=""
        NGINX_CUSTOM_PKGS=""
        MIGRATE_NGINX="n"
    fi

    # Ask about disabling IPv6 in /etc/network/interfaces
    print_header "───────────────────────────────────────────────"
    print_header "   Miscellaneous"
    print_header "───────────────────────────────────────────────"
    echo ""
    print_message "Disable IPv6 in /etc/network/interfaces?"
    print_message "  Comments out all inet6 configuration lines"
    print_message "  Useful for static network configuration"
    prompt_read -r -p "Comment out IPv6 in /etc/network/interfaces? (y/N): " COMMENT_IPV6_INTERFACES
    COMMENT_IPV6_INTERFACES=${COMMENT_IPV6_INTERFACES:-n}

    # Ask about disabling IPv6 in netplan (Ubuntu default, also possible on Debian)
    if [ -d /etc/netplan ] && \
       compgen -G '/etc/netplan/*.yaml' >/dev/null 2>&1 || \
       compgen -G '/etc/netplan/*.yml'  >/dev/null 2>&1; then
        echo ""
        print_message "Disable IPv6 in /etc/netplan/*.yaml?"
        print_message "  Removes IPv6 addresses, gateway6, IPv6 nameservers/routes"
        print_message "  Sets dhcp6: false, accept-ra: false, link-local: [ipv4] on all ifaces"
        print_message "  Validates with 'netplan generate' before keeping changes"
        print_warning "  Will NOT auto-apply — run 'sudo netplan apply' yourself when ready"
        print_warning "  (avoids losing SSH if IPv6 connectivity was active)"
        prompt_read -r -p "Disable IPv6 in netplan? (y/N): " DISABLE_IPV6_NETPLAN
        DISABLE_IPV6_NETPLAN=${DISABLE_IPV6_NETPLAN:-n}
    else
        DISABLE_IPV6_NETPLAN="n"
    fi

    echo ""

    # Ask about MOTD installation
    print_message "Install custom MOTD (Message of the Day)?"
    prompt_read -r -p "Install MOTD? (y/N): " INSTALL_MOTD
    INSTALL_MOTD=${INSTALL_MOTD:-n}

    # Ask for UFW ports (if UFW is enabled)
    if [ "$CONFIGURE_UFW" = "y" ] || [ "$CONFIGURE_UFW" = "Y" ]; then
        echo ""
        print_header "───────────────────────────────────────────────"
        print_header "   UFW Additional Ports"
        print_header "───────────────────────────────────────────────"
        echo ""
        print_message "Port $SSH_PORT (SSH) will be allowed automatically"
        echo ""
        print_message "Additional ports format:"
        print_message "  Single port:     8080"
        print_message "  With protocol:   8080/tcp  or  53/udp"
        print_message "  Multiple ports:  8080,8443,9000"
        print_message "  Mixed:           8080/tcp,53/udp,3000"
        echo ""
        prompt_read -r -p "Enter additional ports (comma-separated, press Enter to skip): " CUSTOM_PORTS

        if [ ! -z "$CUSTOM_PORTS" ]; then
            print_message "Custom ports will be configured: $CUSTOM_PORTS"
        fi
    else
        CUSTOM_PORTS=""
    fi
    
    # Ask about Swap Configuration
    echo ""
    print_header "═══════════════════════════════════════════════"
    print_header "   Swap Configuration (swapfile + zram)"
    print_header "═══════════════════════════════════════════════"
    echo ""
    TOTAL_RAM_MB=$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo)
    TOTAL_RAM_GB=$(awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo)
    print_message "Detected RAM: ${TOTAL_RAM_MB} MB (~${TOTAL_RAM_GB} GB)"
    print_message "This will configure hybrid swap: swapfile (disk) + zram (compressed RAM)"
    print_message "Recommended for VPS with limited memory"
    prompt_read -r -p "Configure Swap? (y/N): " CONFIGURE_SWAP
    CONFIGURE_SWAP=${CONFIGURE_SWAP:-n}

    if [ "$CONFIGURE_SWAP" = "y" ] || [ "$CONFIGURE_SWAP" = "Y" ]; then
        echo ""
        print_message "Swap setup mode:"
        echo "  1) Auto-detect (choose template based on RAM size)"
        echo "  2) Interactive wizard (full control over settings)"
        echo ""
        prompt_read -r -p "Select mode [1-2] (default: 1): " SWAP_MODE
        SWAP_MODE=${SWAP_MODE:-1}

        if [ "$SWAP_MODE" = "2" ]; then
            SWAP_INTERACTIVE=true
        else
            SWAP_INTERACTIVE=false
        fi
    fi

else
    # Default settings for non-interactive mode
    SET_ROOT_PASSWORD="n"
    ROOT_PASSWORD=""
    CREATE_USER="n"
    NEW_USERNAME=""
    NEW_USER_PASSWORD=""
    CONFIGURE_USER_SSH_KEY="n"
    USER_SSH_KEY=""
    INSTALL_ZSH="n"
    CONFIGURE_CRONTAB="n"
    CRONTAB_MODE="3"
    CRONTAB_TASKS=""
    CONFIGURE_SSH="n"
    SSH_PORT="22"
    SSH_ALLOW_USERS=""
    SSH_PUBKEY_AUTH=""
    SSH_PASSWORD_AUTH=""
    SSH_EMPTY_PASSWORDS=""
    SSH_ROOT_LOGIN=""
    SSH_PRINT_MOTD=""
    CONFIGURE_YUBIKEY_SSH="n"
    YUBIKEY_SSH_USER=""
    YUBIKEY_SSH_PUBLIC_KEY=""
    YUBIKEY_SSH_DISABLE_PASSWORD_AUTH="n"
    CREATE_VENV="n"
    VENV_PATH=""
    INSTALL_DOCKER="n"
    DOCKER_DISABLE_IPTABLES="n"
    ENABLE_NFTABLES="n"
    INSTALL_NFTABLES_CONF="n"
    NFTABLES_PROFILE=""
    INSTALL_NFTABLES_LOGGING="n"
    INSTALL_NFT_DOCKER_WATCH="n"
    CONFIGURE_UFW="y"
    BLOCK_ICMP="n"
    INSTALL_UFW_CUSTOM_RULES="n"
    EXTRACT_OPT_ARCHIVE="n"
    UFW_RULES_VERSION="6"
    UFW_CUSTOM_RULES_PASSWORD=""
    CONFIGURE_SYSCTL="y"
    SYSCTL_MODE="1"
    ENABLE_IP_FORWARD="n"
    INSTALL_SYSCTL_SERVICE="y"
    CONFIGURE_RESOLVED="n"
    RESOLVED_DNS=""
    RESOLVED_STUB_LISTENER_OFF=""
    RESOLVED_DNS_OVER_TLS=""
    CONFIGURE_REPOS="n"
    INSTALL_MOTD="n"
    CUSTOM_PORTS=""
    INSTALL_UFW_DOCKER="n"
    ADD_UBUNTU_PPAS="n"
    ADD_PPA_PHP="n"
    ADD_PPA_GIT="n"
    ADD_PPA_TOOLCHAIN="n"
    INSTALL_PHP_CLI="n"
    INSTALL_PHP_EXTENSIONS="n"
    ADD_NGINX_ORG="n"
    ADD_NGINX_MYGUARD="n"
    ADD_NGINX_MODULES="n"
    INSTALL_NGINX="n"
    NGINX_INSTALL_VARIANT=""
    NGINX_CUSTOM_PKGS=""
    MIGRATE_NGINX="n"
    REMOVE_NGINX="n"
    COMMENT_IPV6_INTERFACES="n"
    DISABLE_IPV6_NETPLAN="n"
    INSTALL_GO="n"
    INSTALL_IPSET="n"
    INSTALL_RCLONE="n"
    INSTALL_RUSTDESK="n"
    INSTALL_RUSTDESK_UPDATE="n"
    CONFIGURE_SWAP="n"
    SWAP_MODE="1"
    SWAP_INTERACTIVE=false
    RUN_BBR_OPTIMIZER="n"
    BBR_FORCE_IPV4="n"
    BBR_FULL_UPDATE="n"
    BBR_FIX_HOSTS="n"
    BBR_FIX_DNS="n"
    DISABLE_IPV6_GRUB="n"
    
    print_message "Non-interactive mode - using default settings:"
    print_message "- Root password: NO"
    print_message "- Create user: NO"
    print_message "- SSH configuration: NO"
    print_message "- Python venv: NO"
    print_message "- Docker: NO"
    print_message "- Docker iptables disable: NO"
    print_message "- ufw-docker: NO"
    print_message "- nftables: NO"
    print_message "- UFW: YES"
    print_message "- Block ICMP: NO"
    print_message "- sysctl: YES"
    print_message "- IP forwarding: NO"
    print_message "- systemd-resolved: NO"
    print_message "- Repositories: NO (preserve existing distro/cloud sources)"
    print_message "- MOTD: NO"
    print_message "- Custom UFW Port: None"
    print_message "- Crontab: NO"
    print_message "- BBR Optimizer: NO"
fi
echo ""

# Confirm settings
print_header "═══════════════════════════════════════════════"
print_message "Configuration Summary:"
print_message "  OS: $OS $VERSION ($VERSION_CODENAME)"
print_message "  RustDesk Server: $([ "$INSTALL_RUSTDESK" = "y" ] || [ "$INSTALL_RUSTDESK" = "Y" ] && echo "YES (Docker)" || echo "NO")"
if [ "$INSTALL_RUSTDESK" = "y" ] || [ "$INSTALL_RUSTDESK" = "Y" ]; then
    print_message "    - Weekly auto-update: $([ "$INSTALL_RUSTDESK_UPDATE" = "y" ] || [ "$INSTALL_RUSTDESK_UPDATE" = "Y" ] && echo "YES (rustdesk-update.timer)" || echo "NO")"
fi
print_message "  Root password: $([ "$SET_ROOT_PASSWORD" = "y" ] || [ "$SET_ROOT_PASSWORD" = "Y" ] && echo "YES" || echo "NO")"
print_message "  New user: $([ ! -z "$NEW_USERNAME" ] && echo "YES ($NEW_USERNAME)" || echo "NO")"
if [ ! -z "$NEW_USERNAME" ]; then
    print_message "    - SSH key: $([ "$CONFIGURE_USER_SSH_KEY" = "y" ] || [ "$CONFIGURE_USER_SSH_KEY" = "Y" ] && echo "YES" || echo "NO")"
    print_message "    - zsh: $([ "$INSTALL_ZSH" = "y" ] || [ "$INSTALL_ZSH" = "Y" ] && echo "YES" || echo "NO")"
fi
print_message "  Crontab: $([ "$CONFIGURE_CRONTAB" = "y" ] || [ "$CONFIGURE_CRONTAB" = "Y" ] && echo "YES" || echo "NO")"
print_message "  SSH Configuration: $([ "$CONFIGURE_SSH" = "y" ] || [ "$CONFIGURE_SSH" = "Y" ] && echo "YES (Port: $SSH_PORT, Users: ${SSH_ALLOW_USERS:-none})" || echo "NO")"
if [ "$CONFIGURE_SSH" = "y" ] || [ "$CONFIGURE_SSH" = "Y" ]; then
    if [ ! -z "$SSH_PUBKEY_AUTH" ]; then
        print_message "    - PubkeyAuthentication: $SSH_PUBKEY_AUTH"
    fi
    if [ ! -z "$SSH_PASSWORD_AUTH" ]; then
        print_message "    - PasswordAuthentication: $SSH_PASSWORD_AUTH"
    fi
    if [ ! -z "$SSH_EMPTY_PASSWORDS" ]; then
        print_message "    - PermitEmptyPasswords: $SSH_EMPTY_PASSWORDS"
    fi
    if [ ! -z "$SSH_ROOT_LOGIN" ]; then
        print_message "    - PermitRootLogin: $SSH_ROOT_LOGIN"
    fi
    if [ ! -z "$SSH_PRINT_MOTD" ]; then
        print_message "    - PrintMotd: $SSH_PRINT_MOTD"
    fi
fi
print_message "  YubiKey/FIDO2 SSH: $([ "$CONFIGURE_YUBIKEY_SSH" = "y" ] || [ "$CONFIGURE_YUBIKEY_SSH" = "Y" ] && echo "YES (User: ${YUBIKEY_SSH_USER:-none}, Key: $([ -n "$YUBIKEY_SSH_PUBLIC_KEY" ] && echo "provided" || echo "not provided"))" || echo "NO")"
if [ "$CONFIGURE_YUBIKEY_SSH" = "y" ] || [ "$CONFIGURE_YUBIKEY_SSH" = "Y" ]; then
    print_message "    - Disable SSH password auth: $([ "$YUBIKEY_SSH_DISABLE_PASSWORD_AUTH" = "y" ] || [ "$YUBIKEY_SSH_DISABLE_PASSWORD_AUTH" = "Y" ] && echo "YES" || echo "NO")"
fi
print_message "  Python venv: $([ "$CREATE_VENV" = "y" ] || [ "$CREATE_VENV" = "Y" ] && echo "YES (Path: $VENV_PATH)" || echo "NO")"
print_message "  Docker: $([ "$INSTALL_DOCKER" = "y" ] || [ "$INSTALL_DOCKER" = "Y" ] && echo "YES" || echo "NO")"
if [ "$INSTALL_DOCKER" = "y" ] || [ "$INSTALL_DOCKER" = "Y" ]; then
    print_message "    - Docker iptables/ip6tables disable: $([ "$DOCKER_DISABLE_IPTABLES" = "y" ] || [ "$DOCKER_DISABLE_IPTABLES" = "Y" ] && echo "YES (daemon.json: iptables+ip6tables+userland-proxy=false)" || echo "NO")"
fi
print_message "  ufw-docker: $([ "$INSTALL_UFW_DOCKER" = "y" ] || [ "$INSTALL_UFW_DOCKER" = "Y" ] && echo "YES" || echo "NO")"
print_message "  Go language: $([ "$INSTALL_GO" = "y" ] || [ "$INSTALL_GO" = "Y" ] && echo "YES (latest version)" || echo "NO")"
print_message "  ipset: $([ "$INSTALL_IPSET" = "y" ] || [ "$INSTALL_IPSET" = "Y" ] && echo "YES (distribution package)" || echo "NO")"
print_message "  rclone: $([ "$INSTALL_RCLONE" = "y" ] || [ "$INSTALL_RCLONE" = "Y" ] && echo "YES (distribution package)" || echo "NO")"
print_message "  nftables: $([ "$ENABLE_NFTABLES" = "y" ] || [ "$ENABLE_NFTABLES" = "Y" ] && echo "YES" || echo "NO")"
if [ "$ENABLE_NFTABLES" = "y" ] || [ "$ENABLE_NFTABLES" = "Y" ]; then
    if [ "$INSTALL_NFTABLES_CONF" = "y" ] || [ "$INSTALL_NFTABLES_CONF" = "Y" ]; then
        print_message "    - Config profile: ${NFTABLES_PROFILE} (${NFTABLES_CONF_FILE})"
        if [ -n "$NFTABLES_LOG_SCRIPT" ]; then
            print_message "    - Logging script: $([ "$INSTALL_NFTABLES_LOGGING" = "y" ] || [ "$INSTALL_NFTABLES_LOGGING" = "Y" ] && echo "YES (${NFTABLES_LOG_SCRIPT})" || echo "NO")"
        else
            print_message "    - Logging script: N/A (not available for this profile)"
        fi
    else
        print_message "    - Config from opt.7z: NO (default config)"
    fi
    print_message "    - nft-docker-watch: $([ "$INSTALL_NFT_DOCKER_WATCH" = "y" ] || [ "$INSTALL_NFT_DOCKER_WATCH" = "Y" ] && echo "YES (systemd service)" || echo "NO")"
fi
print_message "  UFW Firewall: $([ "$CONFIGURE_UFW" = "y" ] || [ "$CONFIGURE_UFW" = "Y" ] && echo "YES" || echo "NO")"
if [ "$CONFIGURE_UFW" = "y" ] || [ "$CONFIGURE_UFW" = "Y" ]; then
    print_message "  Block ICMP (ping): $([ "$BLOCK_ICMP" = "y" ] || [ "$BLOCK_ICMP" = "Y" ] && echo "YES" || echo "NO")"
    if [ "$INSTALL_UFW_CUSTOM_RULES" = "y" ] || [ "$INSTALL_UFW_CUSTOM_RULES" = "Y" ]; then
        UFW_SOURCE_TEXT="$([ "$UFW_INSTALL_SOURCE" = "2" ] && echo "from repository" || echo "from archive")"
        print_message "  Custom UFW Docker rules: YES (v${UFW_RULES_VERSION}, ${UFW_SOURCE_TEXT})"
        if [ "$UFW_INSTALL_SOURCE" = "1" ]; then
            print_message "    - Extract opt.7z to /opt: $([ "$EXTRACT_OPT_ARCHIVE" = "y" ] || [ "$EXTRACT_OPT_ARCHIVE" = "Y" ] && echo "YES" || echo "NO")"
        elif [ "$UFW_INSTALL_SOURCE" = "2" ] && [ -n "$UFW_SSH_PORT" ]; then
            print_message "    - Custom SSH port: $UFW_SSH_PORT"
        fi
    else
        print_message "  Custom UFW Docker rules: NO"
    fi
fi
if [ "$CONFIGURE_SYSCTL" = "y" ] || [ "$CONFIGURE_SYSCTL" = "Y" ]; then
    if [ "$SYSCTL_MODE" = "2" ]; then
        print_message "  sysctl optimization: YES (full — Linux NetworkOptimizer / bbr.sh)"
    else
        print_message "  sysctl optimization: YES (basic — static parameters)"
    fi
    print_message "  IP forwarding: $([ "$ENABLE_IP_FORWARD" = "y" ] || [ "$ENABLE_IP_FORWARD" = "Y" ] && echo "YES" || echo "NO")"
    print_message "  sysctl enforcement service: $([ "$INSTALL_SYSCTL_SERVICE" = "y" ] || [ "$INSTALL_SYSCTL_SERVICE" = "Y" ] && echo "YES" || echo "NO")"
else
    print_message "  sysctl optimization: NO"
fi
print_message "  systemd-resolved: $([ "$CONFIGURE_RESOLVED" = "y" ] || [ "$CONFIGURE_RESOLVED" = "Y" ] && echo "YES" || echo "NO")"
if [ "$CONFIGURE_RESOLVED" = "y" ] || [ "$CONFIGURE_RESOLVED" = "Y" ]; then
    print_message "    - DNS server: ${RESOLVED_DNS}"
    print_message "    - DNSStubListener: $([ "$RESOLVED_STUB_LISTENER_OFF" = "y" ] || [ "$RESOLVED_STUB_LISTENER_OFF" = "Y" ] && echo "disabled" || echo "enabled (default)")"
    print_message "    - DNSOverTLS: $([ "$RESOLVED_DNS_OVER_TLS" = "y" ] || [ "$RESOLVED_DNS_OVER_TLS" = "Y" ] && echo "yes" || echo "no")"
fi
if [ "$OS" = "debian" ] || [ "$OS" = "ubuntu" ]; then
    print_message "  IPv6 disable via GRUB: $([ "$DISABLE_IPV6_GRUB" = "y" ] || [ "$DISABLE_IPV6_GRUB" = "Y" ] && echo "YES (kernel level, both GRUB lines)" || echo "NO")"
fi
print_message "  Repositories configuration: $([ "$CONFIGURE_REPOS" = "y" ] || [ "$CONFIGURE_REPOS" = "Y" ] && echo "YES" || echo "NO")"
if [ "$OS" = "ubuntu" ] && { [ "$ADD_UBUNTU_PPAS" = "y" ] || [ "$ADD_UBUNTU_PPAS" = "Y" ]; }; then
    print_message "  Ubuntu PPA repositories:"
    if [ "$ADD_PPA_PHP" = "y" ] || [ "$ADD_PPA_PHP" = "Y" ]; then
        print_message "    - Ondrej PHP: YES"
        print_message "      - php-cli: $([ "$INSTALL_PHP_CLI" = "y" ] || [ "$INSTALL_PHP_CLI" = "Y" ] && echo "YES" || echo "NO")"
        if [ "$INSTALL_PHP_CLI" = "y" ] || [ "$INSTALL_PHP_CLI" = "Y" ]; then
            print_message "      - PHP extensions: $([ "$INSTALL_PHP_EXTENSIONS" = "y" ] || [ "$INSTALL_PHP_EXTENSIONS" = "Y" ] && echo "YES" || echo "NO")"
        fi
    fi
    if [ "$ADD_PPA_GIT" = "y" ] || [ "$ADD_PPA_GIT" = "Y" ]; then
        print_message "    - Git Core: YES"
    fi
    if [ "$ADD_PPA_TOOLCHAIN" = "y" ] || [ "$ADD_PPA_TOOLCHAIN" = "Y" ]; then
        print_message "    - Ubuntu Toolchain: YES"
    fi
fi
if [ "$OS" = "debian" ] || [ "$OS" = "ubuntu" ]; then
    if [ "$REMOVE_NGINX" = "y" ] || [ "$REMOVE_NGINX" = "Y" ]; then
        print_message "  Completely REMOVE nginx:                    YES (backup /etc/nginx + purge all)"
    fi
    if [ "$ADD_NGINX_ORG" = "y" ] || [ "$ADD_NGINX_ORG" = "Y" ]; then
        print_message "  Official nginx.org repository:               YES"
    fi
    if [ "$ADD_NGINX_MYGUARD" = "y" ] || [ "$ADD_NGINX_MYGUARD" = "Y" ]; then
        print_message "  Third-party deb.myguard.nl Nginx repo:      YES"
    fi
    if [ "$ADD_NGINX_MODULES" = "y" ] || [ "$ADD_NGINX_MODULES" = "Y" ]; then
        print_message "  nginx-modules.com (Blendbyte) modules repo: YES"
    fi
    if [ "$INSTALL_NGINX" = "y" ] || [ "$INSTALL_NGINX" = "Y" ]; then
        print_message "  Install nginx now:                          YES (preset ${NGINX_INSTALL_VARIANT:-?})"
        if [ "$MIGRATE_NGINX" = "y" ] || [ "$MIGRATE_NGINX" = "Y" ]; then
            print_message "  Migrate existing nginx (backup + swap):     YES"
        fi
    fi
fi
print_message "  Comment IPv6 in /etc/network/interfaces: $([ "$COMMENT_IPV6_INTERFACES" = "y" ] || [ "$COMMENT_IPV6_INTERFACES" = "Y" ] && echo "YES" || echo "NO")"
print_message "  Disable IPv6 in /etc/netplan/*.yaml:      $([ "$DISABLE_IPV6_NETPLAN" = "y" ] || [ "$DISABLE_IPV6_NETPLAN" = "Y" ] && echo "YES (validated, manual apply)" || echo "NO")"
print_message "  Custom MOTD: $([ "$INSTALL_MOTD" = "y" ] || [ "$INSTALL_MOTD" = "Y" ] && echo "YES" || echo "NO")"
if [ ! -z "$CUSTOM_PORTS" ]; then
    print_message "  UFW Custom Ports: $CUSTOM_PORTS"
else
    print_message "  UFW Custom Ports: None"
fi
if [ "$CONFIGURE_SWAP" = "y" ] || [ "$CONFIGURE_SWAP" = "Y" ]; then
    if [ "$SWAP_INTERACTIVE" = true ]; then
        print_message "  Swap Configuration: YES (interactive wizard)"
    else
        print_message "  Swap Configuration: YES (auto-detect by RAM)"
    fi
else
    print_message "  Swap Configuration: NO"
fi
if [ "$SYSCTL_MODE" = "2" ]; then
    print_message "  Linux NetworkOptimizer (bbr.sh): YES"
    print_message "    - Force IPv4 APT: $([ "$BBR_FORCE_IPV4" = "y" ] || [ "$BBR_FORCE_IPV4" = "Y" ] && echo "YES" || echo "NO")"
    print_message "    - Full Update: $([ "$BBR_FULL_UPDATE" = "y" ] || [ "$BBR_FULL_UPDATE" = "Y" ] && echo "YES" || echo "NO")"
    print_message "    - Fix /etc/hosts: $([ "$BBR_FIX_HOSTS" = "y" ] || [ "$BBR_FIX_HOSTS" = "Y" ] && echo "YES" || echo "NO")"
    if { [ "$CONFIGURE_RESOLVED" = "y" ] || [ "$CONFIGURE_RESOLVED" = "Y" ]; } && [ "$BBR_FIX_DNS" = "n" ]; then
        print_message "    - Fix DNS: SKIPPED (systemd-resolved configured)"
    else
        print_message "    - Fix DNS: $([ "$BBR_FIX_DNS" = "y" ] || [ "$BBR_FIX_DNS" = "Y" ] && echo "YES" || echo "NO")"
    fi
fi
if { [ "$CONFIGURE_UFW" = "y" ] || [ "$CONFIGURE_UFW" = "Y" ]; } && \
   { [ "$INSTALL_DOCKER" = "y" ] || [ "$INSTALL_DOCKER" = "Y" ]; } && \
   { [ "$INSTALL_UFW_DOCKER" != "y" ] && [ "$INSTALL_UFW_DOCKER" != "Y" ]; }; then
    print_warning "Docker with UFW selected, but ufw-docker is not selected; Docker-published ports can bypass UFW"
fi
if { [ "$DOCKER_DISABLE_IPTABLES" = "y" ] || [ "$DOCKER_DISABLE_IPTABLES" = "Y" ]; } && \
   { [ "$ENABLE_NFTABLES" != "y" ] && [ "$ENABLE_NFTABLES" != "Y" ]; }; then
    print_warning "Docker iptables disable selected without nftables; container port publishing/NAT may stop working"
fi
print_header "═══════════════════════════════════════════════"
echo ""

if [ "$INTERACTIVE" = true ]; then
    prompt_read -r -p "Continue with these settings? (Y/n): " CONFIRM
    CONFIRM=${CONFIRM:-y}
    
    if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
        print_error "Installation cancelled by user"
        exit 0
    fi
else
    print_message "Continuing with default settings (non-interactive mode)..."
    sleep 2
fi

echo ""
print_message "Starting installation..."
echo ""

configure_apt_repositories() {
    local sources_dir=/etc/apt/sources.list.d main=/etc/apt/sources.list
    local target stage_main stage_sources archive security components suites timestamp
    local target_existed=false main_existed=false
    timestamp=$(date +%Y%m%d-%H%M%S)
    mkdir -p "$sources_dir" || return 1
    stage_main=$(mktemp) || return 1
    stage_sources=$(mktemp) || { rm -f -- "$stage_main"; return 1; }
    target="$sources_dir/$OS.sources"

    if [ -e "$target" ]; then
        cp -p -- "$target" "$target.backup.$timestamp~" || return 1
        target_existed=true
    fi
    if [ -e "$main" ]; then
        cp -p -- "$main" "$main.backup.$timestamp~" || return 1
        main_existed=true
        # Keep unrelated repositories and comments in the main sources.list.
        # Remove only distro entries replaced by the new DEB822 definition.
        awk -v os="$OS" '
            /^[[:space:]]*deb(-src)?[[:space:]]/ {
                if (os == "debian" && /https?:\/\/(deb|security|ftp([.][a-z]+)?)\.debian\.org\//) next
                if (os == "ubuntu" && /https?:\/\/(([a-z]+\.)?archive|security|ports)\.ubuntu\.com\//) next
            }
            { print }
        ' "$main" > "$stage_main" || return 1
    fi

    case "$OS" in
        debian)
            archive=https://deb.debian.org/debian
            security=https://deb.debian.org/debian-security
            components='main contrib non-free non-free-firmware'
            suites="$VERSION_CODENAME $VERSION_CODENAME-updates"
            [ "$VERSION" = 12 ] && suites="$suites $VERSION_CODENAME-backports"
            ;;
        ubuntu)
            case "$(dpkg --print-architecture)" in
                amd64|i386) archive=https://archive.ubuntu.com/ubuntu; security=https://security.ubuntu.com/ubuntu ;;
                *) archive=https://ports.ubuntu.com/ubuntu-ports; security="$archive" ;;
            esac
            components='main restricted universe multiverse'
            suites="$VERSION_CODENAME $VERSION_CODENAME-updates $VERSION_CODENAME-backports"
            ;;
        *) rm -f -- "$stage_main" "$stage_sources"; return 1 ;;
    esac
    cat > "$stage_sources" <<REPOS
Types: deb
URIs: $archive
Suites: $suites
Components: $components
Signed-By: /usr/share/keyrings/$OS-archive-keyring.gpg

Types: deb
URIs: $security
Suites: $VERSION_CODENAME-security
Components: $components
Signed-By: /usr/share/keyrings/$OS-archive-keyring.gpg
REPOS
    if write_file_atomic "$target" 0644 root:root < "$stage_sources" &&
       write_file_atomic "$main" 0644 root:root < "$stage_main"; then
        rm -f -- "$stage_main" "$stage_sources"
        print_message "Distribution repositories configured in $target; unrelated sources preserved"
        return 0
    fi
    print_error "Failed to write APT sources; restoring backups"
    if [ "$target_existed" = true ]; then cp -p -- "$target.backup.$timestamp~" "$target"; else rm -f -- "$target"; fi
    if [ "$main_existed" = true ]; then cp -p -- "$main.backup.$timestamp~" "$main"; else rm -f -- "$main"; fi
    rm -f -- "$stage_main" "$stage_sources"
    return 1
}

if is_yes "$ADD_NGINX_ORG" && is_yes "$ADD_NGINX_MYGUARD"; then
    print_error "Choose one nginx package source: nginx.org or deb.myguard.nl"
    exit 1
fi

# Repository configuration must happen before the first apt update/package
# install; otherwise minimal or stale systems can fail before the script gets a
# chance to fix their sources.
if [ "$CONFIGURE_REPOS" = "y" ] || [ "$CONFIGURE_REPOS" = "Y" ]; then
    configure_apt_repositories || { print_error "Repository configuration failed"; exit 1; }
    echo ""
fi

# Update package lists
print_message "Updating package lists..."
if apt-get update; then
    print_message "Package lists updated successfully"
else
    print_error "CRITICAL: Failed to update package lists"
    print_error "Installation cannot continue"
    exit 1
fi

# Common packages for both Debian and Ubuntu
COMMON_PACKAGES=(
    htop
    mc
    mc-data
    wget
    #iptables
    #ufw
    shellcheck
    nano
    apt-utils
    curl
    git
    rsyslog
    systemd
    auditd
    manpages
    gnupg2
    sudo
    net-tools
    apache2-utils
    sqlite3
    ca-certificates
    lsb-release
    traceroute
    cron
    pwgen
    libwww-perl
    apg
    makepasswd
    squashfs-tools
    jq
    bash
    build-essential
    pkg-config
    libmnl-dev
    libnftnl-dev
    autoconf
    automake
    libtool
    python3
    python3-venv
    vim
    rsync
)

# Keep ufw out of the unconditional base package set. Install it only when the
# operator explicitly selected UFW configuration.
if [ "$CONFIGURE_UFW" = "y" ] || [ "$CONFIGURE_UFW" = "Y" ]; then
    COMMON_PACKAGES+=(ufw)
fi

# Add zsh if requested
if [ "$INSTALL_ZSH" = "y" ] || [ "$INSTALL_ZSH" = "Y" ]; then
    COMMON_PACKAGES+=(zsh)
fi

# Add OpenSSH server/client when the script will manage SSH settings
if [ "$CONFIGURE_SSH" = "y" ] || [ "$CONFIGURE_SSH" = "Y" ] || \
   [ "$CONFIGURE_YUBIKEY_SSH" = "y" ] || [ "$CONFIGURE_YUBIKEY_SSH" = "Y" ]; then
    COMMON_PACKAGES+=(openssh-client openssh-server)
fi

# Debian-specific packages
# You can comment out (#) any package to disable its installation
DEBIAN_PACKAGES=(
    openvswitch-switch-dpdk
)

# Add linux-headers only if available for the running kernel
if apt-cache show "linux-headers-$(uname -r)" &>/dev/null; then
    DEBIAN_PACKAGES+=("linux-headers-$(uname -r)")
else
    print_warning "linux-headers-$(uname -r) not available (kernel updated without reboot?), skipping"
fi

# Ubuntu-specific packages
# linux-headers-$(uname -r) is added below only when the package exists
# You can comment out (#) any package to disable its installation
UBUNTU_PACKAGES=(
    landscape-common
    update-notifier-common
    ubuntu-keyring
    openvswitch-switch-dpdk
)

# Add linux-headers only if available for the running kernel
if apt-cache show "linux-headers-$(uname -r)" &>/dev/null; then
    UBUNTU_PACKAGES+=("linux-headers-$(uname -r)")
else
    print_warning "linux-headers-$(uname -r) not available (kernel updated without reboot?), skipping"
fi

# Install packages based on OS
print_message "Installing packages..."

if [ "$OS" = "debian" ]; then
    print_message "Installing common packages for Debian..."
    if ! apt-get install -y "${COMMON_PACKAGES[@]}"; then
        print_error "CRITICAL: Failed to install required Debian packages"
        exit 1
    fi
    
    if [ ${#DEBIAN_PACKAGES[@]} -gt 0 ]; then
        print_message "Installing Debian-specific packages..."
        apt-get install -y "${DEBIAN_PACKAGES[@]}" || print_warning "Some Debian-specific packages may not be available"
    else
        print_message "No Debian-specific packages to install"
    fi
    
elif [ "$OS" = "ubuntu" ]; then
    print_message "Installing common packages for Ubuntu..."
    if ! apt-get install -y "${COMMON_PACKAGES[@]}"; then
        print_error "CRITICAL: Failed to install required Ubuntu packages"
        exit 1
    fi
    
    if [ ${#UBUNTU_PACKAGES[@]} -gt 0 ]; then
        print_message "Installing Ubuntu-specific packages..."
        apt-get install -y "${UBUNTU_PACKAGES[@]}" || print_warning "Some Ubuntu-specific packages may not be available"
    else
        print_message "No Ubuntu-specific packages to install"
    fi
fi

# ============================================
# INSTALL RUSTDESK SERVER (DOCKER)
# ============================================

if [ "$INSTALL_RUSTDESK" = "y" ] || [ "$INSTALL_RUSTDESK" = "Y" ]; then
    print_message "Installing RustDesk server in Docker..."
    echo ""

    RUSTDESK_DIR="/opt/rustdesk"
    RUSTDESK_SERVICE_PATH="/etc/systemd/system/rustdesk-compose.service"
    RUSTDESK_COMPOSE_SHA256="a73353e35c6db908c3f82d7832f6d289692d96a08a243c2e47321ae5fe9d87ad"
    RUSTDESK_SERVICE_SHA256="0edca9b82c6c7f5c35bd93c6618dc42be21dbea29baf2d404f89830b171b0094"
    RUSTDESK_OK=true

    # Create rustdesk directory
    print_message "Creating directory: $RUSTDESK_DIR..."
    if mkdir -p "$RUSTDESK_DIR"; then
        print_message "Directory created successfully"
    else
        print_error "Failed to create directory $RUSTDESK_DIR"
        print_warning "RustDesk installation will be skipped; setup will continue"
        RUSTDESK_OK=false
    fi

    # Download docker-compose.yml
    if [ "$RUSTDESK_OK" = true ]; then
        print_message "Downloading docker-compose.yml..."
        if install_verified_repo_asset "config/docker-compose.yml" "${RUSTDESK_DIR}/docker-compose.yml" "$RUSTDESK_COMPOSE_SHA256" 0644; then
            print_message "docker-compose.yml verified and installed"
        else
            print_error "Failed to download docker-compose.yml"
            print_warning "RustDesk installation will be skipped; setup will continue"
            RUSTDESK_OK=false
        fi
    fi

    # Download systemd service file
    if [ "$RUSTDESK_OK" = true ]; then
        print_message "Downloading systemd service file..."
        if install_verified_repo_asset "config/rustdesk-compose.service" "$RUSTDESK_SERVICE_PATH" "$RUSTDESK_SERVICE_SHA256" 0644; then
            print_message "Service file verified and installed"
        else
            print_error "Failed to download service file"
            print_warning "RustDesk installation will be skipped; setup will continue"
            RUSTDESK_OK=false
        fi
    fi

    # Reload systemd daemon
    if [ "$RUSTDESK_OK" = true ]; then
        print_message "Reloading systemd daemon..."
        if systemctl daemon-reload; then
            print_message "Systemd daemon reloaded successfully"
        else
            print_error "Failed to reload systemd daemon for RustDesk"
            print_warning "RustDesk service will not be enabled; setup will continue"
            RUSTDESK_OK=false
        fi
    fi

    # Enable rustdesk service
    if [ "$RUSTDESK_OK" = true ]; then
        print_message "Enabling rustdesk-compose service..."
        if systemctl enable rustdesk-compose.service; then
            print_message "Service enabled successfully"
        else
            print_error "Failed to enable rustdesk-compose service"
            print_warning "RustDesk service will not start automatically; setup will continue"
            RUSTDESK_OK=false
        fi
    fi

    # Check if Docker is installed and running (needed to start the service)
    if [ "$RUSTDESK_OK" != true ]; then
        print_warning "Skipping RustDesk container start because installation did not complete"
    elif command -v docker &> /dev/null && systemctl is-active --quiet docker 2>/dev/null; then
        print_message "Docker is running, starting RustDesk containers..."

        # Pull images first to avoid timeout on slow connections
        if docker compose -f "${RUSTDESK_DIR}/docker-compose.yml" pull 2>/dev/null; then
            print_message "RustDesk images pulled successfully"
        else
            print_warning "Failed to pull images (will try on service start)"
        fi

        if systemctl start rustdesk-compose.service; then
            sleep 5
            if systemctl is-active --quiet rustdesk-compose.service; then
                print_success "RustDesk service is running"
                # Show container status
                docker compose -f "${RUSTDESK_DIR}/docker-compose.yml" ps 2>/dev/null || true
            else
                print_warning "RustDesk service started but containers may still be initializing"
                print_message "Check status: systemctl status rustdesk-compose.service"
                print_message "Check logs:   docker compose -f ${RUSTDESK_DIR}/docker-compose.yml logs"
            fi
        else
            print_error "Failed to start RustDesk service"
            print_message "Try manually: systemctl start rustdesk-compose.service"
            print_message "Check logs:   journalctl -u rustdesk-compose.service"
        fi
    elif command -v docker &> /dev/null; then
        print_message "Docker is installed but not running"
        print_message "RustDesk containers will start after Docker service is active"
    else
        print_message "Docker is not installed yet"
        print_message "RustDesk containers will start automatically after Docker installation"
    fi

    # --- Weekly auto-update timer (optional) ---
    if [ "$RUSTDESK_OK" = true ] && { [ "$INSTALL_RUSTDESK_UPDATE" = "y" ] || [ "$INSTALL_RUSTDESK_UPDATE" = "Y" ]; }; then
        echo ""
        print_message "Installing RustDesk weekly auto-update timer..."

        RUSTDESK_UPDATE_SERVICE_PATH="/etc/systemd/system/rustdesk-update.service"
        RUSTDESK_UPDATE_TIMER_PATH="/etc/systemd/system/rustdesk-update.timer"
        RUSTDESK_UPDATE_SCRIPT_PATH="/usr/local/sbin/rustdesk-safe-update.sh"
        RUSTDESK_UPDATE_SERVICE_SHA256="597de499d52ce1fa058624289fde8c5739d90bba43a6ea5a4a249f7a0a6ba874"
        RUSTDESK_UPDATE_TIMER_SHA256="281e81c5cd6515341b904de91f742cf0e203657303c33d12b668fd256545d961"
        RUSTDESK_UPDATE_SCRIPT_SHA256="0eab8fb576d06c0e836febc725706a458b3b86051cf73bed35168ce7a957ae5e"

        RUSTDESK_UPDATE_OK=true

        if install_verified_repo_asset "config/rustdesk-update.service" "$RUSTDESK_UPDATE_SERVICE_PATH" "$RUSTDESK_UPDATE_SERVICE_SHA256" 0644; then
            print_message "rustdesk-update.service verified and installed"
        else
            print_warning "Failed to download rustdesk-update.service"
            RUSTDESK_UPDATE_OK=false
        fi

        if [ "$RUSTDESK_UPDATE_OK" = true ]; then
            if install_verified_repo_asset "config/rustdesk-update.timer" "$RUSTDESK_UPDATE_TIMER_PATH" "$RUSTDESK_UPDATE_TIMER_SHA256" 0644; then
                print_message "rustdesk-update.timer verified and installed"
            else
                print_warning "Failed to download rustdesk-update.timer"
                RUSTDESK_UPDATE_OK=false
            fi
        fi

        if [ "$RUSTDESK_UPDATE_OK" = true ]; then
            if install_verified_repo_asset "config/rustdesk-safe-update.sh" "$RUSTDESK_UPDATE_SCRIPT_PATH" "$RUSTDESK_UPDATE_SCRIPT_SHA256" 0755; then
                print_message "rustdesk-safe-update.sh verified and installed"
            else
                print_warning "Failed to install rustdesk-safe-update.sh"
                RUSTDESK_UPDATE_OK=false
            fi
        fi

        if [ "$RUSTDESK_UPDATE_OK" = true ]; then
            chmod 644 "$RUSTDESK_UPDATE_SERVICE_PATH" "$RUSTDESK_UPDATE_TIMER_PATH"

            # Reload systemd to pick up new unit files
            systemctl daemon-reload

            # Enable and start the timer (not the service — the timer triggers it)
            if systemctl enable rustdesk-update.timer 2>/dev/null && \
               systemctl start rustdesk-update.timer 2>/dev/null; then
                print_success "rustdesk-update.timer enabled and started"
                NEXT_RUN=$(systemctl list-timers rustdesk-update.timer --no-pager 2>/dev/null | awk 'NR==2 {print $1, $2}')
                [ -n "$NEXT_RUN" ] && print_message "  Next run: $NEXT_RUN"
                print_message "  Schedule:  Sunday 04:00 (±1h random delay)"
                print_message "  Manual run: systemctl start rustdesk-update.service"
                print_message "  Logs:      journalctl -u rustdesk-update.service"
                print_message "  Status:    systemctl list-timers rustdesk-update.timer"
            else
                print_error "Failed to enable/start rustdesk-update.timer"
                RUSTDESK_UPDATE_OK=false
            fi
        else
            print_warning "Auto-update timer installation skipped due to download errors"
        fi
    fi

    echo ""
    if [ "$RUSTDESK_OK" = true ]; then
        print_success "RustDesk installation completed"
    else
        print_error "RustDesk installation did not complete"
    fi
    print_message "  Directory: $RUSTDESK_DIR"
    print_message "  Service:   rustdesk-compose.service"
    print_message "  Manage:    systemctl {start|stop|restart|status} rustdesk-compose.service"
    if [ "$INSTALL_RUSTDESK_UPDATE" = "y" ] || [ "$INSTALL_RUSTDESK_UPDATE" = "Y" ]; then
        print_message "  Auto-update: rustdesk-update.timer (weekly, Sun 04:00)"
    fi
    echo ""
else
    print_message "Skipping RustDesk installation (not requested)"
fi

# ============================================
# SET ROOT PASSWORD
# ============================================

if [ "$SET_ROOT_PASSWORD" = "y" ] || [ "$SET_ROOT_PASSWORD" = "Y" ]; then
    print_message "Setting root password..."
    if printf '%s:%s\n' "root" "$ROOT_PASSWORD" | chpasswd; then
        ROOT_PASSWORD_OK=true
        print_message "Root password set successfully"
    else
        print_error "Failed to set root password"
    fi
    unset ROOT_PASSWORD ROOT_PASSWORD_CONFIRM
    echo ""
fi

# ============================================
# CREATE NEW USER (after packages with sudo)
# ============================================

if [ "$CREATE_USER" = "y" ] || [ "$CREATE_USER" = "Y" ]; then
    print_message "Creating new user: $NEW_USERNAME"
    
    # Create user with home directory
    if adduser --gecos "" --disabled-password "$NEW_USERNAME"; then
        print_message "User $NEW_USERNAME created successfully"
        
        # Set password
        if ! printf '%s:%s\n' "$NEW_USERNAME" "$NEW_USER_PASSWORD" | chpasswd; then
            print_error "Failed to set password for $NEW_USERNAME; account remains locked"
            exit 1
        fi
        unset NEW_USER_PASSWORD NEW_USER_PASSWORD_CONFIRM
        print_message "Password set for $NEW_USERNAME"
        
        # Add user to sudo group
        gpasswd -a "$NEW_USERNAME" sudo || { print_error "Failed to grant sudo access to $NEW_USERNAME"; exit 1; }
        print_message "User $NEW_USERNAME added to sudo group"
    else
        print_error "Failed to create user $NEW_USERNAME"
        exit 1
    fi
    echo ""
elif [ "$CREATE_USER" = "existing" ]; then
    print_message "Using existing user: $NEW_USERNAME"
    
    # Ensure user is in sudo group
    if ! groups "$NEW_USERNAME" | grep -q "\bsudo\b"; then
        gpasswd -a "$NEW_USERNAME" sudo || { print_error "Failed to grant sudo access to $NEW_USERNAME"; exit 1; }
        print_message "User $NEW_USERNAME added to sudo group"
    else
        print_message "User $NEW_USERNAME is already in sudo group"
    fi
    echo ""
fi

# ============================================
# CONFIGURE SSH KEY FOR USER
# ============================================

if ( [ "$CONFIGURE_USER_SSH_KEY" = "y" ] || [ "$CONFIGURE_USER_SSH_KEY" = "Y" ] ) && [ ! -z "$NEW_USERNAME" ]; then
    print_message "Configuring SSH key for $NEW_USERNAME"
    
    if install_user_public_key "$NEW_USERNAME" "$USER_SSH_KEY"; then
        USER_SSH_KEY_OK=true
        print_message "SSH key configured successfully for $NEW_USERNAME"
    else
        print_error "Failed to install SSH key for $NEW_USERNAME; stopping before SSH authentication changes"
        exit 1
    fi
    echo ""
fi

# ============================================
# CONFIGURE YUBIKEY / FIDO2 SSH AUTHENTICATION
# ============================================

if [ "$CONFIGURE_YUBIKEY_SSH" = "y" ] || [ "$CONFIGURE_YUBIKEY_SSH" = "Y" ]; then
    print_message "Configuring YubiKey/FIDO2 SSH authentication..."
    echo ""

    YUBIKEY_SSH_OK=true

    install_required_yubikey_package() {
        local pkg="$1"
        if apt-cache show "$pkg" &>/dev/null; then
            if apt-get install -y "$pkg"; then
                print_message "Installed package: $pkg"
            else
                print_error "Failed to install required package: $pkg"
                YUBIKEY_SSH_OK=false
            fi
        else
            print_error "Required package is not available in configured repositories: $pkg"
            YUBIKEY_SSH_OK=false
        fi
    }

    install_optional_yubikey_package() {
        local pkg="$1"
        if apt-cache show "$pkg" &>/dev/null; then
            if apt-get install -y "$pkg"; then
                print_message "Installed optional package: $pkg"
            else
                print_warning "Failed to install optional package: $pkg"
            fi
        else
            print_warning "Optional package not available, skipping: $pkg"
        fi
    }

    # Try to install the first available alternative from a list (e.g. libfido2-1
    # vs libfido2t64-1 after Ubuntu's t64 transition). Marks YUBIKEY_SSH_OK=false
    # if none are available.
    install_required_yubikey_package_alts() {
        local label="$1"; shift
        local pkg
        for pkg in "$@"; do
            if apt-cache show "$pkg" &>/dev/null; then
                if apt-get install -y "$pkg"; then
                    print_message "Installed $label package: $pkg"
                    return 0
                fi
            fi
        done
        print_error "None of the candidate packages for $label could be installed: $*"
        YUBIKEY_SSH_OK=false
        return 1
    }

    print_message "Installing OpenSSH/FIDO2 support packages..."
    install_required_yubikey_package openssh-client
    install_required_yubikey_package openssh-server
    # libfido2-1 was renamed to libfido2t64-1 on Ubuntu 24.04+ during the t64 transition.
    install_required_yubikey_package_alts "libfido2 runtime" libfido2-1 libfido2t64-1
    install_optional_yubikey_package libu2f-udev
    install_optional_yubikey_package yubikey-manager

    # YUBIKEY_SSH_FIDO2_SUPPORTED gates everything that requires sk-* key support
    # in sshd: writing the drop-in, and especially disabling password auth.
    # Without FIDO2-capable OpenSSH, configuring the drop-in + disabling passwords
    # would lock the user out (no working auth methods left).
    YUBIKEY_SSH_FIDO2_SUPPORTED=true
    if command -v ssh &>/dev/null; then
        SSH_VERSION_RAW=$(ssh -V 2>&1 || true)
        print_message "OpenSSH client version: $SSH_VERSION_RAW"
        SSH_VERSION_MAJOR=$(printf '%s\n' "$SSH_VERSION_RAW" | sed -nE 's/^OpenSSH_([0-9]+)\.([0-9]+).*/\1/p')
        SSH_VERSION_MINOR=$(printf '%s\n' "$SSH_VERSION_RAW" | sed -nE 's/^OpenSSH_([0-9]+)\.([0-9]+).*/\2/p')
        if [ -n "$SSH_VERSION_MAJOR" ] && [ -n "$SSH_VERSION_MINOR" ]; then
            if [ "$SSH_VERSION_MAJOR" -lt 8 ] || { [ "$SSH_VERSION_MAJOR" -eq 8 ] && [ "$SSH_VERSION_MINOR" -lt 2 ]; }; then
                print_error "OpenSSH 8.2+ is required for FIDO2 security key SSH authentication; this system has $SSH_VERSION_RAW"
                print_error "Skipping sshd drop-in to avoid locking you out (sshd cannot accept sk-* keys)"
                YUBIKEY_SSH_FIDO2_SUPPORTED=false
                YUBIKEY_SSH_OK=false
                if [ "$YUBIKEY_SSH_DISABLE_PASSWORD_AUTH" = "y" ] || [ "$YUBIKEY_SSH_DISABLE_PASSWORD_AUTH" = "Y" ]; then
                    print_warning "Forcing YUBIKEY_SSH_DISABLE_PASSWORD_AUTH=n: password auth must remain enabled"
                    YUBIKEY_SSH_DISABLE_PASSWORD_AUTH="n"
                fi
            elif [ "$SSH_VERSION_MAJOR" -eq 8 ] && [ "$SSH_VERSION_MINOR" -eq 2 ]; then
                print_warning "OpenSSH 8.3+ is recommended for verify-required/PIN enforcement"
            fi
        else
            print_warning "Could not parse OpenSSH version; continuing with sshd validation"
        fi
    fi

    YUBIKEY_AUTHORIZED_KEYS=""
    if [ -n "$YUBIKEY_SSH_PUBLIC_KEY" ]; then
        if install_user_public_key "$YUBIKEY_SSH_USER" "$YUBIKEY_SSH_PUBLIC_KEY"; then
            YUBIKEY_USER_HOME=$(getent passwd "$YUBIKEY_SSH_USER" | cut -d: -f6)
            YUBIKEY_AUTHORIZED_KEYS="$YUBIKEY_USER_HOME/.ssh/authorized_keys"
            print_success "YubiKey SSH public key installed"
        else
            print_error "Failed to install YubiKey public key; SSH authentication was left unchanged"
            YUBIKEY_SSH_OK=false
        fi
    else
        print_warning "No YubiKey SSH public key provided; installed packages and sshd support only"
    fi

    SSHD_CONFIG="/etc/ssh/sshd_config"
    SSHD_CONFIG_DIR="/etc/ssh/sshd_config.d"
    YUBIKEY_SSHD_DROPIN="${SSHD_CONFIG_DIR}/00-yubikey-fido2.conf"

    if [ "$YUBIKEY_SSH_FIDO2_SUPPORTED" != true ] || [ "$YUBIKEY_SSH_OK" != true ]; then
        print_warning "Skipping sshd drop-in for YubiKey: OpenSSH does not support FIDO2 sk-* key types on this system"
        print_warning "Authorized key (if any) has been added but sshd will not accept it until OpenSSH is upgraded to 8.2+"
    elif [ ! -f "$SSHD_CONFIG" ]; then
        print_error "sshd_config not found: $SSHD_CONFIG"
        YUBIKEY_SSH_OK=false
    else
        YUBIKEY_SSHD_BACKUP="${SSHD_CONFIG}.backup.yubikey.$(date +%Y%m%d-%H%M%S)~"
        cp "$SSHD_CONFIG" "$YUBIKEY_SSHD_BACKUP"
        print_message "Original sshd_config backed up: $YUBIKEY_SSHD_BACKUP"

        mkdir -p "$SSHD_CONFIG_DIR"
        YUBIKEY_DROPIN_BACKUP=""
        if [ -e "$YUBIKEY_SSHD_DROPIN" ]; then
            YUBIKEY_DROPIN_BACKUP="${YUBIKEY_SSHD_DROPIN}.backup.$(date +%Y%m%d-%H%M%S)~"
            cp -a -- "$YUBIKEY_SSHD_DROPIN" "$YUBIKEY_DROPIN_BACKUP" || exit 1
        fi

        if ! ensure_sshd_include_first "$SSHD_CONFIG"; then
            print_error "Failed to ensure Include directive in $SSHD_CONFIG; restoring backup"
            cp "$YUBIKEY_SSHD_BACKUP" "$SSHD_CONFIG"
            YUBIKEY_SSH_OK=false
        else
            if ! {
                echo "# Managed by system-setup.sh - YubiKey/FIDO2 SSH support"
                echo "# OpenSSH 8.2+ supports FIDO2 sk-* public key types."
                echo "# WARNING: This file is regenerated on every run; manual edits will be lost."
                echo "PubkeyAuthentication yes"
                if [ "$YUBIKEY_SSH_DISABLE_PASSWORD_AUTH" = "y" ] || [ "$YUBIKEY_SSH_DISABLE_PASSWORD_AUTH" = "Y" ]; then
                    echo "PasswordAuthentication no"
                    echo "KbdInteractiveAuthentication no"
                fi
            } | write_file_atomic "$YUBIKEY_SSHD_DROPIN" 0644 root:root; then
                print_error "Failed to write sshd drop-in: $YUBIKEY_SSHD_DROPIN"
                YUBIKEY_SSH_OK=false
            else
                print_message "Created sshd drop-in: $YUBIKEY_SSHD_DROPIN"

                if sshd -t; then
                    print_success "sshd configuration is valid"
                    if systemctl restart sshd 2>/dev/null; then
                        print_message "SSH service restarted (sshd)"
                    elif systemctl restart ssh 2>/dev/null; then
                        print_message "SSH service restarted (ssh)"
                    elif service ssh restart 2>/dev/null; then
                        print_message "SSH service restarted (service ssh)"
                    elif service sshd restart 2>/dev/null; then
                        print_message "SSH service restarted (service sshd)"
                    else
                        print_warning "Could not restart SSH automatically; restart manually after checking active sessions"
                    fi
                else
                    print_error "sshd configuration validation failed; restoring backup"
                    rm -f "$YUBIKEY_SSHD_DROPIN"
                    [ -n "$YUBIKEY_DROPIN_BACKUP" ] && cp -a -- "$YUBIKEY_DROPIN_BACKUP" "$YUBIKEY_SSHD_DROPIN"
                    cp "$YUBIKEY_SSHD_BACKUP" "$SSHD_CONFIG"
                    if [ -n "$YUBIKEY_SSH_PUBLIC_KEY" ] && [ -n "${YUBIKEY_AUTHORIZED_KEYS:-}" ] && [ -f "$YUBIKEY_AUTHORIZED_KEYS" ]; then
                        print_warning "Public key was already appended to $YUBIKEY_AUTHORIZED_KEYS and was NOT rolled back."
                        print_warning "Review and remove the FIDO2 line manually if desired: sudo -u $YUBIKEY_SSH_USER nano $YUBIKEY_AUTHORIZED_KEYS"
                    fi
                    YUBIKEY_SSH_OK=false
                fi
            fi
        fi
    fi

    if [ "$YUBIKEY_SSH_OK" = true ]; then
        print_success "YubiKey/FIDO2 SSH authentication configuration completed"
    else
        print_warning "YubiKey/FIDO2 SSH authentication completed with warnings/errors; review messages above"
    fi
    echo ""
else
    print_message "Skipping YubiKey/FIDO2 SSH authentication (not requested)"
fi

# ============================================
# ADD UBUNTU PPA REPOSITORIES
# ============================================

if [ "$OS" = "ubuntu" ] && { [ "$ADD_UBUNTU_PPAS" = "y" ] || [ "$ADD_UBUNTU_PPAS" = "Y" ]; }; then
    print_message "Adding Ubuntu PPA repositories..."
    echo ""
    
    # Install software-properties-common if not already installed (provides add-apt-repository)
    if ! command -v add-apt-repository &> /dev/null; then
        print_message "Installing software-properties-common..."
        apt-get install -y software-properties-common
    fi

    if [[ "$ADD_PPA_PHP" =~ ^[yY]$ ]]; then
        add_supported_ubuntu_ppa ppa:ondrej/php || ADD_PPA_PHP="n"
    fi
    if [[ "$ADD_PPA_GIT" =~ ^[yY]$ ]]; then
        add_supported_ubuntu_ppa ppa:git-core/ppa || ADD_PPA_GIT="n"
    fi
    if [[ "$ADD_PPA_TOOLCHAIN" =~ ^[yY]$ ]]; then
        add_supported_ubuntu_ppa ppa:ubuntu-toolchain-r/test || ADD_PPA_TOOLCHAIN="n"
    fi

    # Update package lists after adding PPAs
    print_message "Updating package lists with new PPA repositories..."
    if apt-get update; then
        print_success "Package lists updated successfully"
        
        # Show added PPAs
        print_message "Added PPA repositories:"
        if [ "$ADD_PPA_PHP" = "y" ] || [ "$ADD_PPA_PHP" = "Y" ]; then
            print_message "  ✓ ppa:ondrej/php"
        fi
        if [ "$ADD_PPA_GIT" = "y" ] || [ "$ADD_PPA_GIT" = "Y" ]; then
            print_message "  ✓ ppa:git-core/ppa"
        fi
        if [ "$ADD_PPA_TOOLCHAIN" = "y" ] || [ "$ADD_PPA_TOOLCHAIN" = "Y" ]; then
            print_message "  ✓ ppa:ubuntu-toolchain-r/test"
        fi
    else
        print_warning "Failed to update package lists after adding PPAs"
    fi

    echo ""
fi

# ============================================
# REMOVE NGINX COMPLETELY (Debian & Ubuntu)
# ============================================

if { [ "$OS" = "debian" ] || [ "$OS" = "ubuntu" ]; } && \
   { [ "$REMOVE_NGINX" = "y" ] || [ "$REMOVE_NGINX" = "Y" ]; }; then
    print_message "Completely removing nginx (packages, modules, configs, binaries, deps, symlinks)..."

    # 1. Back up /etc/nginx first
    NGINX_RM_BK=""
    if [ -d /etc/nginx ]; then
        install -d -m 0700 -o root -g root /var/backups
        NGINX_RM_BK=$(mktemp -d "/var/backups/nginx-removal-$(date +%Y%m%d-%H%M%S).XXXXXX") || exit 1
        chmod 0700 "$NGINX_RM_BK"
        if tar czf "$NGINX_RM_BK/etc-nginx.tar.gz" -C / etc/nginx 2>/dev/null; then
            print_success "Backed up /etc/nginx to $NGINX_RM_BK/etc-nginx.tar.gz"
        else
            print_error "Could not back up /etc/nginx; refusing destructive changes"
            exit 1
        fi
        dpkg-query -W -f='${Package} ${Version} ${Status}\n' 'nginx*' 'libnginx-mod-*' 2>/dev/null \
            | awk '$3 == "install" && $4 == "ok" && $5 == "installed" {print $1, $2}' \
            > "$NGINX_RM_BK/packages.txt" || true
    fi

    # 2. Stop and disable the service
    if command -v systemctl >/dev/null 2>&1; then
        systemctl stop nginx 2>/dev/null || true
        systemctl disable nginx 2>/dev/null || true
    fi
    pkill -x nginx 2>/dev/null || true

    # 3. Purge all nginx packages and dynamic modules
    NGINX_RM_PKGS="$(dpkg-query -W -f='${Package} ${Status}\n' 'nginx*' 'libnginx-mod-*' 2>/dev/null \
        | awk '/ install ok installed$/{print $1}' | sort -u | tr '\n' ' ')"
    NGINX_RM_PKGS="$(echo "$NGINX_RM_PKGS" | xargs 2>/dev/null)"
    if [ -n "$NGINX_RM_PKGS" ]; then
        print_message "Purging packages: $NGINX_RM_PKGS"
        apt-get purge -y $NGINX_RM_PKGS || { print_error "nginx purge failed; leaving remaining files intact"; exit 1; }
    else
        print_message "No nginx packages registered with dpkg."
    fi

    # 4. Remove dependencies that are no longer required
    apt-get autoremove -y --purge || true

    # 5. Remove leftover files, dirs, orphan binaries and module symlinks
    rm -f /usr/sbin/nginx /usr/bin/nginx
    rm -rf /etc/nginx /usr/share/nginx /usr/lib/nginx /var/log/nginx /var/lib/nginx /run/nginx.pid
    rm -f /lib/systemd/system/nginx.service /usr/lib/systemd/system/nginx.service \
          /etc/systemd/system/nginx.service /etc/systemd/system/multi-user.target.wants/nginx.service
    rm -rf /etc/systemd/system/nginx.service.d

    # 6. Remove upstream repo definitions, pins and keys added by this script
    rm -f /etc/apt/sources.list.d/nginx.list \
          /etc/apt/sources.list.d/myguard-nginx.list \
          /etc/apt/sources.list.d/blendbyte.list
    rm -f /etc/apt/preferences.d/99nginx \
          /etc/apt/preferences.d/99myguard \
          /etc/apt/preferences.d/99blendbyte
    rm -f /usr/share/keyrings/nginx-archive-keyring.gpg \
          /etc/apt/keyrings/deb.myguard.nl.gpg \
          /etc/apt/keyrings/blendbyte.gpg

    # 7. Reload systemd, clear shell hash, verify
    command -v systemctl >/dev/null 2>&1 && systemctl daemon-reload 2>/dev/null || true
    hash -r 2>/dev/null || true
    if [ -e /usr/sbin/nginx ] || command -v nginx >/dev/null 2>&1; then
        print_warning "An nginx binary may still be present; inspect manually with: command -v nginx"
    else
        print_success "nginx fully removed."
    fi
    [ -n "$NGINX_RM_BK" ] && print_message "Config backup kept at: $NGINX_RM_BK"
    echo ""
fi

# ============================================
# ADD UPSTREAM NGINX REPOSITORIES (Debian & Ubuntu)
# ============================================

if { [ "$OS" = "debian" ] || [ "$OS" = "ubuntu" ]; } && \
   { [ "$ADD_NGINX_ORG" = "y" ] || [ "$ADD_NGINX_ORG" = "Y" ] || \
     [ "$ADD_NGINX_MYGUARD" = "y" ] || [ "$ADD_NGINX_MYGUARD" = "Y" ] || \
     [ "$ADD_NGINX_MODULES" = "y" ] || [ "$ADD_NGINX_MODULES" = "Y" ]; }; then
    print_message "Adding upstream Nginx repositories..."
    echo ""

    # Ensure prerequisites for fetching keys and resolving the distro codename
    NGINX_REPO_PREREQS=""
    command -v curl >/dev/null 2>&1 || NGINX_REPO_PREREQS="$NGINX_REPO_PREREQS curl"
    command -v gpg >/dev/null 2>&1  || NGINX_REPO_PREREQS="$NGINX_REPO_PREREQS gnupg2"
    command -v lsb_release >/dev/null 2>&1 || NGINX_REPO_PREREQS="$NGINX_REPO_PREREQS lsb-release"
    [ -e /etc/ssl/certs/ca-certificates.crt ] || NGINX_REPO_PREREQS="$NGINX_REPO_PREREQS ca-certificates"
    if [ -n "$NGINX_REPO_PREREQS" ]; then
        print_message "Installing prerequisites:$NGINX_REPO_PREREQS"
        apt-get install -y $NGINX_REPO_PREREQS || print_warning "Failed to install some prerequisites, continuing..."
    fi

    # Resolve the distribution codename (e.g. bookworm, jammy, noble) and architecture
    NGINX_CODENAME="$(lsb_release -cs 2>/dev/null)"
    if [ -z "$NGINX_CODENAME" ] && [ -r /etc/os-release ]; then
        NGINX_CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME:-$UBUNTU_CODENAME}")"
    fi
    NGINX_ARCH="$(dpkg --print-architecture 2>/dev/null || echo amd64)"

    if [ -z "$NGINX_CODENAME" ]; then
        print_warning "Could not determine distribution codename; skipping Nginx repositories"
    else
        # Validate suite availability before installing any source definition.
        for NGINX_SOURCE_FLAG in ADD_NGINX_ORG ADD_NGINX_MYGUARD ADD_NGINX_MODULES; do
            is_yes "${!NGINX_SOURCE_FLAG}" || continue
            case "$NGINX_SOURCE_FLAG" in
                ADD_NGINX_ORG) NGINX_RELEASE_URL="https://nginx.org/packages/$OS/dists/$NGINX_CODENAME/Release" ;;
                ADD_NGINX_MYGUARD) NGINX_RELEASE_URL="https://deb.myguard.nl/apt/nginx/$NGINX_CODENAME/dists/$NGINX_CODENAME/Release" ;;
                ADD_NGINX_MODULES) NGINX_RELEASE_URL="https://apt.blendbyte.net/nginx/dists/$NGINX_CODENAME/Release" ;;
            esac
            if ! repository_has_release "$NGINX_RELEASE_URL" "$NGINX_CODENAME"; then
                print_error "Nginx repository has no verified metadata for $NGINX_CODENAME: $NGINX_SOURCE_FLAG"
                printf -v "$NGINX_SOURCE_FLAG" '%s' n
            fi
        done

        # ---- Official nginx.org repository ----
        if [ "$ADD_NGINX_ORG" = "y" ] || [ "$ADD_NGINX_ORG" = "Y" ]; then
            print_message "Adding official nginx.org repository ($OS $NGINX_CODENAME)..."

            # Import the official nginx signing key into a dedicated keyring
            install -d -m 0755 /usr/share/keyrings
            NGINX_KEY_ASC=$(mktemp "${TMPDIR:-/tmp}/nginx-signing.XXXXXX")
            NGINX_KEYRING_TMP=$(mktemp "/usr/share/keyrings/nginx-archive-keyring.XXXXXX")
            if download_verified_url "https://nginx.org/keys/nginx_signing.key" "$NGINX_KEY_ASC" \
                    "55385da31d198fa6a5012d40ae98ecb272a6c4e8fffffba94719ffd3e87de37a" && \
               gpg --batch --yes --dearmor -o "$NGINX_KEYRING_TMP" "$NGINX_KEY_ASC" 2>/dev/null; then
                mv -f -- "$NGINX_KEYRING_TMP" /usr/share/keyrings/nginx-archive-keyring.gpg || { print_error "Cannot install nginx keyring"; exit 1; }
                chmod 0644 /usr/share/keyrings/nginx-archive-keyring.gpg

                # Stable repository source (path differs per OS: ubuntu vs debian)
                echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] https://nginx.org/packages/$OS $NGINX_CODENAME nginx" \
                    > /etc/apt/sources.list.d/nginx.list

                # Pin nginx.org so its packages are always preferred over the
                # distro's, preventing an accidental switch back to the distro
                # nginx on "apt update && apt upgrade".
                #   * Priority 900 > 500 (default distro): nginx.org always wins
                #     as the candidate regardless of the distro version number,
                #     so nginx is never silently replaced by the distro build.
                #   * Priority stays < 1000 on purpose: this forbids forced
                #     downgrades — apt will only ever move to a NEWER nginx.org
                #     version (security updates), never replace it with another.
                # Two separate stanzas are used (apt honours only the first
                # "Pin:" line within a single stanza) so the pin matches both by
                # site (origin nginx.org) and by signed Release metadata
                # (release o=nginx), surviving mirrors/redirects.
                cat > /etc/apt/preferences.d/99nginx <<'NGINX_PIN'
Package: *
Pin: origin nginx.org
Pin-Priority: 900

Package: *
Pin: release o=nginx
Pin-Priority: 900
NGINX_PIN

                print_success "Official nginx.org repository added"
            else
                # gpg --dearmor -o creates the target before reading stdin, so a
                # failed download can leave an empty keyring; remove it.
                ADD_NGINX_ORG="n"
                print_error "Failed to import nginx.org signing key, skipping official repository"
            fi
            rm -f -- "$NGINX_KEY_ASC" "$NGINX_KEYRING_TMP"
            echo ""
        fi

        # ---- Third-party deb.myguard.nl repository (nginx) ----
        if [ "$ADD_NGINX_MYGUARD" = "y" ] || [ "$ADD_NGINX_MYGUARD" = "Y" ]; then
            print_message "Adding third-party deb.myguard.nl Nginx repository ($NGINX_CODENAME, $NGINX_ARCH)..."

            install -d -m 0755 /etc/apt/keyrings

            # Import the deb.myguard.nl signing key into a dedicated keyring
            if download_verified_url "https://deb.myguard.nl/deb.myguard.nl.gpg" \
                /etc/apt/keyrings/deb.myguard.nl.gpg \
                "9744a10c48237234dcb762b5f7326ed21b6944a6f079cc3624169edf90118bdc"; then
                chmod 0644 /etc/apt/keyrings/deb.myguard.nl.gpg

                # Nginx-only repository source for this codename
                echo "deb [arch=$NGINX_ARCH signed-by=/etc/apt/keyrings/deb.myguard.nl.gpg] https://deb.myguard.nl/apt/nginx/$NGINX_CODENAME $NGINX_CODENAME main" \
                    > /etc/apt/sources.list.d/myguard-nginx.list

                # Pin deb.myguard.nl (matches the upstream myguard.deb pinning).
                # Priority 901 > 500 (distro) keeps nginx sourced from this repo
                # on every "apt update && apt upgrade"; staying < 1000 forbids
                # forced downgrades so the version is never silently replaced.
                # Only nginx is served from this source list, so "Package: *"
                # affects nginx alone.
                printf 'Package: *\nPin: origin deb.myguard.nl\nPin-Priority: 901\n' \
                    > /etc/apt/preferences.d/99myguard

                print_success "Third-party deb.myguard.nl Nginx repository added"
            else
                ADD_NGINX_MYGUARD="n"
                print_error "Failed to import deb.myguard.nl signing key, skipping third-party repository"
            fi
            echo ""
        fi

        # ---- nginx-modules.com (Blendbyte) dynamic modules repository ----
        if [ "$ADD_NGINX_MODULES" = "y" ] || [ "$ADD_NGINX_MODULES" = "Y" ]; then
            print_message "Adding nginx-modules.com (Blendbyte) repository ($NGINX_CODENAME)..."

            install -d -m 0755 /etc/apt/keyrings

            # Import the Blendbyte signing key into a dedicated keyring
            if download_verified_url "https://apt.blendbyte.net/nginx/blendbyte-archive-keyring.gpg" \
                /etc/apt/keyrings/blendbyte.gpg \
                "baf98d0706d8e7df82230b6bdbd763dd2ffadf0aa41fa017158cf1217f46cd87"; then
                chmod 0644 /etc/apt/keyrings/blendbyte.gpg

                # Modules repository source for this codename
                echo "deb [arch=$NGINX_ARCH signed-by=/etc/apt/keyrings/blendbyte.gpg] https://apt.blendbyte.net/nginx $NGINX_CODENAME main" \
                    > /etc/apt/sources.list.d/blendbyte.list

                # Pin Blendbyte so its nginx-module-* packages are preferred and
                # stay sourced from this repo on upgrades. Same safe range as the
                # other Nginx repos: > 500 beats the distro, < 1000 forbids
                # forced downgrades. Two stanzas match by site and by signed
                # Release metadata (Origin: Blendbyte).
                cat > /etc/apt/preferences.d/99blendbyte <<'BLENDBYTE_PIN'
Package: *
Pin: origin apt.blendbyte.net
Pin-Priority: 900

Package: *
Pin: release o=Blendbyte
Pin-Priority: 900
BLENDBYTE_PIN

                print_success "nginx-modules.com (Blendbyte) repository added"
            else
                ADD_NGINX_MODULES="n"
                print_error "Failed to import Blendbyte signing key, skipping modules repository"
            fi
            echo ""
        fi

        # Refresh package lists with the new repositories
        print_message "Updating package lists with new Nginx repositories..."
        if apt-get update; then
            print_success "Package lists updated successfully"
            print_message "Added Nginx repositories:"
            if [ "$ADD_NGINX_ORG" = "y" ] || [ "$ADD_NGINX_ORG" = "Y" ]; then
                print_message "  ✓ nginx.org (official, https://nginx.org/packages/$OS)"
            fi
            if [ "$ADD_NGINX_MYGUARD" = "y" ] || [ "$ADD_NGINX_MYGUARD" = "Y" ]; then
                print_message "  ✓ deb.myguard.nl (third-party nginx)"
            fi
            if [ "$ADD_NGINX_MODULES" = "y" ] || [ "$ADD_NGINX_MODULES" = "Y" ]; then
                print_message "  ✓ nginx-modules.com (Blendbyte modules)"
            fi

            # Verify the pinning: show which repository nginx now resolves to.
            # The "Candidate" line must point at nginx.org / deb.myguard.nl
            # (priority 900/901), confirming apt upgrade will not switch nginx
            # back to the distro version.
            if command -v apt-cache >/dev/null 2>&1; then
                print_message "Verifying nginx package source (apt-cache policy nginx):"
                apt-cache policy nginx 2>/dev/null || print_warning "Could not query nginx policy"
            fi
        else
            print_warning "Failed to update package lists after adding Nginx repositories"
        fi
        echo ""
    fi
fi

# ============================================
# INSTALL NGINX (with selectable module set)
# ============================================

if { [ "$OS" = "debian" ] || [ "$OS" = "ubuntu" ]; } && \
   { [ "$INSTALL_NGINX" = "y" ] || [ "$INSTALL_NGINX" = "Y" ]; }; then

    # Dynamic-module package sets, kept in sync with each repository's catalogue
    NGINX_ORG_MODULES="nginx-module-njs nginx-module-geoip nginx-module-image-filter nginx-module-xslt nginx-module-perl nginx-module-otel nginx-module-acme"
    BLENDBYTE_MODULES="nginx-module-brotli nginx-module-brotli-static nginx-module-cache-purge nginx-module-dav-ext nginx-module-fancyindex nginx-module-geoip2 nginx-module-headers-more nginx-module-modsecurity nginx-module-stream-geoip2 nginx-module-substitutions nginx-module-zstd nginx-module-zstd-static"
    # Lean myguard module set (Debian-style libnginx-mod-* names) — equivalent to
    # the distro nginx-full subset commonly used (e.g. by x-ui-pro), without the
    # ~110-module zoo that exceeds nginx's module limit.
    MYGUARD_CURATED_MODULES="libnginx-mod-stream libnginx-mod-stream-geoip2 libnginx-mod-http-upstream-fair libnginx-mod-http-subs-filter libnginx-mod-http-geoip2 libnginx-mod-http-echo libnginx-mod-http-dav-ext libnginx-mod-http-auth-pam"

    NGINX_PKGS=""
    NGINX_VARIANT_OK="y"

    case "$NGINX_INSTALL_VARIANT" in
        1)  # nginx.org: nginx only
            if [ "$ADD_NGINX_ORG" = "y" ] || [ "$ADD_NGINX_ORG" = "Y" ]; then
                NGINX_PKGS="nginx"
            else
                NGINX_VARIANT_OK="n"
            fi
            ;;
        2)  # nginx.org: nginx + official dynamic modules
            if [ "$ADD_NGINX_ORG" = "y" ] || [ "$ADD_NGINX_ORG" = "Y" ]; then
                NGINX_PKGS="nginx $NGINX_ORG_MODULES"
            else
                NGINX_VARIANT_OK="n"
            fi
            ;;
        3)  # nginx.org + ALL Blendbyte modules
            if { [ "$ADD_NGINX_ORG" = "y" ] || [ "$ADD_NGINX_ORG" = "Y" ]; } && \
               { [ "$ADD_NGINX_MODULES" = "y" ] || [ "$ADD_NGINX_MODULES" = "Y" ]; }; then
                NGINX_PKGS="nginx $BLENDBYTE_MODULES"
            else
                NGINX_VARIANT_OK="n"
            fi
            ;;
        4)  # nginx.org: EVERYTHING (nginx + official modules + all Blendbyte modules)
            if { [ "$ADD_NGINX_ORG" = "y" ] || [ "$ADD_NGINX_ORG" = "Y" ]; } && \
               { [ "$ADD_NGINX_MODULES" = "y" ] || [ "$ADD_NGINX_MODULES" = "Y" ]; }; then
                NGINX_PKGS="nginx $NGINX_ORG_MODULES $BLENDBYTE_MODULES"
            else
                NGINX_VARIANT_OK="n"
            fi
            ;;
        5)  # deb.myguard.nl: nginx-full
            if [ "$ADD_NGINX_MYGUARD" = "y" ] || [ "$ADD_NGINX_MYGUARD" = "Y" ]; then
                NGINX_PKGS="nginx-full"
            else
                NGINX_VARIANT_OK="n"
            fi
            ;;
        6)  # deb.myguard.nl: nginx-extras (maximal module set)
            if [ "$ADD_NGINX_MYGUARD" = "y" ] || [ "$ADD_NGINX_MYGUARD" = "Y" ]; then
                NGINX_PKGS="nginx-extras"
            else
                NGINX_VARIANT_OK="n"
            fi
            ;;
        7)  # custom: only the packages the user listed
            NGINX_PKGS=""
            ;;
        8)  # deb.myguard.nl: nginx + curated lean module set
            if [ "$ADD_NGINX_MYGUARD" = "y" ] || [ "$ADD_NGINX_MYGUARD" = "Y" ]; then
                NGINX_PKGS="nginx nginx-common $MYGUARD_CURATED_MODULES"
            else
                NGINX_VARIANT_OK="n"
            fi
            ;;
        *)
            NGINX_VARIANT_OK="n"
            ;;
    esac

    # Always honour any extra packages the user specified
    if [ -n "$NGINX_CUSTOM_PKGS" ]; then
        NGINX_PKGS="$NGINX_PKGS $NGINX_CUSTOM_PKGS"
    fi

    NGINX_PKGS=${NGINX_PKGS//,/ }
    read -r -a NGINX_PACKAGE_ARRAY <<< "$NGINX_PKGS"
    for NGINX_PACKAGE in "${NGINX_PACKAGE_ARRAY[@]}"; do
        if ! [[ "$NGINX_PACKAGE" =~ ^[a-z0-9][a-z0-9.+-]*(:[a-z0-9-]+)?(=[a-zA-Z0-9.+:~_-]+)?$ ]]; then
            print_error "Invalid nginx package name: $NGINX_PACKAGE"
            NGINX_VARIANT_OK="n"
        fi
    done
    NGINX_PKGS="${NGINX_PACKAGE_ARRAY[*]}"

    if [ "$NGINX_VARIANT_OK" != "y" ]; then
        print_warning "Selected nginx preset '$NGINX_INSTALL_VARIANT' requires a repository that was not enabled; skipping nginx installation."
    elif [ -z "$NGINX_PKGS" ]; then
        print_warning "No nginx packages resolved for the chosen preset; skipping nginx installation."
    else
        if { [ "$ADD_NGINX_ORG" = "y" ] || [ "$ADD_NGINX_ORG" = "Y" ]; } && \
           { [ "$ADD_NGINX_MYGUARD" = "y" ] || [ "$ADD_NGINX_MYGUARD" = "Y" ]; }; then
            print_warning "Both nginx.org and deb.myguard.nl are enabled: the 'nginx' package resolves to deb.myguard.nl (pin 901)."
        fi

        # Detect a pre-existing nginx (typically installed from the distro repos).
        NGINX_PREEXISTING="n"
        if dpkg-query -W -f='${Status}' nginx 2>/dev/null | grep -q "install ok installed"; then
            NGINX_PREEXISTING="y"
        fi

        NGINX_DO_INSTALL="y"
        NGINX_BK=""
        if [ "$NGINX_PREEXISTING" = "y" ] && \
           [ "$MIGRATE_NGINX" != "y" ] && [ "$MIGRATE_NGINX" != "Y" ]; then
            NGINX_DO_INSTALL="n"
            print_warning "Existing nginx detected but migration was not confirmed; skipping nginx installation to avoid breaking it."
        fi

        # Resolve the complete target transaction before stopping or removing a
        # working nginx installation. Apt uses the already-downloaded package
        # indexes, so this catches missing modules/version skew without downtime.
        if [ "$NGINX_DO_INSTALL" = "y" ] && ! apt-get install -s $NGINX_PKGS >/dev/null 2>&1; then
            print_error "Dependency resolution failed for the selected nginx package set; existing nginx was left untouched"
            apt-get install -s $NGINX_PKGS 2>&1 | tail -n 15
            NGINX_DO_INSTALL="n"
        fi

        if [ "$NGINX_DO_INSTALL" = "y" ]; then
            # ---- Safe migration from an existing (distro) nginx ----
            if [ "$NGINX_PREEXISTING" = "y" ]; then
                install -d -m 0700 -o root -g root /var/backups
                NGINX_BK=$(mktemp -d "/var/backups/nginx-migration-$(date +%Y%m%d-%H%M%S).XXXXXX") || exit 1
                chmod 0700 "$NGINX_BK"
                print_message "Backing up current nginx setup to $NGINX_BK ..."
                if [ -d /etc/nginx ]; then
                    if tar czf "$NGINX_BK/etc-nginx.tar.gz" -C / etc/nginx 2>/dev/null; then
                        print_success "Saved $NGINX_BK/etc-nginx.tar.gz"
                    else
                        print_error "Could not back up /etc/nginx; refusing destructive changes"
            exit 1
                    fi
                fi
                dpkg-query -W -f='${Package} ${Version} ${Status}\n' 'nginx*' 'libnginx-mod-*' 2>/dev/null \
                    | awk '$3 == "install" && $4 == "ok" && $5 == "installed" {print $1, $2}' \
                    > "$NGINX_BK/packages.txt" || true
                [ -s "$NGINX_BK/packages.txt" ] || { print_error "Cannot save nginx package inventory; migration cancelled"; exit 1; }
                nginx -v 2> "$NGINX_BK/nginx-version.txt" || true

                # Stop the running service before swapping packages
                if command -v systemctl >/dev/null 2>&1; then
                    systemctl stop nginx 2>/dev/null || true
                fi

                # Presets 1-4 target nginx.org, whose 'nginx' Conflicts/Replaces the
                # distro nginx-common/nginx-core and uses a different layout (no
                # modules-enabled). Remove the distro stack for a clean switch.
                # myguard (5/6) is Debian-style and upgrades in place via the pin.
                case "$NGINX_INSTALL_VARIANT" in
                    1|2|3|4)
                        DISTRO_NGINX_PKGS="$(dpkg-query -W -f='${Package} ${Status}\n' 'nginx*' 'libnginx-mod-*' 2>/dev/null \
                            | awk '/ install ok installed$/{print $1}' | sort -u | tr '\n' ' ')"
                        DISTRO_NGINX_PKGS="$(echo "$DISTRO_NGINX_PKGS" | xargs 2>/dev/null)"
                        if [ -n "$DISTRO_NGINX_PKGS" ]; then
                            print_message "Removing distro nginx packages for the nginx.org switch: $DISTRO_NGINX_PKGS"
                            apt-get remove -y $DISTRO_NGINX_PKGS || print_warning "Some distro nginx packages could not be removed"
                        fi
                        # Distro modules-enabled/*.conf load .so files that no longer
                        # exist after removal; move them aside so nginx.org can start.
                        if [ -d /etc/nginx/modules-enabled ] && ls /etc/nginx/modules-enabled/*.conf >/dev/null 2>&1; then
                            mkdir -p "$NGINX_BK/modules-enabled"
                            mv /etc/nginx/modules-enabled/*.conf "$NGINX_BK/modules-enabled/" 2>/dev/null || true
                            print_message "Moved distro modules-enabled/*.conf to backup (nginx.org loads modules via nginx.conf)."
                        fi
                        ;;
                    5|6)
                        # myguard uses Debian-style package names, so the upgrade is
                        # in place (no removal). myguard's nginx pulls NEW libs
                        # (libssl-nginx, libz-ng2), so a plain "apt upgrade" would
                        # hold it back; an explicit install handles that. Add every
                        # currently installed nginx package to the set so they all
                        # move to the myguard version together and no distro module
                        # is left orphaned against the new ABI.
                        MG_INSTALLED="$(dpkg-query -W -f='${Package} ${Status}\n' 'nginx*' 'libnginx-mod-*' 2>/dev/null \
                            | awk '/ install ok installed$/{print $1}' | sort -u | tr '\n' ' ')"
                        MG_INSTALLED="$(echo "$MG_INSTALLED" | xargs 2>/dev/null)"
                        if [ -n "$MG_INSTALLED" ]; then
                            print_message "Upgrading existing nginx packages in place to deb.myguard.nl: $MG_INSTALLED"
                            NGINX_PKGS="$(echo "$NGINX_PKGS $MG_INSTALLED" | tr ',' ' ' | xargs 2>/dev/null)"
                        fi
                        ;;
                    8)
                        # Lean myguard preset: keep ONLY the curated module set.
                        # Remove the distro nginx stack first so the distro
                        # nginx-full metapackage (and its module zoo) is gone and
                        # is not dragged back in; the curated myguard packages are
                        # then installed fresh. modules-enabled is left in place
                        # (myguard is Debian-style and re-creates the needed links).
                        DISTRO_NGINX_PKGS="$(dpkg-query -W -f='${Package} ${Status}\n' 'nginx*' 'libnginx-mod-*' 2>/dev/null \
                            | awk '/ install ok installed$/{print $1}' | sort -u | tr '\n' ' ')"
                        DISTRO_NGINX_PKGS="$(echo "$DISTRO_NGINX_PKGS" | xargs 2>/dev/null)"
                        if [ -n "$DISTRO_NGINX_PKGS" ]; then
                            print_message "Removing existing nginx packages for the lean myguard install: $DISTRO_NGINX_PKGS"
                            apt-get remove -y $DISTRO_NGINX_PKGS || print_warning "Some nginx packages could not be removed"
                        fi
                        ;;
                esac
            fi

            print_message "Installing nginx packages: $NGINX_PKGS"

            # On IPv6-disabled hosts the nginx package ships "listen [::]:80/443"
            # in its default site; nginx fails to bind it and the postinst aborts
            # the install. Block service autostart during apt so the install
            # completes, then strip those directives before the config test.
            NGINX_IPV6_GUARD="n"
            if nginx_ipv6_is_disabled; then
                print_message "IPv6 is disabled on this host; guarding nginx install against listen [::] failures."
                if nginx_block_service_autostart; then
                    NGINX_IPV6_GUARD="y"
                else
                    print_error "Could not safely install the temporary policy-rc.d guard"
                    exit 1
                fi
            fi

            # Keep existing conffiles on a conflict (preserves the migrated config);
            # confdef/confold make the install non-interactive and predictable.
            if apt-get install -y \
                    -o Dpkg::Options::=--force-confold \
                    -o Dpkg::Options::=--force-confdef \
                    $NGINX_PKGS; then
                print_success "nginx installed successfully"
                echo ""

                # IPv6-disabled host: remove the [::] listen directives the
                # package shipped so the upcoming "nginx -t" and service start
                # do not fail (mirrors the manual "edit config + re-run" fix).
                if [ "$NGINX_IPV6_GUARD" = "y" ]; then
                    nginx_strip_ipv6_listen
                fi
                if command -v nginx >/dev/null 2>&1; then
                    print_message "Installed nginx version:"
                    nginx -v 2>&1 || true
                fi
                if command -v apt-cache >/dev/null 2>&1; then
                    print_message "nginx package source after install (apt-cache policy nginx):"
                    apt-cache policy nginx 2>/dev/null || true
                fi

                # myguard ships base modules (NDK, stream, mail) as SEPARATE
                # dynamic modules that many others link against, but numbers every
                # conf "50-". Since modules-enabled/*.conf load in alphabetical
                # order, a dependent like 50-mod-http-array-var.conf or
                # 50-mod-http-keyval.conf can sort before 50-mod-http-ndk.conf /
                # 50-mod-stream.conf and fail with "undefined symbol"
                # (ndk_set_var_value, ngx_stream_add_variable, ...). Force the base
                # modules to load first via low numeric prefixes (00-,01-,02-).
                if [ -d /etc/nginx/modules-enabled ]; then
                    _bm_i=0
                    for _bm in mod-http-ndk mod-stream mod-mail; do
                        for _cur in /etc/nginx/modules-enabled/*"$_bm".conf; do
                            [ -e "$_cur" ] || continue
                            _bm_tgt="$(readlink -f "$_cur" 2>/dev/null)"
                            [ -n "$_bm_tgt" ] || _bm_tgt="/usr/share/nginx/modules-available/$_bm.conf"
                            rm -f "$_cur"
                            ln -sf "$_bm_tgt" "/etc/nginx/modules-enabled/0${_bm_i}-${_bm}.conf"
                            print_message "Reordered base module $_bm to load early (0${_bm_i}-${_bm}.conf)."
                        done
                        _bm_i=$((_bm_i + 1))
                    done
                fi

                # myguard's large module set occasionally enables a module conf
                # whose .so is not actually present (or named differently),
                # causing nginx -t to fail with "cannot open shared object file".
                # Disable any modules-enabled conf whose referenced .so is missing.
                if [ -d /etc/nginx/modules-enabled ]; then
                    for _mc in /etc/nginx/modules-enabled/*.conf; do
                        [ -e "$_mc" ] || continue
                        _so="$(sed -n 's/.*load_module[[:space:]]\+modules\/\([^;]*\.so\);.*/\1/p' "$_mc" 2>/dev/null | head -1)"
                        if [ -n "$_so" ] && [ ! -e "/usr/share/nginx/modules/$_so" ] && [ ! -e "/usr/lib/nginx/modules/$_so" ]; then
                            print_warning "Disabling $(basename "$_mc"): module file $_so not found."
                            rm -f "$_mc"
                        fi
                    done
                fi

                # Validate config before (re)starting so a broken migration does
                # not take the service down.
                NGINX_RUNTIME_OK=false
                if command -v nginx >/dev/null 2>&1 && nginx -t 2>&1; then
                    print_success "nginx configuration test passed"
                    if command -v systemctl >/dev/null 2>&1; then
                        systemctl enable nginx 2>/dev/null && systemctl restart nginx 2>/dev/null || true
                        if systemctl is-active --quiet nginx; then
                            print_success "nginx is running"
                            NGINX_RUNTIME_OK=true
                        else
                            print_error "nginx is not active after migration"
                        fi
                    else
                        NGINX_RUNTIME_OK=true
                    fi
                else
                    print_error "nginx -t reported a problem; the migrated service was not started"
                fi

                if [ "$NGINX_RUNTIME_OK" != true ] && [ -n "$NGINX_BK" ]; then
                    if nginx_restore_migration "$NGINX_BK"; then
                        print_warning "Previous nginx packages and configuration were restored after runtime validation failed"
                    else
                        print_error "Automatic nginx rollback failed; recovery files are in: $NGINX_BK"
                    fi
                fi

                if [ -n "$NGINX_BK" ]; then
                    print_message "Migration backup kept at: $NGINX_BK"
                    print_warning "Old site configs are preserved in /etc/nginx; new package configs (if any) were saved as *.dpkg-dist."
                fi
                if [ "$NGINX_RUNTIME_OK" = true ]; then
                    print_warning "Dynamic modules are installed but NOT auto-enabled."
                    print_warning "Add the matching 'load_module .../modules/<name>.so;' lines to the top of /etc/nginx/nginx.conf,"
                    print_warning "then run 'nginx -t && systemctl reload nginx'. Installed *.so live under /etc/nginx/modules/ or /usr/lib/nginx/modules/."
                fi
            else
                # On an IPv6-disabled host a leftover [::] listen can still leave
                # the install half-configured; strip it and finish the install.
                if [ "$NGINX_IPV6_GUARD" = "y" ]; then
                    nginx_strip_ipv6_listen
                    if dpkg --configure -a 2>/dev/null && apt-get install -y -f; then
                        print_success "nginx install completed after removing IPv6 listen directives"
                        if nginx -t 2>&1 && systemctl enable nginx 2>/dev/null && systemctl restart nginx 2>/dev/null; then
                            print_success "nginx configuration verified and service started"
                        else
                            print_error "nginx recovery install completed but validation or service start failed"
                        fi
                    else
                        print_error "Failed to install one or more nginx packages: $NGINX_PKGS"
                        if [ -n "$NGINX_BK" ]; then
                            if nginx_restore_migration "$NGINX_BK"; then
                                print_warning "Previous nginx packages and configuration were restored"
                            else
                                print_error "Automatic nginx rollback failed; recovery files are in: $NGINX_BK"
                            fi
                        fi
                    fi
                else
                    print_error "Failed to install one or more nginx packages: $NGINX_PKGS"
                    if [ -n "$NGINX_BK" ]; then
                        if nginx_restore_migration "$NGINX_BK"; then
                            print_warning "Previous nginx packages and configuration were restored"
                        else
                            print_error "Automatic nginx rollback failed; recovery files are in: $NGINX_BK"
                        fi
                    fi
                fi
            fi

            # Always re-enable service autostart after the nginx package install.
            if [ "$NGINX_IPV6_GUARD" = "y" ]; then
                nginx_unblock_service_autostart
            fi
        fi
        echo ""
    fi
fi

# ============================================
# INSTALL PHP PACKAGES
# ============================================

if [ "$OS" = "ubuntu" ] && { [ "$ADD_PPA_PHP" = "y" ] || [ "$ADD_PPA_PHP" = "Y" ]; }; then
    if [ "$INSTALL_PHP_CLI" = "y" ] || [ "$INSTALL_PHP_CLI" = "Y" ]; then
        print_message "Installing PHP CLI..."
        apt-get install -y php-cli || print_warning "Failed to install php-cli"
        echo ""

        if [ "$INSTALL_PHP_EXTENSIONS" = "y" ] || [ "$INSTALL_PHP_EXTENSIONS" = "Y" ]; then
            # Use version-neutral metapackages (php-mbstring, etc.) instead of
            # pinning to php8.4-*. The metapackages pull in extensions for the
            # default PHP version of the running distro (e.g. 8.5 on Ubuntu 26.04).
            print_message "Installing PHP extensions (mbstring, xml, curl, mysql)..."
            apt-get install -y php-mbstring php-xml php-curl php-mysql || print_warning "Failed to install PHP extensions"
            echo ""
        fi
    fi
fi

# ============================================
# INSTALL MIDNIGHT COMMANDER
# ============================================

if [ "$OS" = "debian" ] || [ "$OS" = "ubuntu" ]; then
    print_message "Installing Midnight Commander from standard repositories..."
    apt-get install -y mc || print_warning "Failed to install mc"
    echo ""
fi

# ============================================
# INSTALL AND CONFIGURE ZSH FOR USER
# ============================================

if ( [ "$INSTALL_ZSH" = "y" ] || [ "$INSTALL_ZSH" = "Y" ] ) && [ ! -z "$NEW_USERNAME" ]; then
    print_message "Installing Oh My Zsh for $NEW_USERNAME"
    
    USER_HOME=$(getent passwd "$NEW_USERNAME" | cut -d: -f6)
    
    ZSH_CONFIG_OK=true
    USER_GROUP=$(id -gn "$NEW_USERNAME")
    OH_MY_ZSH_OK=false
    OH_MY_ZSH_COMMIT="830a5bcfd29fd577fdcd5f3b8e98cbaf973421fa"
    # Install Oh My Zsh as user
    print_message "Installing Oh My Zsh..."
    if [ -d "$USER_HOME/.oh-my-zsh" ]; then
        print_message "Oh My Zsh already installed, reusing existing directory"
    else
        OH_MY_ZSH_INSTALLER_TMP=$(mktemp)
        OH_MY_ZSH_SHA256="5b16896b831243ebd2f409ecd99c3d231385cc706fbc564625057929ebee5e6e"
        if download_verified_url "https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/${OH_MY_ZSH_COMMIT}/tools/install.sh" "$OH_MY_ZSH_INSTALLER_TMP" "$OH_MY_ZSH_SHA256"; then
            chmod 755 "$OH_MY_ZSH_INSTALLER_TMP"
	    if ! sudo -u "$NEW_USERNAME" -i bash << EOF
	        export HOME="$USER_HOME"
	        export RUNZSH=no
	        export CHSH=no
	        cd "\$HOME"
	        sh "$OH_MY_ZSH_INSTALLER_TMP" --unattended
EOF
	    then
	        print_error "Pinned Oh My Zsh installer failed"
	    fi
            rm -f "$OH_MY_ZSH_INSTALLER_TMP"
        else
            rm -f "$OH_MY_ZSH_INSTALLER_TMP"
            print_warning "Failed to download Oh My Zsh installer"
        fi
    fi
    
    # The upstream installer fetches only the branch tip (--depth=1). Fetch
    # the pinned object explicitly, including when repairing an earlier run.
    if [ -d "$USER_HOME/.oh-my-zsh/.git" ]; then
        if pin_user_git_checkout "$NEW_USERNAME" "$USER_HOME/.oh-my-zsh" "$OH_MY_ZSH_COMMIT"; then
            OH_MY_ZSH_OK=true
        else
            print_error "Failed to pin Oh My Zsh checkout to $OH_MY_ZSH_COMMIT"
        fi
    fi

    if [ "$OH_MY_ZSH_OK" = true ]; then
        print_message "Oh My Zsh installed successfully"
        
        # Install zsh plugins
        print_message "Installing zsh plugins..."
        
        if ! sudo -u "$NEW_USERNAME" -i bash << EOF
            export HOME="$USER_HOME"
            cd "\$HOME"
            ZSH_PLUGIN_DIR="\${ZSH_CUSTOM:-\$HOME/.oh-my-zsh/custom}/plugins"
            mkdir -p "\$ZSH_PLUGIN_DIR"
            install_plugin() {
                local url="\$1" directory="\$2" commit="\$3"
                if [ ! -d "\$directory/.git" ]; then
                    git clone --no-checkout "\$url" "\$directory" || return 1
                fi
                git -C "\$directory" fetch --depth=1 origin "\$commit" &&
                    git -C "\$directory" checkout --detach "\$commit"
            }
            install_plugin https://github.com/zsh-users/zsh-syntax-highlighting.git \
                "\$ZSH_PLUGIN_DIR/zsh-syntax-highlighting" 2fc57d63067c18b1100ecdbf684fa5baf49459d1 || exit 1
            install_plugin https://github.com/zsh-users/zsh-autosuggestions.git \
                "\$ZSH_PLUGIN_DIR/zsh-autosuggestions" 85919cd1ffa7d2d5412f6d3fe437ebdbeeec4fc5 || exit 1
            install_plugin https://github.com/zsh-users/zsh-history-substring-search.git \
                "\$ZSH_PLUGIN_DIR/zsh-history-substring-search" 14c8d2e0ffaee98f2df9850b19944f32546fdea5 || exit 1
EOF
        then
            ZSH_CONFIG_OK=false
            print_error "Pinned zsh plugin installation failed"
        else
            print_message "Zsh plugins installed successfully"
        fi
        
        # Download custom .zshrc
        print_message "Downloading custom .zshrc configuration..."
        if install_verified_repo_asset "config/.zshrc" "$USER_HOME/.zshrc" "b5b20444bd9c87f06acb18e56e5cc96d86b40974fcaa3a85dd3ea692c348a654" 0644; then
            print_message "Custom .zshrc verified and installed"
            chown "$NEW_USERNAME:$USER_GROUP" "$USER_HOME/.zshrc" || ZSH_CONFIG_OK=false
            chmod 644 "$USER_HOME/.zshrc"
        else
            ZSH_CONFIG_OK=false
            print_error "Failed to install custom .zshrc"
        fi

        # Download custom .zshenv (sets PATH for non-interactive shells too —
        # .zshrc returns early for those, so ~/.local/bin must come from here)
        print_message "Downloading custom .zshenv configuration..."
        if install_verified_repo_asset "config/.zshenv" "$USER_HOME/.zshenv" "720c0cf32bfda634c8b9ba66012d19a9129048cd4520981c431b6423595cfcfd" 0644; then
            print_message "Custom .zshenv verified and installed"
            chown "$NEW_USERNAME:$USER_GROUP" "$USER_HOME/.zshenv" || ZSH_CONFIG_OK=false
        else
            ZSH_CONFIG_OK=false
            print_error "Failed to install custom .zshenv"
        fi

        # Change default shell to zsh
        print_message "Changing default shell to zsh for $NEW_USERNAME"
        if chsh -s "$(command -v zsh)" "$NEW_USERNAME"; then
            print_message "Default shell changed to zsh"
        else
            ZSH_CONFIG_OK=false
            print_error "Failed to change default shell to zsh"
        fi
    else
        print_error "Oh My Zsh installation failed"
    fi
    echo ""
fi

# ============================================
# CONFIGURE SSH
# ============================================

# Configure SSH
if [ "$CONFIGURE_SSH" = "y" ] || [ "$CONFIGURE_SSH" = "Y" ]; then
    print_message "Configuring SSH..."

    SSHD_CONFIG="/etc/ssh/sshd_config"
    SSHD_CONFIG_DIR="/etc/ssh/sshd_config.d"
    SSHD_DROPIN="${SSHD_CONFIG_DIR}/10-system-setup.conf"
    SSHD_CONFIG_BACKUP=""
    SSHD_DROPIN_BACKUP=""
    SSHD_LEGACY_DROPIN="${SSHD_CONFIG_DIR}/99-system-setup.conf"
    SSHD_LEGACY_BACKUP=""
    ORIGINAL_SSH_PORT=$(sshd -T 2>/dev/null | awk '$1 == "port" { print $2; exit }')
    ORIGINAL_SSH_PORT=${ORIGINAL_SSH_PORT:-22}

    # Backup original sshd_config
    if [ -f "$SSHD_CONFIG" ]; then
        SSHD_CONFIG_BACKUP="/etc/ssh/sshd_config.backup.$(date +%Y%m%d-%H%M%S)~"
        cp -p "$SSHD_CONFIG" "$SSHD_CONFIG_BACKUP" || { print_error "Cannot back up sshd_config"; exit 1; }
        print_message "Original sshd_config backed up"
    else
        print_error "sshd_config not found: $SSHD_CONFIG"
        print_error "Skipping SSH configuration to avoid writing an incomplete config"
        CONFIGURE_SSH="n"
    fi

    if [ "$CONFIGURE_SSH" = "y" ] || [ "$CONFIGURE_SSH" = "Y" ]; then
        mkdir -p "$SSHD_CONFIG_DIR"

        if [ -e "$SSHD_DROPIN" ] || [ -L "$SSHD_DROPIN" ]; then
            SSHD_DROPIN_BACKUP="${SSHD_DROPIN}.backup.$(date +%Y%m%d-%H%M%S)~"
            cp -a -- "$SSHD_DROPIN" "$SSHD_DROPIN_BACKUP" || { print_error "Cannot back up SSH drop-in"; exit 1; }
        fi

        # Migrate only our old managed file. It sorts after cloud-init and
        # leaves stale accumulating directives if kept alongside the new file.
        if [ -f "$SSHD_LEGACY_DROPIN" ] && grep -Fxq '# Managed by system-setup.sh' "$SSHD_LEGACY_DROPIN"; then
            SSHD_LEGACY_BACKUP="${SSHD_LEGACY_DROPIN}.backup.$(date +%Y%m%d-%H%M%S)~"
            if ! mv -- "$SSHD_LEGACY_DROPIN" "$SSHD_LEGACY_BACKUP"; then
                SSHD_LEGACY_BACKUP=""
                print_error "Failed to back up legacy SSH drop-in"
                CONFIGURE_SSH="failed"
            fi
        fi

        if ! ensure_sshd_include_first "$SSHD_CONFIG" || ! remove_sshd_accumulating_parameters "$SSHD_CONFIG"; then
            print_error "Failed to enable sshd drop-in processing"
            CONFIGURE_SSH="failed"
        fi

        # Build drop-in content in a buffer, then write atomically at the end.
        # This avoids a window where the file exists but is only partially written.
        SSHD_DROPIN_CONTENT="# Managed by system-setup.sh
# WARNING: This file is regenerated on every run; manual edits will be lost.
# To customize sshd beyond what this script manages, create another drop-in
# whose name sorts BEFORE this one (e.g. /etc/ssh/sshd_config.d/01-local.conf).
"

        # Helper: append a parameter to the in-memory drop-in content.
        append_ssh_parameter() {
            local param_name="$1"
            local param_value="$2"
            SSHD_DROPIN_CONTENT+="$(printf '%s %s\n' "$param_name" "$param_value")"$'\n'
            print_message "SSH parameter set: ${param_name} ${param_value}"
        }

        # Change SSH port
        if [ -n "$SSH_PORT" ]; then
            # Ubuntu 24.04+ reads this Port via sshd-socket-generator when
            # systemctl daemon-reload runs. restart_ssh_listener verifies that
            # ssh.socket or ssh.service is actually listening afterward.
            append_ssh_parameter "Port" "$SSH_PORT"
        fi

        # Configure PubkeyAuthentication
        if [ ! -z "$SSH_PUBKEY_AUTH" ]; then
            append_ssh_parameter "PubkeyAuthentication" "$SSH_PUBKEY_AUTH"
        fi

        # Configure PasswordAuthentication
        if [ ! -z "$SSH_PASSWORD_AUTH" ]; then
            append_ssh_parameter "PasswordAuthentication" "$SSH_PASSWORD_AUTH"
        fi

        # Configure PermitEmptyPasswords (ALWAYS no for security)
        if [ ! -z "$SSH_EMPTY_PASSWORDS" ]; then
            append_ssh_parameter "PermitEmptyPasswords" "$SSH_EMPTY_PASSWORDS"
            print_warning "PermitEmptyPasswords set to 'no' for security reasons"
        fi

        # Configure PermitRootLogin
        if [ ! -z "$SSH_ROOT_LOGIN" ]; then
            append_ssh_parameter "PermitRootLogin" "$SSH_ROOT_LOGIN"
        fi

        # Configure PrintMotd
        if [ ! -z "$SSH_PRINT_MOTD" ]; then
            append_ssh_parameter "PrintMotd" "$SSH_PRINT_MOTD"
        fi

        # Add AllowUsers if specified
        if [ ! -z "$SSH_ALLOW_USERS" ]; then
            append_ssh_parameter "AllowUsers" "$SSH_ALLOW_USERS"
            print_message "AllowUsers set to: $SSH_ALLOW_USERS"
        fi

        # Atomically install the drop-in.
        if [ "$CONFIGURE_SSH" != "failed" ] && \
           ! printf '%s' "$SSHD_DROPIN_CONTENT" | write_file_atomic "$SSHD_DROPIN" 0644 root:root; then
            print_error "Failed to install managed SSH drop-in"
            CONFIGURE_SSH="failed"
        fi

        # Warn if an earlier-loaded drop-in (e.g. 00-yubikey-fido2.conf) sets
        # any of the same parameters: sshd uses "first value wins", so the
        # earlier file silently overrides ours.
        if [ "$CONFIGURE_SSH" != "failed" ]; then
            warn_sshd_dropin_conflicts "$SSHD_DROPIN"
        fi

        # Test SSH configuration
        print_message "Testing SSH configuration..."
        if [ "$CONFIGURE_SSH" != "failed" ] && sshd -t && verify_sshd_parameters "$SSHD_DROPIN"; then
            print_message "SSH configuration is valid"

            # Restart the listener and verify the selected port. On Ubuntu
            # 24.04/26.04, ssh.socket may be the unit that owns the port.
            print_message "Restarting SSH listener..."
            if ! restart_ssh_listener "$SSH_PORT"; then
                print_error "New SSH listener failed verification; rolling back SSH configuration"
                if [ -n "$SSHD_DROPIN_BACKUP" ]; then
                    rm -f -- "$SSHD_DROPIN"
                    cp -a -- "$SSHD_DROPIN_BACKUP" "$SSHD_DROPIN"
                else
                    rm -f -- "$SSHD_DROPIN"
                fi
                [ -n "$SSHD_CONFIG_BACKUP" ] && cp -- "$SSHD_CONFIG_BACKUP" "$SSHD_CONFIG"
                [ -n "$SSHD_LEGACY_BACKUP" ] && cp -a -- "$SSHD_LEGACY_BACKUP" "$SSHD_LEGACY_DROPIN"
                restore_ssh_activation_state
                if sshd -t && restart_ssh_listener "$ORIGINAL_SSH_PORT"; then
                    print_warning "SSH configuration rolled back; listener restored on port $ORIGINAL_SSH_PORT"
                else
                    print_error "CRITICAL: SSH rollback failed; keep the current session open and use console access"
                fi
                SSH_PORT="$ORIGINAL_SSH_PORT"
                CONFIGURE_SSH="failed"
            fi
        else
            print_error "SSH configuration test failed!"
            print_error "Removing managed drop-in and restoring sshd_config backup..."
            rm -f -- "$SSHD_DROPIN"
            if [ -n "$SSHD_DROPIN_BACKUP" ]; then
                cp -a -- "$SSHD_DROPIN_BACKUP" "$SSHD_DROPIN"
            fi
            if [ -n "$SSHD_CONFIG_BACKUP" ]; then
                cp "$SSHD_CONFIG_BACKUP" "$SSHD_CONFIG"
                print_error "SSH configuration restored from backup"
            else
                print_error "No backup found to restore"
            fi
            [ -n "$SSHD_LEGACY_BACKUP" ] && cp -a -- "$SSHD_LEGACY_BACKUP" "$SSHD_LEGACY_DROPIN"
            restore_ssh_activation_state
            SSH_PORT="$ORIGINAL_SSH_PORT"
            CONFIGURE_SSH="failed"
        fi
    fi
else
    print_message "Skipping SSH configuration (not requested)"
fi

# ============================================
# CONFIGURE UFW
# ============================================

# Configure UFW
if { [ "$CONFIGURE_UFW" = "y" ] || [ "$CONFIGURE_UFW" = "Y" ]; } && command -v ufw >/dev/null 2>&1; then
    print_message "Configuring UFW firewall..."
    UFW_CONFIG_OK=true
    
    UFW_SSH_PORTS=$(sshd -T 2>/dev/null | awk '$1 == "port" {print $2}')
    UFW_SSH_PORTS=${UFW_SSH_PORTS:-$SSH_PORT}
    for UFW_SSH_PORT in $UFW_SSH_PORTS; do
        ufw allow "${UFW_SSH_PORT}/tcp" comment 'SSH' || UFW_CONFIG_OK=false
    done
    if [ "$UFW_CONFIG_OK" != true ]; then
        print_error "Could not allow the SSH listener in UFW; refusing to change firewall policies"
        exit 1
    fi

    # Set default policies
    print_message "Setting UFW default policies..."
    ufw --force default deny incoming || UFW_CONFIG_OK=false
    ufw --force default allow outgoing || UFW_CONFIG_OK=false
    ufw --force default deny routed || UFW_CONFIG_OK=false
    print_message "UFW default policies configured"
    
    # Allow SSH (use configured port)
    ufw allow "${SSH_PORT}"/tcp comment 'SSH' || UFW_CONFIG_OK=false
    print_message "UFW rule added: Allow SSH (port ${SSH_PORT})"
    
    # Add custom ports if specified
    if [ ! -z "$CUSTOM_PORTS" ]; then
        print_message "Configuring custom ports: $CUSTOM_PORTS"
        
        # Split ports by comma
        IFS=',' read -ra PORT_ARRAY <<< "$CUSTOM_PORTS"
        
        for PORT_SPEC in "${PORT_ARRAY[@]}"; do
            # Trim whitespace
            PORT_SPEC=$(echo "$PORT_SPEC" | xargs)
            
            # Check if protocol is specified
            if [[ "$PORT_SPEC" =~ ^([0-9]+)/(tcp|udp)$ ]]; then
                # Port with protocol: 8080/tcp or 53/udp
                PORT="${BASH_REMATCH[1]}"
                PROTOCOL="${BASH_REMATCH[2]}"
                
                if [ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ]; then
                    ufw allow "${PORT}"/"${PROTOCOL}" comment "Custom ${PROTOCOL} port" || UFW_CONFIG_OK=false
                    print_message "UFW rule added: Allow port ${PORT}/${PROTOCOL}"
                else
                    print_warning "Invalid port number: $PORT (must be 1-65535). Skipping."
                fi
            elif [[ "$PORT_SPEC" =~ ^[0-9]+$ ]]; then
                # Port without protocol - default to tcp
                PORT="$PORT_SPEC"
                
                if [ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ]; then
                    ufw allow "${PORT}"/tcp comment "Custom tcp port" || UFW_CONFIG_OK=false
                    print_message "UFW rule added: Allow port ${PORT}/tcp (default)"
                else
                    print_warning "Invalid port number: $PORT (must be 1-65535). Skipping."
                fi
            else
                print_warning "Invalid port format: $PORT_SPEC. Expected: PORT or PORT/PROTOCOL. Skipping."
            fi
        done
        
        print_message "Custom ports configuration completed"
    fi
    
    # Enable UFW
    print_message "Enabling UFW..."
    if [ "$UFW_CONFIG_OK" = true ]; then
        ufw --force enable || UFW_CONFIG_OK=false
    fi
    ufw status verbose || UFW_CONFIG_OK=false
    if [ "$UFW_CONFIG_OK" != true ]; then
        print_error "UFW configuration failed; firewall state must be reviewed manually"
    fi
else
    if [ "$CONFIGURE_UFW" = "y" ] || [ "$CONFIGURE_UFW" = "Y" ]; then
        print_error "UFW was selected but the ufw command is unavailable"
        CONFIGURE_UFW="failed"
    else
        print_message "Skipping UFW configuration (not requested)"
    fi
fi

# Configure ICMP blocking in UFW
if [ "$BLOCK_ICMP" = "y" ] || [ "$BLOCK_ICMP" = "Y" ]; then
    print_message "Configuring ICMP blocking in UFW..."
    
    UFW_BEFORE_RULES="/etc/ufw/before.rules"
    
    # Check if ICMP blocking is already configured
    if grep -q "icmp-type echo-request -j DROP" "$UFW_BEFORE_RULES"; then
        print_warning "ICMP blocking is already configured in before.rules"
        print_message "Skipping ICMP configuration to avoid duplicates"
    else
        # Backup original before.rules
        if [ -f "$UFW_BEFORE_RULES" ]; then
            # Save original permissions (numeric format for chmod)
            ORIGINAL_PERMS=$(stat -c "%a" "$UFW_BEFORE_RULES" 2>/dev/null || \
                            stat -f "%A" "$UFW_BEFORE_RULES" 2>/dev/null | tail -c 4)
            
            cp "$UFW_BEFORE_RULES" "/etc/ufw/before.rules.backup.$(date +%Y%m%d-%H%M%S)~"
            print_message "Original before.rules backed up"
        fi
        
        # Check if the ICMP section exists
        if grep -q "# ok icmp codes for INPUT" "$UFW_BEFORE_RULES"; then
            print_message "Found ICMP section in before.rules"
            
            # Create a temporary file for modifications
            TEMP_FILE=$(mktemp)
            
            # Process the file and replace ICMP rules
            awk '
            /# ok icmp codes for INPUT/ {
                print "# ok icmp codes for INPUT"
                print "-A ufw-before-input -p icmp --icmp-type destination-unreachable -j ACCEPT"
                print "-A ufw-before-input -p icmp --icmp-type source-quench -j ACCEPT"
                print "-A ufw-before-input -p icmp --icmp-type time-exceeded -j ACCEPT"
                print "-A ufw-before-input -p icmp --icmp-type parameter-problem -j ACCEPT"
                print "-A ufw-before-input -p icmp --icmp-type echo-request -j DROP"
                
                # Skip all lines that start with -A ufw-before-input -p icmp
                while (getline > 0) {
                    if ($0 !~ /^-A ufw-before-input -p icmp/) {
                        print
                        break
                    }
                }
                next
            }
            { print }
            ' "$UFW_BEFORE_RULES" > "$TEMP_FILE"
            
            # Verify the temporary file is not empty
            if [ -s "$TEMP_FILE" ]; then
                # Replace original file
                mv "$TEMP_FILE" "$UFW_BEFORE_RULES"
                
                # Restore original permissions
                if [ ! -z "$ORIGINAL_PERMS" ]; then
                    chmod "$ORIGINAL_PERMS" "$UFW_BEFORE_RULES"
                    print_message "Restored original file permissions: $ORIGINAL_PERMS"
                else
                    # Set default permissions if we couldn't detect them
                    chmod 640 "$UFW_BEFORE_RULES"
                    print_message "Set default file permissions: 640"
                fi
                
                print_message "ICMP blocking configured successfully"
                
                # Reload UFW to apply changes
                print_message "Reloading UFW to apply ICMP blocking..."
                if ufw reload; then
                    print_message "UFW reloaded"
                else
                    print_error "UFW reload failed after ICMP configuration"
                    UFW_CONFIG_OK=false
                fi
            else
                print_error "Failed to modify before.rules (temporary file is empty)"
                rm -f "$TEMP_FILE"
            fi
        else
            print_warning "ICMP section not found in before.rules"
            print_warning "Skipping ICMP blocking configuration"
        fi
        
        print_message "ICMP (ping) requests are now blocked"
        print_message "Your server will not respond to ping"
    fi
else
    if [ "$CONFIGURE_UFW" = "y" ] || [ "$CONFIGURE_UFW" = "Y" ]; then
        print_message "ICMP blocking not requested - server will respond to ping"
    fi
fi

# ============================================
# INSTALL DOCKER
# ============================================

install_docker_from_official_repository() {
    local docker_tmp_dir docker_key_tmp docker_key_sha docker_repo_os
    local docker_codename docker_arch docker_sources
    local expected_key_sha="1500c1f56fa9e26b9b8f42452a553675796ade0807cdce11975eb98170b3a570"

    case "$OS" in
        debian|ubuntu) docker_repo_os="$OS" ;;
        *) print_error "Docker repository is unsupported on OS: $OS"; return 1 ;;
    esac
    docker_codename="${VERSION_CODENAME:-}"
    docker_arch=$(dpkg --print-architecture)
    [ -n "$docker_codename" ] || { print_error "Docker repository codename is empty"; return 1; }

    apt-get install -y ca-certificates curl gnupg || return 1
    create_temp_dir "docker-repository" || return 1
    docker_tmp_dir="$SYSTEM_SETUP_CREATED_TEMP_DIR"
    docker_key_tmp="${docker_tmp_dir}/docker.asc"
    docker_sources="/etc/apt/sources.list.d/docker.sources"

    if ! download_url_ipv4 "https://download.docker.com/linux/${docker_repo_os}/gpg" "$docker_key_tmp"; then
        print_error "Failed to download the Docker repository signing key"
        return 1
    fi
    docker_key_sha=$(sha256sum "$docker_key_tmp" | awk '{print $1}')
    if [ "$docker_key_sha" != "$expected_key_sha" ]; then
        print_error "Docker signing key SHA256 mismatch"
        return 1
    fi

    if ! repository_has_release "https://download.docker.com/linux/${docker_repo_os}/dists/${docker_codename}/Release" "$docker_codename"; then
        print_error "Docker repository does not provide verified metadata for $docker_codename"
        return 1
    fi
    install -d -m 0755 /etc/apt/keyrings || return 1
    install -m 0644 -o root -g root "$docker_key_tmp" /etc/apt/keyrings/docker.asc || return 1
    write_file_atomic "$docker_sources" 0644 root:root <<EOF
Types: deb
URIs: https://download.docker.com/linux/${docker_repo_os}
Suites: ${docker_codename}
Components: stable
Architectures: ${docker_arch}
Signed-By: /etc/apt/keyrings/docker.asc
EOF
    [ "$?" -eq 0 ] || return 1

    if ! apt-get update; then
        print_error "Docker repository metadata update failed"
        return 1
    fi
    if ! apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
        print_error "Docker package installation failed"
        return 1
    fi

    print_message "Docker installed from its signed official APT repository"
    return 0
}

# Install Docker if requested
if [ "$INSTALL_DOCKER" = "y" ] || [ "$INSTALL_DOCKER" = "Y" ]; then
    print_message "Installing Docker..."
    echo ""
    
    # Check if Docker is already installed
    if command -v docker &> /dev/null; then
        DOCKER_VERSION=$(docker --version 2>/dev/null || echo "unknown")
        print_warning "Docker is already installed: $DOCKER_VERSION"
        prompt_read -r -p "Do you want to reinstall Docker? (y/N): " REINSTALL_DOCKER
        REINSTALL_DOCKER=${REINSTALL_DOCKER:-n}
        
        if [ "$REINSTALL_DOCKER" != "y" ] && [ "$REINSTALL_DOCKER" != "Y" ]; then
            print_message "Skipping Docker installation"
            DOCKER_INSTALLED="yes"
        else
            print_message "Reinstalling Docker..."
            if install_docker_from_official_repository; then
                DOCKER_INSTALLED="yes"
            else
                DOCKER_INSTALLED="no"
            fi
        fi
    else
        print_message "Installing Docker from the official signed APT repository..."
        if install_docker_from_official_repository; then
            DOCKER_INSTALLED="yes"
            
            # Start and enable Docker
            if ! systemctl enable --now docker; then
                print_error "Docker packages installed but daemon failed to start"
            fi
            
            # Ensure docker group exists
            if ! getent group docker > /dev/null 2>&1; then
                print_message "Creating docker group..."
                groupadd docker
            fi
            
            # Add new user to docker group if created
            if [ ! -z "$NEW_USERNAME" ]; then
                usermod -aG docker "$NEW_USERNAME"
                print_message "User $NEW_USERNAME added to docker group"
                
                # Note about newgrp
                print_message "To activate docker group without logout, user can run: newgrp docker"
            fi
            
            # Add current user to docker group if not root
            if [ ! -z "$SUDO_USER" ] && [ "$SUDO_USER" != "$NEW_USERNAME" ]; then
                usermod -aG docker "$SUDO_USER"
                print_message "User $SUDO_USER added to docker group"
            fi
            
            if [ ! -z "$NEW_USERNAME" ] || [ ! -z "$SUDO_USER" ]; then
                print_warning "Users need to log out and log back in (or run 'newgrp docker') for docker group to take effect"
            fi
        else
            DOCKER_INSTALLED="no"
        fi
    fi
    
    # Create daemon.json to disable Docker iptables management
    if [ "$DOCKER_INSTALLED" = "yes" ]; then
        if [ "$DOCKER_DISABLE_IPTABLES" = "y" ] || [ "$DOCKER_DISABLE_IPTABLES" = "Y" ]; then
            print_message "Configuring Docker daemon: disabling iptables management..."
            mkdir -p /etc/docker

            DAEMON_JSON="/etc/docker/daemon.json"
            DAEMON_JSON_BACKUP=""
            if [ -f "$DAEMON_JSON" ]; then
                # Backup existing daemon.json
                DAEMON_JSON_BACKUP="${DAEMON_JSON}.backup.$(date +%Y%m%d-%H%M%S)~"
                cp -- "$DAEMON_JSON" "$DAEMON_JSON_BACKUP"
                chmod 0600 "$DAEMON_JSON_BACKUP"
                print_message "Existing daemon.json backed up to $DAEMON_JSON_BACKUP"

                # Merge only after successfully parsing the administrator's
                # existing JSON. Never replace an invalid or unfamiliar config
                # with a minimal file: that could silently discard daemon settings.
                if command -v python3 &>/dev/null; then
                    DAEMON_JSON_TMP=""
                    if DAEMON_JSON_TMP=$(mktemp "${DAEMON_JSON}.tmp.XXXXXX"); then
                        chmod 0600 "$DAEMON_JSON_TMP"
                    else
                        print_error "Could not create a temporary Docker configuration"
                        DOCKER_DISABLE_IPTABLES="n"
                    fi
                    if [ -n "$DAEMON_JSON_TMP" ] && python3 - "$DAEMON_JSON" "$DAEMON_JSON_TMP" <<'PYEOF'
import json
import sys

source, destination = sys.argv[1:]
with open(source, encoding="utf-8") as stream:
    config = json.load(stream)
if not isinstance(config, dict):
    raise ValueError("top-level Docker configuration must be a JSON object")
config["iptables"] = False
config["ip6tables"] = False
config["userland-proxy"] = False
with open(destination, "w", encoding="utf-8") as stream:
    json.dump(config, stream, indent=2)
    stream.write("\n")
PYEOF
                    then
                        chown root:root "$DAEMON_JSON_TMP"
                        mv -f -- "$DAEMON_JSON_TMP" "$DAEMON_JSON"
                        print_message "daemon.json updated (merged with existing config)"
                    else
                        rm -f -- "$DAEMON_JSON_TMP"
                        print_error "Existing daemon.json is not valid JSON; it was left unchanged"
                        DOCKER_DISABLE_IPTABLES="n"
                    fi
                else
                    print_error "python3 is required to safely merge the existing daemon.json; it was left unchanged"
                    DOCKER_DISABLE_IPTABLES="n"
                fi
            else
                # No existing daemon.json — create new
                if write_file_atomic "$DAEMON_JSON" 0600 root:root <<'DEOF'
{
  "iptables": false,
  "ip6tables": false,
  "userland-proxy": false
}
DEOF
                then
                    print_message "daemon.json created"
                else
                    DOCKER_DISABLE_IPTABLES="n"
                fi
            fi

            # Restart Docker only when the requested configuration was applied.
            if { [ "$DOCKER_DISABLE_IPTABLES" = "y" ] || [ "$DOCKER_DISABLE_IPTABLES" = "Y" ]; } && \
               systemctl is-active --quiet docker 2>/dev/null; then
                print_message "Restarting Docker to apply daemon.json..."
                if systemctl restart docker && sleep 2 && systemctl is-active --quiet docker 2>/dev/null; then
                    print_success "Docker restarted with iptables disabled"
                else
                    DOCKER_DISABLE_IPTABLES="failed"
                    print_error "Docker failed to restart with the updated daemon.json"
                    if [ -n "${DAEMON_JSON_BACKUP:-}" ] && [ -f "$DAEMON_JSON_BACKUP" ]; then
                        cp -- "$DAEMON_JSON_BACKUP" "$DAEMON_JSON"
                        systemctl restart docker 2>/dev/null || true
                        print_warning "Previous daemon.json restored"
                    else
                        rm -f -- "$DAEMON_JSON"
                        systemctl restart docker 2>/dev/null || true
                        print_warning "New daemon.json removed and previous Docker defaults restored"
                    fi
                fi
            fi
        fi
    fi

    # Verify Docker installation
    if [ "$DOCKER_INSTALLED" = "yes" ]; then
        if docker --version &> /dev/null; then
            print_message "Docker version: $(docker --version)"
            if docker compose version &> /dev/null; then
                print_message "Docker Compose version: $(docker compose version)"
            fi
        fi

        # Start RustDesk containers if the service was previously enabled
        # RustDesk section runs BEFORE Docker installation, so the service
        # is enabled but containers couldn't start without Docker.
        # Now that Docker is installed and running, start the RustDesk service.
        if systemctl is-enabled --quiet rustdesk-compose.service 2>/dev/null; then
            echo ""
            print_message "RustDesk service detected, starting containers..."
            if systemctl start rustdesk-compose.service; then
                sleep 3
                if systemctl is-active --quiet rustdesk-compose.service; then
                    print_success "RustDesk containers started successfully"
                else
                    print_warning "RustDesk service started but may still be pulling images"
                    print_message "Check status: systemctl status rustdesk-compose.service"
                fi
            else
                print_warning "Failed to start RustDesk service"
                print_message "Try manually: systemctl start rustdesk-compose.service"
            fi
        fi
    fi

    echo ""
else
    print_message "Skipping Docker installation (not requested)"
    DOCKER_INSTALLED="no"
fi

# Install ufw-docker (independent of Docker installation)
if [ "$INSTALL_UFW_DOCKER" = "y" ] || [ "$INSTALL_UFW_DOCKER" = "Y" ]; then
    print_message "Installing ufw-docker..."
    UFW_DOCKER_COMMIT="020a8699f95592561f254d8d4ad1bb40d401dfc7"
    UFW_DOCKER_SHA256="643e56b080567c567b4aa28650196849b2a2da5dd0473fd3e5216b0886035ab0"
    if create_temp_dir "ufw-docker"; then
        UFW_DOCKER_TMP="${SYSTEM_SETUP_CREATED_TEMP_DIR}/ufw-docker"
    else
        UFW_DOCKER_TMP=""
    fi
    UFW_DOCKER_URL="https://raw.githubusercontent.com/chaifeng/ufw-docker/${UFW_DOCKER_COMMIT}/ufw-docker"

    if [ -n "$UFW_DOCKER_TMP" ] && download_url_ipv4 "$UFW_DOCKER_URL" "$UFW_DOCKER_TMP" && \
       [ "$(sha256sum "$UFW_DOCKER_TMP" | awk '{print $1}')" = "$UFW_DOCKER_SHA256" ]; then
        install -m 0755 -o root -g root "$UFW_DOCKER_TMP" /usr/local/bin/ufw-docker || {
            print_error "Failed to install verified ufw-docker binary"
            exit 1
        }
        print_message "Pinned ufw-docker verified and installed"
        
        # Run ufw-docker install
        print_message "Configuring ufw-docker..."
        if /usr/local/bin/ufw-docker install; then
            UFW_DOCKER_OK=true
            print_message "ufw-docker configured successfully"
        else
            print_error "ufw-docker configuration failed"
        fi
        
        if ! command -v docker &> /dev/null; then
            print_warning "Note: Docker is not installed. ufw-docker will be ready when you install Docker."
        fi
    else
        print_error "Failed to download or verify pinned ufw-docker"
    fi
else
    print_message "Skipping ufw-docker installation (not requested)"
fi

# ============================================
# INSTALL GO LANGUAGE
# ============================================

if [ "$INSTALL_GO" = "y" ] || [ "$INSTALL_GO" = "Y" ]; then
    if [ -z "$NEW_USERNAME" ]; then
        print_warning "Cannot install Go: No user was created"
        print_warning "Go installation requires a non-root user"
    else
        print_message "Installing latest version of Go for user $NEW_USERNAME..."
        echo ""
        
        USER_HOME=$(getent passwd "$NEW_USERNAME" | cut -d: -f6)
        
        ARCH=$(uname -m)
        case "$ARCH" in
            x86_64) GO_ARCH="amd64" ;;
            aarch64|arm64) GO_ARCH="arm64" ;;
            armv6l) GO_ARCH="armv6l" ;;
            i386|i686) GO_ARCH="386" ;;
            *)
                print_error "Unsupported Go architecture: $ARCH"
                GO_ARCH=""
                ;;
        esac

        if [ -n "$GO_ARCH" ]; then
            print_message "Fetching latest stable Go release and checksum..."
            GO_METADATA_TMP=$(mktemp)
            if download_url_ipv4 "https://go.dev/dl/?mode=json" "$GO_METADATA_TMP" &&
               GO_RELEASE=$(select_go_archive "$GO_METADATA_TMP" "$GO_ARCH"); then
                read -r LATEST_GO_VERSION GO_ARCHIVE GO_EXPECTED_SHA256 <<< "$GO_RELEASE"
                print_message "Latest Go version: $LATEST_GO_VERSION"
            else
                print_error "Could not fetch verified Go release metadata"
                GO_ARCH=""
            fi
            rm -f -- "$GO_METADATA_TMP"
        fi

        if [ -z "$GO_ARCH" ]; then
            # Skip Go installation for unsupported architectures
            :
        else
            print_message "Detected architecture: $ARCH (Go architecture: $GO_ARCH)"

            # Download Go
            GO_URL="https://go.dev/dl/${GO_ARCHIVE}"
            if create_temp_dir "go-install"; then
                GO_TMP_DIR="$SYSTEM_SETUP_CREATED_TEMP_DIR"
            else
                GO_TMP_DIR=""
            fi
            GO_ARCHIVE_PATH="${GO_TMP_DIR}/${GO_ARCHIVE}"
            GO_STAGE_DIR="${GO_TMP_DIR}/stage"
            GO_INSTALL_OK=false

            print_message "Downloading Go from: $GO_URL"
            if [ -n "$GO_TMP_DIR" ] && \
               download_url_ipv4 "$GO_URL" "$GO_ARCHIVE_PATH" 900; then
                GO_ACTUAL_SHA256=$(sha256sum "$GO_ARCHIVE_PATH" | awk '{print $1}')
                if ! [[ "$GO_EXPECTED_SHA256" =~ ^[0-9a-fA-F]{64}$ ]] || \
                   [ "$GO_EXPECTED_SHA256" != "$GO_ACTUAL_SHA256" ]; then
                    print_error "Go archive SHA256 verification failed (expected $GO_EXPECTED_SHA256, got $GO_ACTUAL_SHA256)"
                else
                    print_success "Go archive SHA256 verified"
                    mkdir -p "$GO_STAGE_DIR"
                    if tar -C "$GO_STAGE_DIR" -xzf "$GO_ARCHIVE_PATH" && \
                       [ -x "$GO_STAGE_DIR/go/bin/go" ] && \
                        "$GO_STAGE_DIR/go/bin/go" version >/dev/null 2>&1; then
                        GO_OLD_DIR=""
                        GO_CAN_ACTIVATE=true
                        if [ -d /usr/local/go ]; then
                            if GO_OLD_DIR=$(mktemp -d "/usr/local/go.backup.$(date +%Y%m%d-%H%M%S).XXXXXX~"); then
                                rmdir "$GO_OLD_DIR"
                            else
                                print_error "Could not reserve a backup path for the previous Go installation"
                                GO_CAN_ACTIVATE=false
                            fi
                            if [ "$GO_CAN_ACTIVATE" = true ] && ! mv /usr/local/go "$GO_OLD_DIR"; then
                                print_error "Could not move the previous Go installation; activation cancelled"
                                GO_OLD_DIR=""
                                GO_CAN_ACTIVATE=false
                            fi
                        fi
                        if [ "$GO_CAN_ACTIVATE" = true ] && \
                           mv "$GO_STAGE_DIR/go" /usr/local/go && \
                           /usr/local/go/bin/go version >/dev/null 2>&1; then
                            GO_INSTALL_OK=true
                            [ -n "$GO_OLD_DIR" ] && rm -rf -- "$GO_OLD_DIR"
                            print_success "Go staged, verified, and installed atomically"
                        elif [ "$GO_CAN_ACTIVATE" = true ]; then
                            rm -rf -- /usr/local/go
                            if [ -n "$GO_OLD_DIR" ] && [ -d "$GO_OLD_DIR" ]; then
                                mv "$GO_OLD_DIR" /usr/local/go
                                print_warning "Previous Go installation restored"
                            fi
                            print_error "Go activation failed"
                        fi
                    else
                        print_error "Go staging extraction or binary verification failed"
                    fi
                fi

                # Add Go to PATH for the user
                if [ "$GO_INSTALL_OK" = true ]; then
                    print_message "Configuring Go environment for $NEW_USERNAME..."

                # Determine which shell config file to use
                if [ -f "$USER_HOME/.zshrc" ]; then
                    SHELL_RC="$USER_HOME/.zshrc"
                elif [ -f "$USER_HOME/.bashrc" ]; then
                    SHELL_RC="$USER_HOME/.bashrc"
                else
                    SHELL_RC="$USER_HOME/.profile"
                fi

                # Add Go to PATH if not already present
                if ! grep -q "export PATH=.*:/usr/local/go/bin" "$SHELL_RC" 2>/dev/null; then
                    if sudo -u "$NEW_USERNAME" tee -a "$SHELL_RC" >/dev/null <<'GOENV'

# Go language
export PATH="$PATH:/usr/local/go/bin:$HOME/go/bin"
GOENV
                    then
                        print_message "Go PATH added to $SHELL_RC"
                    else
                        print_error "Failed to configure Go PATH for $NEW_USERNAME"
                    fi
                else
                    print_message "Go PATH already configured in $SHELL_RC"
                fi

                # Verify installation
                if /usr/local/go/bin/go version &> /dev/null; then
                    GO_INSTALLED_VERSION=$(/usr/local/go/bin/go version)
                    print_message "Go installed successfully: $GO_INSTALLED_VERSION"
                    print_message "Go binary location: /usr/local/go/bin/go"
                    print_message "User $NEW_USERNAME can use Go after reloading shell or running: source $SHELL_RC"
                else
                    print_error "Go installation verification failed"
                fi
                fi
            else
                print_error "Failed to download Go archive"
            fi
        fi

        echo ""
    fi
else
    print_message "Skipping Go installation (not requested)"
fi

# ============================================
# INSTALL IPSET
# ============================================

if [ "$INSTALL_IPSET" = "y" ] || [ "$INSTALL_IPSET" = "Y" ]; then
    print_message "Installing ipset from the signed distribution repository..."
    if apt-get install -y ipset && command -v ipset >/dev/null 2>&1; then
        IPSET_INSTALLED_VERSION=$(ipset --version 2>&1 | head -1 || echo "unknown")
        print_success "ipset installed: $IPSET_INSTALLED_VERSION"
    else
        print_error "Failed to install ipset from the distribution repository"
    fi
    echo ""
else
    print_message "Skipping ipset installation (not requested)"
fi

# ============================================
# INSTALL RCLONE
# ============================================

if [ "$INSTALL_RCLONE" = "y" ] || [ "$INSTALL_RCLONE" = "Y" ]; then
    print_message "Installing rclone..."
    echo ""

    if command -v rclone &>/dev/null; then
        RCLONE_CURRENT=$(rclone version 2>/dev/null | head -1 || echo "unknown")
        print_warning "rclone is already installed: $RCLONE_CURRENT"
        print_message "The distribution package manager will update it when available"
    fi

    # Use the signed distribution repository instead of executing a mutable
    # remote installer as root.
    if apt-get install -y rclone && command -v rclone >/dev/null 2>&1; then
        RCLONE_VERSION=$(rclone version 2>/dev/null | head -1 || echo "unknown")
        print_success "rclone installed from the distribution repository: $RCLONE_VERSION"
    else
        print_error "Failed to install rclone from the distribution repository"
    fi

    echo ""
else
    print_message "Skipping rclone installation (not requested)"
fi

# ============================================
# CREATE PYTHON VIRTUAL ENVIRONMENT
# ============================================

# Create Python virtual environment
if [ "$CREATE_VENV" = "y" ] || [ "$CREATE_VENV" = "Y" ]; then
    print_message "Creating Python virtual environment..."
    
    # Create directory if it doesn't exist
    VENV_DIR=$(dirname "$VENV_PATH")
    if [ ! -d "$VENV_DIR" ]; then
        mkdir -p "$VENV_DIR"
        print_message "Created directory: $VENV_DIR"
    fi
    
    # Create virtual environment
    print_message "Creating venv at: $VENV_PATH"
    if python3 -m venv "$VENV_PATH"; then
        print_message "Virtual environment created successfully"
        
        # Activate virtual environment and install packages
        print_message "Installing Python packages..."
        VENV_CREATED_OK=true

        # Upgrade pip first without letting pip failures stop the whole setup.
        set +e
        PIP_TIMEOUT_BIN=""
        if command -v timeout &>/dev/null; then
            PIP_TIMEOUT_BIN="timeout"
        fi

        PIP_COMMON_ARGS=(
            --disable-pip-version-check
            --no-input
            --timeout 15
            --retries 2
            --prefer-binary
        )

        if [ -n "$PIP_TIMEOUT_BIN" ]; then
            PIP_NO_INPUT=1 PIP_DEFAULT_TIMEOUT=15 "$PIP_TIMEOUT_BIN" 180 "$VENV_PATH/bin/python" -m pip install "${PIP_COMMON_ARGS[@]}" --upgrade pip
            PIP_UPGRADE_EXIT_CODE=$?
        else
            PIP_NO_INPUT=1 PIP_DEFAULT_TIMEOUT=15 "$VENV_PATH/bin/python" -m pip install "${PIP_COMMON_ARGS[@]}" --upgrade pip
            PIP_UPGRADE_EXIT_CODE=$?
        fi

        if [ "$PIP_UPGRADE_EXIT_CODE" -ne 0 ]; then
            print_warning "pip upgrade failed or timed out (exit code: $PIP_UPGRADE_EXIT_CODE); continuing with package install"
        fi

        # Install packages
        PIP_PACKAGES=(
            requests
            psutil
            pytz
            uvloop
            python-telegram-bot
            nest_asyncio
            aiohttp
            charset-normalizer
            maxminddb
            geoipsets
            setuptools
            wheel
            pip
            passlib
            bcrypt
            tqdm
            colorama
            humanize
            termcolor
            rich
            "python-telegram-bot[job-queue]"
            urllib3
            chardet
        )

        if [ -n "$PIP_TIMEOUT_BIN" ]; then
            PIP_NO_INPUT=1 PIP_DEFAULT_TIMEOUT=15 "$PIP_TIMEOUT_BIN" 600 "$VENV_PATH/bin/python" -m pip install "${PIP_COMMON_ARGS[@]}" --upgrade "${PIP_PACKAGES[@]}"
            PIP_EXIT_CODE=$?
        else
            PIP_NO_INPUT=1 PIP_DEFAULT_TIMEOUT=15 "$VENV_PATH/bin/python" -m pip install "${PIP_COMMON_ARGS[@]}" --upgrade "${PIP_PACKAGES[@]}"
            PIP_EXIT_CODE=$?
        fi
        set +e

        if [ $PIP_EXIT_CODE -eq 0 ]; then
            VENV_PACKAGES_OK=true
            print_message "Python packages installed successfully"
        elif [ $PIP_EXIT_CODE -eq 124 ]; then
            print_error "Python package installation timed out"
        else
            print_error "Some Python packages may have failed to install (exit code: $PIP_EXIT_CODE)"
        fi
        print_message "Virtual environment location: $VENV_PATH"
        print_message "To activate: source $VENV_PATH/bin/activate"

    else
        print_error "Failed to create virtual environment"
    fi
else
    print_message "Skipping Python virtual environment creation (not requested)"
fi

# ============================================
# CONFIGURE CRONTAB
# ============================================

if [ "$CONFIGURE_CRONTAB" = "y" ] || [ "$CONFIGURE_CRONTAB" = "Y" ]; then
    print_message "Configuring crontab for root..."

    create_temp_dir "crontab" || {
        print_error "Failed to create temporary directory for crontab"
        CONFIGURE_CRONTAB="n"
    }
    CRONTAB_TMP_DIR="${SYSTEM_SETUP_CREATED_TEMP_DIR:-}"

    if [ "$CONFIGURE_CRONTAB" = "y" ] || [ "$CONFIGURE_CRONTAB" = "Y" ]; then
    # Backup existing crontab
    EXISTING_CRONTAB_FILE="${CRONTAB_TMP_DIR}/existing-crontab"
    if crontab -l &>/dev/null; then
        CRONTAB_BACKUP=$(mktemp "${TMPDIR:-/tmp}/crontab.backup.$(date +%Y%m%d-%H%M%S).XXXXXX")
        crontab -l > "$CRONTAB_BACKUP" || { print_error "Cannot back up existing crontab"; exit 1; }
        chmod 600 "$CRONTAB_BACKUP"
        cp "$CRONTAB_BACKUP" "$EXISTING_CRONTAB_FILE" || exit 1
        print_message "Existing crontab backed up: $CRONTAB_BACKUP"
    else
        : > "$EXISTING_CRONTAB_FILE"
    fi

    # Remove previous managed block only; preserve user-managed cron entries.
    CLEAN_CRONTAB_FILE="${CRONTAB_TMP_DIR}/clean-crontab"
    strip_managed_block "$EXISTING_CRONTAB_FILE" crontab > "$CLEAN_CRONTAB_FILE" || {
        print_error "Unbalanced managed crontab markers; existing crontab was preserved"
        exit 1
    }

    # Create managed crontab content with environment variables
    CRONTAB_CONTENT="# BEGIN system-setup.sh managed crontab
# Crontab environment variables
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
HOME=/root
MAILTO=\"\"
LANG=en_US.UTF-8
"

    # Add custom tasks if provided
    if [ ! -z "$CRONTAB_TASKS" ]; then
        CRONTAB_CONTENT="${CRONTAB_CONTENT}
# Custom cron tasks
${CRONTAB_TASKS}"
    fi

    CRONTAB_CONTENT="${CRONTAB_CONTENT}
# END system-setup.sh managed crontab"

    # Install merged crontab
    if {
        cat "$CLEAN_CRONTAB_FILE"
        if [ -s "$CLEAN_CRONTAB_FILE" ]; then
            printf '\n'
        fi
        printf '%s\n' "$CRONTAB_CONTENT"
    } | crontab -; then
        CRONTAB_OK=true
        print_message "Crontab configured successfully"
    else
        print_error "Failed to install crontab; previous crontab was preserved"
    fi
    rm -f "$EXISTING_CRONTAB_FILE" "$CLEAN_CRONTAB_FILE"
    # Display configured crontab
    print_message "Configured crontab:"
    echo "----------------------------------------"
    crontab -l
    echo "----------------------------------------"
    echo ""
    fi
else
    print_message "Skipping crontab configuration (not requested)"
fi

# ============================================
# INSTALL CUSTOM MOTD
# ============================================

# Install custom MOTD
if [ "$INSTALL_MOTD" = "y" ] || [ "$INSTALL_MOTD" = "Y" ]; then
    print_message "Installing custom MOTD (Message of the Day)..."
    echo ""
    
    if create_temp_dir "motd-install"; then
        MOTD_TMP_DIR="$SYSTEM_SETUP_CREATED_TEMP_DIR"
    else
        MOTD_TMP_DIR=""
    fi
    MOTD_SCRIPT="${MOTD_TMP_DIR}/motd_install.sh"
    MOTD_TEST_OUTPUT="${MOTD_TMP_DIR}/motd-test.txt"
    MOTD_SCRIPT_READY=false
    
    MOTD_COMMIT="11f4fb44c4e8f906059212b99661156bac3f059e"
    if [ "$OS" = "debian" ]; then
        MOTD_URL="https://raw.githubusercontent.com/civisrom/motd-ubuntu-debian/${MOTD_COMMIT}/scripts/debian.sh"
        MOTD_SHA256="b26fdfaa4f61cade002de578c0e6872c19ee672655a4ecea631e5f50c597c0f7"
    else
        MOTD_URL="https://raw.githubusercontent.com/civisrom/motd-ubuntu-debian/${MOTD_COMMIT}/scripts/ubuntu.sh"
        MOTD_SHA256="ad1303d8b8ee427ea7956a9517de02572b6897034da1782eb49f66538e429e49"
    fi
    
    print_message "Downloading MOTD installation script for $OS..."
    if [ -n "$MOTD_TMP_DIR" ] && download_verified_url "$MOTD_URL" "$MOTD_SCRIPT" "$MOTD_SHA256"; then
        if validate_shell_script "$MOTD_SCRIPT" bash; then
            MOTD_SCRIPT_READY=true
        else
            print_error "Refusing to run invalid MOTD installation script"
        fi
    fi

    if [ "$MOTD_SCRIPT_READY" = true ]; then
        chmod +x "$MOTD_SCRIPT"
        print_message "Running MOTD installation script..."
        
        if bash "$MOTD_SCRIPT"; then
            MOTD_OK=true
            print_message "Custom MOTD installed successfully"
            rm -f "$MOTD_SCRIPT"
            
            # Post-installation fixes for MOTD
            print_message "Applying MOTD post-installation fixes..."
            
            # Initialize SSH restart flag
            SSH_RESTART_NEEDED=false
            
            # 1. Ensure all scripts in /etc/update-motd.d/ are executable
            if [ -d /etc/update-motd.d ]; then
                chmod +x /etc/update-motd.d/* 2>/dev/null
                # Also ensure directory permissions are correct
                chmod 755 /etc/update-motd.d
                print_message "Set executable permissions on MOTD scripts and directory"
            fi
            
            # 2. Check and fix SSH configuration for MOTD
            SSHD_CONFIG="/etc/ssh/sshd_config"
            if [ -f "$SSHD_CONFIG" ]; then
                # Backup SSH config if not already backed up
                MOTD_SSH_BACKUP="${SSHD_CONFIG}.backup.motd.$(date +%Y%m%d-%H%M%S)~"
                cp -p "$SSHD_CONFIG" "$MOTD_SSH_BACKUP" || exit 1
                
                # Check UsePAM parameter (must be yes for MOTD)
                if grep -q "^UsePAM no" "$SSHD_CONFIG"; then
                    sed -i 's/^UsePAM no/UsePAM yes/' "$SSHD_CONFIG"
                    print_message "Enabled UsePAM in SSH config (required for MOTD)"
                    SSH_RESTART_NEEDED=true
                fi
                
                # Check PrintMotd parameter
                if grep -q "^PrintMotd" "$SSHD_CONFIG"; then
                    # Parameter exists, ensure it's set to yes
                    if ! grep -q "^PrintMotd yes" "$SSHD_CONFIG"; then
                        sed -i 's/^PrintMotd.*/PrintMotd yes/' "$SSHD_CONFIG"
                        print_message "Enabled PrintMotd in SSH config"
                        SSH_RESTART_NEEDED=true
                    fi
                else
                    # Parameter doesn't exist, add it
                    echo "" >> "$SSHD_CONFIG"
                    echo "# Enable MOTD" >> "$SSHD_CONFIG"
                    echo "PrintMotd yes" >> "$SSHD_CONFIG"
                    print_message "Added PrintMotd to SSH config"
                    SSH_RESTART_NEEDED=true
                fi
                
                # Ensure PrintLastLog is no (conflicts with custom MOTD)
                if grep -q "^PrintLastLog yes" "$SSHD_CONFIG"; then
                    sed -i 's/^PrintLastLog yes/PrintLastLog no/' "$SSHD_CONFIG"
                    print_message "Disabled PrintLastLog to avoid conflicts"
                    SSH_RESTART_NEEDED=true
                fi
                
                # Restart SSH if needed
                if [ "$SSH_RESTART_NEEDED" = true ]; then
                    print_message "Restarting SSH service for MOTD changes..."
                    if ! sshd -t; then
                        print_error "MOTD SSH configuration is invalid; restoring the previous file"
                        cp -p -- "$MOTD_SSH_BACKUP" "$SSHD_CONFIG"
                        MOTD_OK=false
                    elif systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null; then
                        print_success "SSH service restarted successfully"
                    else
                        MOTD_OK=false
                        print_error "Could not restart SSH after MOTD changes"
                    fi
                fi
            fi
            
            # 3. Disable static MOTD file if exists
            if [ -f /etc/motd ]; then
                MOTD_BACKUP="/etc/motd.backup.$(date +%Y%m%d-%H%M%S)~"
                mv /etc/motd "$MOTD_BACKUP"
                touch /etc/motd
                print_message "Disabled static /etc/motd file"
            fi
            
            # 4. Check PAM configuration
            PAM_SSHD="/etc/pam.d/sshd"
            if [ -f "$PAM_SSHD" ]; then
                # Backup PAM config
                if [ ! -f "${PAM_SSHD}.backup.motd~" ]; then
                    cp "$PAM_SSHD" "${PAM_SSHD}.backup.motd~"
                fi
                
                if ! grep -q "pam_motd.so" "$PAM_SSHD"; then
                    print_warning "PAM MOTD module not found in $PAM_SSHD"
                    print_message "Adding pam_motd.so to PAM configuration..."
                    echo "" >> "$PAM_SSHD"
                    echo "# Display MOTD" >> "$PAM_SSHD"
                    echo "session optional pam_motd.so motd=/run/motd.dynamic" >> "$PAM_SSHD"
                    echo "session optional pam_motd.so noupdate" >> "$PAM_SSHD"
                    print_message "PAM MOTD configuration added"
                else
                    print_message "PAM MOTD module already configured"
                fi
            else
                print_warning "PAM SSH config not found: $PAM_SSHD"
            fi
            
            # 5. Install run-parts if not available
            if ! command -v run-parts &> /dev/null; then
                print_warning "run-parts not found, installing debianutils..."
                apt-get install -y debianutils || print_warning "Failed to install debianutils"
            fi
            
            # 6. Ensure /run/motd.dynamic can be created (it's a file, not directory)
            # PAM will create this file automatically when needed
            # Just verify /run directory exists (it always does on modern systems)
            if [ ! -d /run ]; then
                print_warning "/run directory does not exist (unusual)"
            else
                # Remove /run/motd.dynamic if it's incorrectly a directory
                if [ -d /run/motd.dynamic ]; then
                    print_warning "/run/motd.dynamic exists as directory, removing..."
                    rm -rf /run/motd.dynamic
                    print_message "Removed incorrect directory /run/motd.dynamic"
                fi
                # Create empty file if it doesn't exist (optional, PAM will create it)
                if [ ! -f /run/motd.dynamic ]; then
                    touch /run/motd.dynamic 2>/dev/null || true
                    print_message "Prepared /run/motd.dynamic file"
                fi
            fi
            
            # 7. Test MOTD generation
            print_message "Testing MOTD generation..."
            if command -v run-parts &> /dev/null; then
                if run-parts /etc/update-motd.d/ > "$MOTD_TEST_OUTPUT" 2>&1; then
                    print_success "MOTD scripts executed successfully"
                    
                    # Check if output was generated
                    if [ -s "$MOTD_TEST_OUTPUT" ]; then
                        print_message "MOTD content generated successfully"
                    else
                        print_warning "MOTD scripts ran but produced no output"
                    fi
                else
                    MOTD_OK=false
                    print_error "Some MOTD scripts failed"
                    print_message "Error details:"
                    cat "$MOTD_TEST_OUTPUT"
                fi
            else
                print_warning "Cannot test MOTD without run-parts"
            fi
            
            # 8. Display current MOTD preview
            echo ""
            print_header "═══════════════════════════════════════════════"
            print_header "   MOTD Preview (will be shown on SSH login)"
            print_header "═══════════════════════════════════════════════"
            echo ""
            
            if command -v run-parts &> /dev/null && [ -d /etc/update-motd.d ]; then
                run-parts /etc/update-motd.d/ 2>/dev/null || echo "MOTD generation failed - please run: run-parts /etc/update-motd.d/"
            else
                print_warning "Cannot display MOTD preview"
            fi
            
            echo ""
            print_header "═══════════════════════════════════════════════"
            echo ""
            
            # Summary of MOTD configuration
            if [ "${MOTD_OK:-false}" = true ]; then
                print_success "MOTD configuration completed successfully!"
            else
                print_error "MOTD configuration is incomplete"
            fi
            print_message "What was configured:"
            print_message "  ✓ MOTD scripts installed in /etc/update-motd.d/"
            print_message "  ✓ SSH configured to display MOTD"
            print_message "  ✓ PAM configured for MOTD"
            print_message "  ✓ Static MOTD file disabled"
            print_message ""
            print_warning "Important: MOTD will be visible on your NEXT SSH login"
            print_message "To test now: exit and reconnect via SSH"
            echo ""
            
            
        else
            print_error "MOTD installation failed"
            rm -f "$MOTD_SCRIPT"
        fi
    else
        print_error "Failed to download or validate MOTD installation script"
    fi
    
    echo ""
else
    print_message "Skipping MOTD installation (not requested)"
fi

# ============================================
# INSTALL CUSTOM UFW DOCKER RULES
# ============================================

run_ufw_custom_rules_script() {
    if ! validate_shell_script "$UFW_INSTALL_PATH" bash; then
        print_error "Refusing to run invalid custom UFW Docker rules script: $UFW_INSTALL_PATH"
        return 1
    fi

    print_message "Executing custom UFW Docker rules script..."
    if [ -n "$UFW_SSH_PORT" ]; then
        print_message "Using custom SSH port: $UFW_SSH_PORT"
    fi
    echo ""
    print_header "═══════════════════════════════════════════════════"
    print_header "  Custom UFW Docker Rules Script Output (v${UFW_RULES_VERSION})"
    print_header "═══════════════════════════════════════════════════"
    echo ""

    if [ -n "$UFW_SSH_PORT" ]; then
        # Execute with SSH_PORT environment variable
        if SSH_PORT="$UFW_SSH_PORT" bash "$UFW_INSTALL_PATH"; then
            echo ""
            print_header "═══════════════════════════════════════════════════"
            print_message "Custom UFW Docker rules applied successfully"
        else
            echo ""
            print_header "═══════════════════════════════════════════════════"
            print_error "Custom UFW Docker rules script failed"
            return 1
        fi
    else
        # Execute without custom SSH_PORT
        if bash "$UFW_INSTALL_PATH"; then
            echo ""
            print_header "═══════════════════════════════════════════════════"
            print_message "Custom UFW Docker rules applied successfully"
        else
            echo ""
            print_header "═══════════════════════════════════════════════════"
            print_error "Custom UFW Docker rules script failed"
            return 1
        fi
    fi
}

if [ "$INSTALL_UFW_CUSTOM_RULES" = "y" ] || [ "$INSTALL_UFW_CUSTOM_RULES" = "Y" ]; then
    print_message "Installing custom UFW Docker rules (v${UFW_RULES_VERSION})..."
    echo ""

    UFW_SCRIPT_NAME="ufw-docker-rules-v${UFW_RULES_VERSION}.sh"
    UFW_INSTALL_PATH="/opt/${UFW_SCRIPT_NAME}"

    # Check installation source
    if [ "$UFW_INSTALL_SOURCE" = "2" ]; then
        # Install from public repository
        print_message "Installing from public repository..."
        UFW_RULES_COMMIT="8cca4af2ce38323940d3657b1c8bbfc188d0b98a"
        case "$UFW_RULES_VERSION" in
            4) UFW_RULES_SHA256="e36a390a808a9a2684e5423173a550b0c3df762c723c0f4f1897dde857c2d42d" ;;
            6) UFW_RULES_SHA256="0c2809fbaefaf3220643df60bfb76f343cfc7882793603f7f40f476a16c01f13" ;;
            *) print_error "Unsupported UFW rules version: $UFW_RULES_VERSION"; UFW_RULES_SHA256="" ;;
        esac
        UFW_REPO_URL="https://raw.githubusercontent.com/civisrom/ufw-rules-docker/${UFW_RULES_COMMIT}/ufw-docker-rules-v${UFW_RULES_VERSION}.sh"

        print_message "Downloading script from repository..."
        if [ -n "$UFW_RULES_SHA256" ] && download_verified_url "$UFW_REPO_URL" "$UFW_INSTALL_PATH" "$UFW_RULES_SHA256"; then
            print_message "Pinned script downloaded and SHA256 verified"

            # Replace SSH port in script if custom port is specified
            if [ -n "$UFW_SSH_PORT" ] && [ "$UFW_SSH_PORT" != "22" ]; then
                print_message "Configuring script to use custom SSH port: $UFW_SSH_PORT"
                # Replace hardcoded SSH_PORT=22 with custom port
                if sed -i "s/^SSH_PORT=22$/SSH_PORT=$UFW_SSH_PORT/" "$UFW_INSTALL_PATH"; then
                    print_message "SSH port configured successfully in ufw-docker-rules-v${UFW_RULES_VERSION}.sh"
                fi
                # Also replace SSH_PORT=${SSH_PORT:-22} pattern if exists
                sed -i "s/^SSH_PORT=\${SSH_PORT:-22}$/SSH_PORT=$UFW_SSH_PORT/" "$UFW_INSTALL_PATH"
            fi

            # Set executable permissions
            chmod +x "$UFW_INSTALL_PATH"
            print_message "Script installed with executable permissions"

            run_ufw_custom_rules_script && UFW_CUSTOM_RULES_OK=true
        else
            print_error "Failed to download script from repository"
            print_error "URL: $UFW_REPO_URL"
        fi
    else
        # Install from password-protected archive
        print_message "Installing from password-protected archive..."
        UFW_ARCHIVE_READY=true

        # Check if p7zip is installed, install if needed
        if ! command -v 7z &> /dev/null; then
            print_message "Installing 7z for archive extraction..."
            if apt-get install -y p7zip-full || apt-get install -y 7zip; then
                print_message "7z installed successfully"
            else
                print_error "Failed to install 7z archive tool"
                print_warning "Custom UFW Docker rules archive installation will be skipped; setup will continue"
                UFW_ARCHIVE_READY=false
            fi
        fi

        if [ "$UFW_ARCHIVE_READY" = true ]; then
            UFW_ARCHIVE_URL="https://raw.githubusercontent.com/civisrom/debian-ubuntu-setup/${SYSTEM_SETUP_REPOSITORY_REF}/config/ufw-docker-rules-v4.7z"
            UFW_ARCHIVE_SHA256="1e18dd1926fa2c767f9a812d63a76504eeb58f07bbd4d64636644f27d561cac1"
            if create_temp_dir "ufw-docker-rules"; then
                UFW_TMP_DIR="$SYSTEM_SETUP_CREATED_TEMP_DIR"
            else
                UFW_TMP_DIR=""
            fi
            UFW_ARCHIVE_FILE="${UFW_TMP_DIR}/ufw-docker-rules-v4.7z"
            UFW_EXTRACT_DIR="${UFW_TMP_DIR}/extract"

        print_message "Downloading custom UFW rules archive..."
        if [ -n "$UFW_TMP_DIR" ] && download_verified_url "$UFW_ARCHIVE_URL" "$UFW_ARCHIVE_FILE" "$UFW_ARCHIVE_SHA256" 900; then
            print_message "Archive downloaded and SHA256 verified"

            # Create extraction directory
            mkdir -p "$UFW_EXTRACT_DIR"

            # Feed the password over stdin so it is never visible in argv.
            print_message "Extracting archive..."
            if extract_7z_archive "$UFW_ARCHIVE_FILE" "$UFW_EXTRACT_DIR" <<< "${UFW_CUSTOM_RULES_PASSWORD}"; then
                print_message "Archive extracted successfully"

                # Find and install the script file
                SCRIPT_FOUND=false

                # Check in root of extraction
                if [ -f "${UFW_EXTRACT_DIR}/${UFW_SCRIPT_NAME}" ]; then
                    SCRIPT_SOURCE="${UFW_EXTRACT_DIR}/${UFW_SCRIPT_NAME}"
                    SCRIPT_FOUND=true
                # Check in opt folder
                elif [ -f "${UFW_EXTRACT_DIR}/opt/${UFW_SCRIPT_NAME}" ]; then
                    SCRIPT_SOURCE="${UFW_EXTRACT_DIR}/opt/${UFW_SCRIPT_NAME}"
                    SCRIPT_FOUND=true
                # Check in opt/scripts folder
                elif [ -f "${UFW_EXTRACT_DIR}/opt/scripts/${UFW_SCRIPT_NAME}" ]; then
                    SCRIPT_SOURCE="${UFW_EXTRACT_DIR}/opt/scripts/${UFW_SCRIPT_NAME}"
                    SCRIPT_FOUND=true
                fi

                if [ "$SCRIPT_FOUND" = true ]; then
                    print_message "Found script: $UFW_SCRIPT_NAME"
                    print_message "Installing script to ${UFW_INSTALL_PATH}..."

                    if ! validate_shell_script "$SCRIPT_SOURCE" bash; then
                        print_error "Archive contained an invalid shell script: $SCRIPT_SOURCE"
                        SCRIPT_FOUND=false
                    else
                        if [ -f "$UFW_INSTALL_PATH" ]; then
                            cp -- "$UFW_INSTALL_PATH" "${UFW_INSTALL_PATH}.backup.$(date +%Y%m%d-%H%M%S)~"
                        fi
                        if ! install -m 0755 -o root -g root "$SCRIPT_SOURCE" "$UFW_INSTALL_PATH"; then
                            print_error "Failed to install the extracted UFW script"
                            SCRIPT_FOUND=false
                        fi
                    fi

                    if [ "$SCRIPT_FOUND" = true ]; then
                        # Set executable permissions
                        chmod 0755 "$UFW_INSTALL_PATH"
                        print_message "Script installed with executable permissions"

                    # Replace SSH port in script if custom port is specified
                    if [ -n "$UFW_SSH_PORT" ] && [ "$UFW_SSH_PORT" != "22" ]; then
                        print_message "Configuring script to use custom SSH port: $UFW_SSH_PORT"
                        # Replace hardcoded SSH_PORT=22 with custom port
                        if sed -i "s/^SSH_PORT=22$/SSH_PORT=$UFW_SSH_PORT/" "$UFW_INSTALL_PATH"; then
                            print_message "SSH port configured successfully in ufw-docker-rules-v${UFW_RULES_VERSION}.sh"
                        fi
                        # Also replace SSH_PORT=${SSH_PORT:-22} pattern if exists
                        sed -i "s/^SSH_PORT=\${SSH_PORT:-22}$/SSH_PORT=$UFW_SSH_PORT/" "$UFW_INSTALL_PATH"
                    fi

                        run_ufw_custom_rules_script && UFW_CUSTOM_RULES_OK=true
                    fi
                else
                    print_error "Script file not found in archive: ${UFW_SCRIPT_NAME}"
                    print_error "Checked locations:"
                    print_error "  - ${UFW_EXTRACT_DIR}/${UFW_SCRIPT_NAME}"
                    print_error "  - ${UFW_EXTRACT_DIR}/opt/${UFW_SCRIPT_NAME}"
                    print_error "  - ${UFW_EXTRACT_DIR}/opt/scripts/${UFW_SCRIPT_NAME}"
                fi

                # Cleanup extraction directory
                rm -rf "$UFW_EXTRACT_DIR"

                # Delete archive
                rm -f "$UFW_ARCHIVE_FILE"
                unset UFW_CUSTOM_RULES_PASSWORD
                print_message "Archive deleted"
            else
                print_error "Failed to extract archive; see the 7z diagnostic above"
                rm -f "$UFW_ARCHIVE_FILE"
                unset UFW_CUSTOM_RULES_PASSWORD
            fi
        else
            print_error "Failed to download custom UFW rules archive"
        fi
        fi
    fi

    echo ""
else
    print_message "Skipping custom UFW Docker rules (not requested)"
fi

# ============================================
# EXTRACT OPT.7Z ARCHIVE TO /OPT
# ============================================

OPT_EXTRACTED_OK=false
OPT_COPY_OK=false

if [ "$EXTRACT_OPT_ARCHIVE" = "y" ] || [ "$EXTRACT_OPT_ARCHIVE" = "Y" ]; then
    echo ""
    print_header "═══════════════════════════════════════════════════"
    print_header "   Extracting opt.7z Archive to /opt"
    print_header "═══════════════════════════════════════════════════"
    echo ""

    # Check if p7zip is installed, install if needed
    if ! command -v 7z &> /dev/null; then
        print_message "Installing 7z for archive extraction..."
        if apt-get install -y p7zip-full || apt-get install -y 7zip; then
            print_message "7z installed successfully"
        else
            print_error "CRITICAL: Failed to install 7z archive tool"
            print_error "Cannot extract opt.7z archive"
        fi
    fi

    # Only proceed if 7z is available
    if command -v 7z &> /dev/null; then
        OPT_ARCHIVE_URL="https://raw.githubusercontent.com/civisrom/debian-ubuntu-setup/${SYSTEM_SETUP_REPOSITORY_REF}/config/opt.7z"
        OPT_ARCHIVE_SHA256="5516f98f5549bed8a11cd8911ca21904c2cbb501038fd96e450f5ef097a03f03"
        if create_temp_dir "opt-archive"; then
            OPT_TMP_DIR="$SYSTEM_SETUP_CREATED_TEMP_DIR"
        else
            OPT_TMP_DIR=""
        fi
        OPT_ARCHIVE_FILE="${OPT_TMP_DIR}/opt.7z"
        OPT_EXTRACT_DIR="${OPT_TMP_DIR}/extract"

        print_message "Downloading opt.7z archive for /opt files..."
        if [ -n "$OPT_TMP_DIR" ] && download_verified_url "$OPT_ARCHIVE_URL" "$OPT_ARCHIVE_FILE" "$OPT_ARCHIVE_SHA256" 900; then
            print_message "opt.7z archive downloaded and SHA256 verified"

            # Create extraction directory
            mkdir -p "$OPT_EXTRACT_DIR"

            # Feed the password over stdin so it is never visible in argv.
            print_message "Extracting opt.7z archive..."
            if extract_7z_archive "$OPT_ARCHIVE_FILE" "$OPT_EXTRACT_DIR" <<< "${OPT_ARCHIVE_PASSWORD}"; then
                print_message "opt.7z archive extracted successfully"

                # Copy all contents to /opt
                print_message "Copying files and folders to /opt..."
                if [ -n "$(find "$OPT_EXTRACT_DIR" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
                    OPT_COPY_SOURCE="$OPT_EXTRACT_DIR"
                    # Accept archives containing an opt/ wrapper as well as
                    # archives whose root is already the contents of /opt.
                    if [ -d "$OPT_EXTRACT_DIR/opt" ] &&
                       [ "$(find "$OPT_EXTRACT_DIR" -mindepth 1 -maxdepth 1 | wc -l)" -eq 1 ]; then
                        OPT_COPY_SOURCE="$OPT_EXTRACT_DIR/opt"
                    fi
                    if mkdir -p /opt && cp -a "$OPT_COPY_SOURCE/." /opt/; then
                        OPT_COPY_OK=true
                        print_message "Files copied to /opt successfully"

                        # Verify nftables directory was extracted (critical for config installation)
                        if [ -d "/opt/nftables" ]; then
                            print_success "nftables directory found in /opt"
                            OPT_EXTRACTED_OK=true
                            # List nftables configs for verification
                            print_message "Available nftables configs:"
                            ls -la /opt/nftables/*.conf 2>/dev/null | awk '{print "  - " $NF}' || print_warning "No .conf files found in /opt/nftables/"
                            if [ -d "/opt/nftables/logging" ]; then
                                print_message "Available logging scripts:"
                                ls -la /opt/nftables/logging/*.sh 2>/dev/null | awk '{print "  - " $NF}' || print_warning "No .sh files found in /opt/nftables/logging/"
                            else
                                print_warning "nftables/logging directory not found in archive"
                            fi
                            verify_nft_profile_assets "/opt/nftables" || print_warning "Some configured nftables profile assets are missing"
                        else
                            print_warning "nftables directory NOT found after extraction"
                            print_warning "Archive may have different internal structure"
                            # Try to find nftables files in case of nested directory
                            FOUND_NFTABLES=$(find /opt -name "*nftables*.conf" -type f 2>/dev/null | head -1)
                            if [ -n "$FOUND_NFTABLES" ]; then
                                FOUND_DIR=$(dirname "$FOUND_NFTABLES")
                                print_message "Found nftables configs in: $FOUND_DIR"
                                print_message "Restructuring: moving files to /opt/nftables/..."
                                mkdir -p /opt/nftables
                                NFT_CONF_COPIED=0
                                while IFS= read -r _nft_conf; do
                                    cp "$_nft_conf" /opt/nftables/
                                    NFT_CONF_COPIED=$((NFT_CONF_COPIED + 1))
                                done < <(find "$FOUND_DIR" -maxdepth 1 -type f -name "*nftables*.conf" 2>/dev/null | sort)
                                print_message "Copied $NFT_CONF_COPIED nftables config file(s)"
                                # Also try to find and copy logging scripts
                                FOUND_LOGGING=$(find /opt -type f -name "*.sh" -path "*/logging/*" 2>/dev/null | head -1)
                                if [ -n "$FOUND_LOGGING" ]; then
                                    FOUND_LOG_DIR=$(dirname "$FOUND_LOGGING")
                                    mkdir -p /opt/nftables/logging
                                    NFT_LOG_COPIED=0
                                    while IFS= read -r _nft_log; do
                                        cp "$_nft_log" /opt/nftables/logging/
                                        NFT_LOG_COPIED=$((NFT_LOG_COPIED + 1))
                                    done < <(find "$FOUND_LOG_DIR" -maxdepth 1 -type f -name "*.sh" 2>/dev/null | sort)
                                    print_message "Copied $NFT_LOG_COPIED nftables logging script(s)"
                                fi
                                unset _nft_conf _nft_log NFT_CONF_COPIED NFT_LOG_COPIED
                                OPT_EXTRACTED_OK=true
                                print_success "nftables files restructured to /opt/nftables/"
                                verify_nft_profile_assets "/opt/nftables" || print_warning "Some configured nftables profile assets are missing"
                            fi
                        fi

                        # Make scripts in scripts folder executable (except .ini files)
                        if [ -d "/opt/scripts" ]; then
                            print_message "Setting executable permissions for scripts in /opt/scripts..."

                            # Find all files in scripts directory and make them executable (except .ini)
                            find /opt/scripts -type f ! -name "*.ini" -exec chmod +x {} \;

                            # Count executable files
                            EXEC_COUNT=$(find /opt/scripts -type f ! -name "*.ini" | wc -l)
                            print_message "Made $EXEC_COUNT file(s) executable in /opt/scripts"
                        fi

                        # List what was copied
                        print_message "Contents copied to /opt:"
                        find /opt -mindepth 1 -maxdepth 1 -printf '  - %f\n' | sort
                    else
                        print_error "Failed to copy extracted archive contents to /opt; files may be incomplete"
                    fi
                else
                    print_error "opt.7z archive is empty"
                fi

                # Cleanup
                rm -rf "$OPT_EXTRACT_DIR"
                rm -f "$OPT_ARCHIVE_FILE"
                unset OPT_ARCHIVE_PASSWORD
                print_message "Temporary files cleaned up"
            else
                print_error "Failed to extract opt.7z archive; see the 7z diagnostic above"
                rm -f "$OPT_ARCHIVE_FILE"
                unset OPT_ARCHIVE_PASSWORD
            fi
        else
            print_error "Failed to download opt.7z archive"
        fi
    fi

    echo ""
else
    print_message "Skipping opt.7z extraction (not requested)"
fi

# ============================================
# ENABLE NFTABLES FIREWALL
# ============================================
# NOTE: This section runs AFTER opt.7z extraction so config files are available.
# Order of operations:
#   1. Install nftables and validate a single atomic transaction
#   2. Snapshot the live ruleset before any mutation
#   3. Apply `flush ruleset` + the new config in one nft transaction
#   4. Disable future UFW activation without touching committed runtime rules
#   5. Install nftables config from opt.7z (relay/docker/native profile)
#   6. Run logging setup script matching the selected profile
#   7. Verify syntax and apply nftables configuration

if [ "$ENABLE_NFTABLES" = "y" ] || [ "$ENABLE_NFTABLES" = "Y" ]; then
    echo ""
    print_header "═══════════════════════════════════════════════════"
    print_header "   Enabling nftables Firewall"
    print_header "═══════════════════════════════════════════════════"
    echo ""

    NFTABLES_OK=true
    NFTABLES_DST="/etc/nftables.conf"
    create_temp_dir "nftables" || {
        print_error "Failed to create nftables temporary directory"
        NFTABLES_OK=false
    }
    NFT_TMP_DIR="${SYSTEM_SETUP_CREATED_TEMP_DIR:-}"
    NFT_PREFLIGHT_ERR="${NFT_TMP_DIR}/preflight.err"
    NFT_SYNTAX_ERR="${NFT_TMP_DIR}/syntax.err"
    NFT_APPLY_ERR="${NFT_TMP_DIR}/apply.err"
    NFT_TRANSACTION="${NFT_TMP_DIR}/transaction.nft"
    NFT_LIVE_BACKUP="${NFT_TMP_DIR}/live-ruleset.nft"
    NFT_ROLLBACK_TRANSACTION="${NFT_TMP_DIR}/rollback.nft"
    NFTABLES_CONFIG_BACKUP=""
    NFT_CONFIG_CHANGED=false
    NFT_RUNTIME_CHANGED=false
    NFT_UFW_CHANGED=false
    NFT_SERVICE_PREVIOUS_STATE=$(systemctl is-enabled nftables.service 2>/dev/null || true)
    NFT_UFW_PREVIOUS_STATE=$(systemctl is-enabled ufw.service 2>/dev/null || true)
    NFT_LOCK_HELD=false

    # Serialize firewall changes with the standalone nft-docker-watch helper.
    # Two concurrent flush-and-reload transactions can otherwise overwrite each
    # other's runtime snapshot and make rollback unreliable.
    if ! command -v flock >/dev/null 2>&1; then
        print_error "flock is required for a safe nftables transaction"
        NFTABLES_OK=false
    else
        mkdir -p /run/lock
        exec 8>/run/lock/nft-docker-watch.lock
        if flock -w 30 8; then
            NFT_LOCK_HELD=true
        else
            print_error "Timed out waiting for another nftables transaction"
            NFTABLES_OK=false
        fi
    fi

    # Install nftables before syntax preflight, but before disabling any
    # existing firewall.
    print_message "Preflight: checking nftables installation..."
    if command -v nft &>/dev/null; then
        print_message "nftables is already installed: $(nft --version 2>/dev/null || echo 'unknown version')"
    else
        print_message "Installing nftables package for preflight validation..."
        if apt-get install -y nftables; then
            print_success "nftables installed successfully"
        else
            print_error "CRITICAL: Failed to install nftables"
            NFTABLES_OK=false
        fi
    fi

    # Fail closed: do not disable an existing firewall until there is a valid
    # nftables config ready to apply.
    if [ "$NFTABLES_OK" = true ] && { [ "$INSTALL_NFTABLES_CONF" = "y" ] || [ "$INSTALL_NFTABLES_CONF" = "Y" ]; }; then
        NFTABLES_SRC="/opt/nftables/${NFTABLES_CONF_FILE}"
        if [ ! -f "$NFTABLES_SRC" ] || [ ! -s "$NFTABLES_SRC" ]; then
            print_error "nftables config preflight failed: source file not found: $NFTABLES_SRC"
            print_error "UFW/iptables will not be disabled"
            NFTABLES_OK=false
        elif ! build_nft_transaction "$NFTABLES_SRC" "$NFT_TRANSACTION" || \
             ! nft -c -f "$NFT_TRANSACTION" 2>"$NFT_PREFLIGHT_ERR"; then
            print_error "nftables config preflight failed: syntax error in $NFTABLES_SRC"
            [ -s "$NFT_PREFLIGHT_ERR" ] && cat "$NFT_PREFLIGHT_ERR"
            print_error "UFW/iptables will not be disabled"
            NFTABLES_OK=false
        else
            print_success "nftables preflight passed for $NFTABLES_SRC"
        fi
        rm -f "$NFT_PREFLIGHT_ERR"
    elif [ "$NFTABLES_OK" = true ] && [ -f "$NFTABLES_DST" ] && [ -s "$NFTABLES_DST" ]; then
        if build_nft_transaction "$NFTABLES_DST" "$NFT_TRANSACTION" && \
           nft -c -f "$NFT_TRANSACTION" 2>"$NFT_PREFLIGHT_ERR"; then
            print_success "nftables preflight passed for existing $NFTABLES_DST"
        else
            print_error "nftables preflight failed: syntax error in existing $NFTABLES_DST"
            [ -s "$NFT_PREFLIGHT_ERR" ] && cat "$NFT_PREFLIGHT_ERR"
            print_error "UFW/iptables will not be disabled"
            NFTABLES_OK=false
        fi
        rm -f "$NFT_PREFLIGHT_ERR"
    elif [ "$NFTABLES_OK" = true ]; then
        print_error "nftables selected but no config profile or existing /etc/nftables.conf was found"
        print_error "UFW/iptables will not be disabled"
        NFTABLES_OK=false
    fi

    # Snapshot the exact live ruleset. This is the rollback source even when
    # /etc/nftables.conf is absent or differs from runtime state.
    if [ "$NFTABLES_OK" = true ]; then
        if ! nft list ruleset > "$NFT_LIVE_BACKUP" 2>"$NFT_PREFLIGHT_ERR"; then
            print_error "Could not snapshot the live nftables ruleset; refusing firewall migration"
            NFTABLES_OK=false
        else
            chmod 0600 "$NFT_LIVE_BACKUP"
        fi
    fi

    # Do not flush legacy rules before nftables is committed. If iptables uses
    # the legacy backend it is cleaned only after the new nft rules are active.
    if [ "$NFTABLES_OK" = true ]; then
        print_message "Live firewall snapshot saved; no rules have been flushed"
    fi

    # --- Step 3: Install nftables if not present ---
    if [ "$NFTABLES_OK" = true ]; then
    echo ""
    print_message "Step 3: Checking nftables installation..."
    if command -v nft &>/dev/null; then
        print_message "nftables is already installed: $(nft --version 2>/dev/null || echo 'unknown version')"
    else
        print_message "Installing nftables package..."
        if apt-get install -y nftables; then
            print_success "nftables installed successfully"
        else
            print_error "CRITICAL: Failed to install nftables"
            NFTABLES_OK=false
        fi
    fi
    fi

    # --- Step 5: Install nftables config ---
    if [ "$NFTABLES_OK" = true ] && { [ "$INSTALL_NFTABLES_CONF" = "y" ] || [ "$INSTALL_NFTABLES_CONF" = "Y" ]; }; then
        echo ""
        print_message "Step 5: Installing nftables config (profile: ${NFTABLES_PROFILE}, file: ${NFTABLES_CONF_FILE})..."

        NFTABLES_SRC="/opt/nftables/${NFTABLES_CONF_FILE}"
        NFTABLES_DST="/etc/nftables.conf"

        # Check if config file exists (from opt.7z extraction or pre-installed)
        if [ ! -f "$NFTABLES_SRC" ] || [ ! -s "$NFTABLES_SRC" ]; then
            # Config not found — check if opt.7z was supposed to provide it
            if [ "$OPT_EXTRACTED_OK" = true ]; then
                print_error "Config file not found after opt.7z extraction: $NFTABLES_SRC"
            else
                print_error "Config file not found: $NFTABLES_SRC"
                print_message "  opt.7z was not extracted — file must already exist in /opt/nftables/"
            fi
            print_message "Available files in /opt/nftables/:"
            ls -la /opt/nftables/ 2>/dev/null || print_error "  /opt/nftables/ directory does not exist"
            print_warning "Skipping config installation — using default nftables.conf"
            INSTALL_NFTABLES_CONF="skipped"
        else
            # Backup existing nftables.conf
            if [ -f "$NFTABLES_DST" ]; then
                NFTABLES_CONFIG_BACKUP="${NFTABLES_DST}.backup.$(date +%Y%m%d-%H%M%S)~"
                cp -p "$NFTABLES_DST" "$NFTABLES_CONFIG_BACKUP" || { print_error "Cannot back up nftables configuration"; exit 1; }
                print_message "Existing $NFTABLES_DST backed up"
            fi

            # Copy selected profile config as /etc/nftables.conf.
            # Mode 0755: the config carries a `#!/usr/sbin/nft -f` shebang and
            # is expected to be executable so it can be invoked directly.
            NFT_CONFIG_CHANGED=true
            if ! write_file_atomic "$NFTABLES_DST" 0755 root:root < "$NFTABLES_SRC"; then
                print_error "CRITICAL: Atomic nftables config installation failed"
                INSTALL_NFTABLES_CONF="skipped"
                NFTABLES_OK=false
            fi

            # Verify the copy was successful
            if [ "$NFTABLES_OK" = true ] && [ -f "$NFTABLES_DST" ] && [ -s "$NFTABLES_DST" ] && cmp -s "$NFTABLES_SRC" "$NFTABLES_DST"; then
                print_success "Installed ${NFTABLES_CONF_FILE} -> $NFTABLES_DST"
                print_message "  Permissions: 755, Owner: root:root"
                print_message "  File size: $(wc -c < "$NFTABLES_DST") bytes"
            else
                print_error "CRITICAL: Config file copy verification failed!"
                print_error "Source: $NFTABLES_SRC ($(wc -c < "$NFTABLES_SRC" 2>/dev/null || echo 0) bytes)"
                print_error "Destination: $NFTABLES_DST ($(wc -c < "$NFTABLES_DST" 2>/dev/null || echo 0) bytes)"
                INSTALL_NFTABLES_CONF="skipped"
                NFTABLES_OK=false
            fi
        fi
    elif [ "$NFTABLES_OK" = true ]; then
        echo ""
        print_message "Step 5: Skipping config installation (not requested)"
    fi

    # --- Step 6: Run logging setup script ---
    if [ "$NFTABLES_OK" = true ] && { [ "$INSTALL_NFTABLES_LOGGING" = "y" ] || [ "$INSTALL_NFTABLES_LOGGING" = "Y" ]; } && [ "$INSTALL_NFTABLES_CONF" != "skipped" ] && [ -n "$NFTABLES_LOG_SCRIPT" ]; then
        echo ""
        print_message "Step 6: Running logging setup (profile: ${NFTABLES_PROFILE}, script: ${NFTABLES_LOG_SCRIPT})..."

        LOGGING_SCRIPT="/opt/nftables/logging/${NFTABLES_LOG_SCRIPT}"

        if [ -f "$LOGGING_SCRIPT" ] && [ -s "$LOGGING_SCRIPT" ]; then
            # Make script executable
            chmod +x "$LOGGING_SCRIPT"
            print_message "Running: $LOGGING_SCRIPT"

            # Execute logging setup script
            if bash "$LOGGING_SCRIPT"; then
                NFT_LOGGING_OK=true
                print_success "Logging setup completed (${NFTABLES_LOG_SCRIPT})"
            else
                print_warning "Logging setup script returned an error (exit code: $?)"
                print_message "You can run it manually later: bash $LOGGING_SCRIPT"
            fi
        else
            print_warning "Logging script not found: $LOGGING_SCRIPT"
            print_message "  File must exist in /opt/nftables/logging/ (from opt.7z or pre-installed)"
            print_message "Available logging scripts:"
            ls -la /opt/nftables/logging/ 2>/dev/null || print_warning "  /opt/nftables/logging/ directory does not exist"
        fi
    elif [ "$NFTABLES_OK" = true ] && [ "$INSTALL_NFTABLES_CONF" != "skipped" ]; then
        echo ""
        print_message "Step 6: Skipping logging setup (not requested)"
    fi

    # --- Step 7: Atomically apply and verify nftables configuration ---
    if [ "$NFTABLES_OK" = true ]; then
        echo ""
        NFTABLES_DST="/etc/nftables.conf"

        if [ -s "$NFTABLES_DST" ]; then
            print_message "Step 7: Building one atomic nftables transaction..."
            if build_nft_transaction "$NFTABLES_DST" "$NFT_TRANSACTION" && \
               nft -c -f "$NFT_TRANSACTION" 2>"$NFT_SYNTAX_ERR"; then
                print_success "Atomic transaction syntax check passed"

                if nft -f "$NFT_TRANSACTION" 2>"$NFT_APPLY_ERR"; then
                    NFT_RUNTIME_CHANGED=true
                    TABLES_COUNT=$(nft list tables 2>/dev/null | wc -l)
                    CHAINS_COUNT=$(nft list ruleset 2>/dev/null | grep -cE '^[[:space:]]*chain[[:space:]]' || true)
                    TABLES_COUNT=${TABLES_COUNT:-0}
                    CHAINS_COUNT=${CHAINS_COUNT:-0}

                    if [ "$TABLES_COUNT" -eq 0 ] || [ "$CHAINS_COUNT" -eq 0 ]; then
                        print_error "nftables postcondition failed: no tables or chains were loaded"
                        NFTABLES_OK=false
                    elif ! systemctl enable nftables.service; then
                        print_error "Could not enable nftables for boot"
                        NFTABLES_OK=false
                    elif ! { NFT_UFW_CHANGED=true; disable_ufw_firewall true; }; then
                        print_error "Could not disable future UFW activation after nftables apply"
                        NFTABLES_OK=false
                    else
                        # iptables-nft shares the nft ruleset and must not be flushed.
                        # Only clean a separate legacy backend after nft is active.
                        if command -v iptables >/dev/null 2>&1 && \
                           iptables --version 2>/dev/null | grep -q '(legacy)'; then
                            for TABLE in filter nat mangle raw; do
                                iptables -t "$TABLE" -F 2>/dev/null || true
                                iptables -t "$TABLE" -X 2>/dev/null || true
                            done
                            iptables -P INPUT ACCEPT 2>/dev/null || true
                            iptables -P FORWARD ACCEPT 2>/dev/null || true
                            iptables -P OUTPUT ACCEPT 2>/dev/null || true
                        fi
                        if command -v ip6tables >/dev/null 2>&1 && \
                           ip6tables --version 2>/dev/null | grep -q '(legacy)'; then
                            for TABLE in filter nat mangle raw; do
                                ip6tables -t "$TABLE" -F 2>/dev/null || true
                                ip6tables -t "$TABLE" -X 2>/dev/null || true
                            done
                            ip6tables -P INPUT ACCEPT 2>/dev/null || true
                            ip6tables -P FORWARD ACCEPT 2>/dev/null || true
                            ip6tables -P OUTPUT ACCEPT 2>/dev/null || true
                        fi
                        print_success "nftables rules committed atomically: ${TABLES_COUNT} table(s), ${CHAINS_COUNT} chain(s)"
                    fi
                else
                    print_error "Failed to commit nftables transaction"
                    [ -s "$NFT_APPLY_ERR" ] && cat "$NFT_APPLY_ERR"
                    NFTABLES_OK=false
                fi
            else
                print_error "Syntax error in atomic nftables transaction"
                [ -s "$NFT_SYNTAX_ERR" ] && cat "$NFT_SYNTAX_ERR"
                NFTABLES_OK=false
            fi


        else
            print_error "No non-empty $NFTABLES_DST found; refusing to replace the current firewall"
            NFTABLES_OK=false
        fi
        rm -f "$NFT_SYNTAX_ERR" "$NFT_APPLY_ERR"
    fi

    # Restore persistent state even when failure occurred before runtime apply.
    if [ "$NFTABLES_OK" != true ]; then
        if [ "$NFT_RUNTIME_CHANGED" = true ]; then
            if restore_live_nft_ruleset "$NFT_LIVE_BACKUP" "$NFT_ROLLBACK_TRANSACTION"; then
                print_warning "Live nftables ruleset restored from the pre-change snapshot"
            else
                install -d -m 0700 /var/backups
                NFT_RECOVERY_FILE=$(mktemp /var/backups/nftables-recovery.XXXXXX)
                cp -- "$NFT_LIVE_BACKUP" "$NFT_RECOVERY_FILE"
                print_error "nftables rollback failed; live snapshot saved at $NFT_RECOVERY_FILE"
            fi
        fi
        if [ "$NFT_CONFIG_CHANGED" = true ]; then
            if [ -n "$NFTABLES_CONFIG_BACKUP" ]; then
                cp -p -- "$NFTABLES_CONFIG_BACKUP" "$NFTABLES_DST" || print_error "Failed to restore nftables config"
            else
                rm -f -- "$NFTABLES_DST"
            fi
        fi
        if [ "$NFT_UFW_CHANGED" = true ]; then
            case "$NFT_UFW_PREVIOUS_STATE" in
                masked) systemctl mask ufw.service 2>/dev/null || true ;;
                enabled) systemctl unmask ufw.service; systemctl enable ufw.service ;;
                *) systemctl unmask ufw.service; systemctl disable ufw.service ;;
            esac
        fi
        case "$NFT_SERVICE_PREVIOUS_STATE" in
            enabled) : ;;
            masked) systemctl mask nftables.service 2>/dev/null || true ;;
            *) systemctl disable nftables.service 2>/dev/null || true ;;
        esac
    fi

    if [ "$NFT_LOCK_HELD" = true ]; then
        flock -u 8 || true
        exec 8>&-
    fi

    # --- Summary ---
    echo ""
    if [ "$NFTABLES_OK" = true ]; then
        print_success "nftables firewall setup completed"
        print_message "  Service: nftables.service"
        print_message "  Config:  /etc/nftables.conf"
        if [ ! -z "$NFTABLES_PROFILE" ] && [ "$INSTALL_NFTABLES_CONF" != "skipped" ]; then
            print_message "  Profile: ${NFTABLES_PROFILE} (${NFTABLES_CONF_FILE})"
        fi
        print_message "  Manage:  systemctl {start|stop|restart|status} nftables"
        print_message "  Rules:   nft list ruleset"
    else
        print_error "nftables setup failed — check errors above"
    fi
    echo ""
else
    if [ "$CONFIGURE_UFW" != "y" ] && [ "$CONFIGURE_UFW" != "Y" ]; then
        print_message "Skipping nftables (not requested)"
    fi
fi

# ============================================
# INSTALL NFT-DOCKER-WATCH SERVICE
# ============================================

if is_yes "$INSTALL_NFT_DOCKER_WATCH" && [ "${NFTABLES_OK:-false}" = true ]; then
    echo ""
    print_header "═══════════════════════════════════════════════════"
    print_header "   Installing nft-docker-watch service"
    print_header "═══════════════════════════════════════════════════"
    echo ""

    NFT_WATCH_INSTALLER_SHA256="b4c93556d95e20168d1a43f6e55298391728a8e24f4d401a3ea80537522600e3"
    NFT_WATCH_INSTALLER_URL="https://raw.githubusercontent.com/civisrom/debian-ubuntu-setup/${SYSTEM_SETUP_REPOSITORY_REF}/install-nft-docker-watch.sh"
    NFT_WATCH_LOCAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
    NFT_WATCH_INSTALLER="${NFT_WATCH_LOCAL_DIR}/install-nft-docker-watch.sh"

    if [ ! -f "$NFT_WATCH_INSTALLER" ]; then
        create_temp_dir "nft-watch-installer" || NFT_WATCH_INSTALLER=""
        if [ -n "$NFT_WATCH_INSTALLER" ]; then
            NFT_WATCH_INSTALLER="${SYSTEM_SETUP_CREATED_TEMP_DIR}/install-nft-docker-watch.sh"
            if ! download_url_ipv4 "$NFT_WATCH_INSTALLER_URL" "$NFT_WATCH_INSTALLER"; then
                print_error "Failed to download nft-docker-watch installer"
                NFT_WATCH_INSTALLER=""
            fi
        fi
    fi

    if [ -n "$NFT_WATCH_INSTALLER" ] && [ -s "$NFT_WATCH_INSTALLER" ]; then
        NFT_WATCH_ACTUAL_SHA256=$(sha256sum "$NFT_WATCH_INSTALLER" | awk '{print $1}')
        if [ "$NFT_WATCH_ACTUAL_SHA256" != "$NFT_WATCH_INSTALLER_SHA256" ]; then
            print_error "nft-docker-watch installer SHA256 mismatch; refusing root execution"
        elif ! validate_shell_script "$NFT_WATCH_INSTALLER" bash; then
            print_error "nft-docker-watch installer syntax validation failed"
        elif bash "$NFT_WATCH_INSTALLER" install; then
            print_success "nft-docker-watch installation completed"
        else
            print_error "nft-docker-watch installation failed"
        fi
    else
        print_error "nft-docker-watch installer is unavailable"
    fi
    echo ""
else
    if { [ "$ENABLE_NFTABLES" = "y" ] || [ "$ENABLE_NFTABLES" = "Y" ]; } && \
       { [ "$INSTALL_DOCKER" = "y" ] || [ "$INSTALL_DOCKER" = "Y" ]; }; then
        print_message "Skipping nft-docker-watch (not requested)"
    fi
fi

# ============================================
# CONFIGURE SWAP (SWAPFILE + ZRAM)
# ============================================

if [ "$CONFIGURE_SWAP" = "y" ] || [ "$CONFIGURE_SWAP" = "Y" ]; then
    echo ""
    print_header "═══════════════════════════════════════════════════"
    print_header "   Configuring Swap (swapfile + zram)"
    print_header "═══════════════════════════════════════════════════"
    echo ""

    # Ensure zram kernel module is available (missing on some VPS with minimal kernel)
    if ! find "/lib/modules/$(uname -r)" -name '*zram*' 2>/dev/null | grep -q .; then
        KERNEL_HAS_ZRAM=$(grep -c "^CONFIG_ZRAM=m" "/boot/config-$(uname -r)" 2>/dev/null || true)
        if [ "${KERNEL_HAS_ZRAM:-0}" -gt 0 ]; then
            print_warning "zram module not found — CONFIG_ZRAM=m detected, installing linux-modules-extra..."
            apt-get install -y "linux-modules-extra-$(uname -r)" 2>&1 | tail -3 || \
                print_warning "Failed to install linux-modules-extra, zram may not work"
        fi
    fi
    # Load zram module now if available (avoids reboot requirement)
    if find "/lib/modules/$(uname -r)" -name '*zram*' 2>/dev/null | grep -q .; then
        if modprobe zram 2>/dev/null; then
            print_message "zram module loaded successfully"
        else
            print_warning "zram module could not be loaded; swap installer will check available support"
        fi
    else
        print_warning "zram module unavailable — zramswap will be skipped by swap-setup.sh"
    fi

    SWAP_SCRIPT_COMMIT="1409e6f424ff7bea57c450dfa878e498645e71c5"
    SWAP_SCRIPT_SHA256="175011c596336598e72dc2a75c50aa49649ae464fcd275fb780ae88a83ac7e92"
    SWAP_SCRIPT_URL="https://raw.githubusercontent.com/civisrom/swapfile-script/${SWAP_SCRIPT_COMMIT}/swap-setup.sh"
    if create_temp_dir "swap-setup"; then
        SWAP_TMP_DIR="$SYSTEM_SETUP_CREATED_TEMP_DIR"
    else
        SWAP_TMP_DIR=""
    fi
    SWAP_SCRIPT_PATH="${SWAP_TMP_DIR}/swap-setup.sh"
    SWAP_INSTALL_PATH="/usr/local/sbin/swap-setup.sh"
    SWAP_SCRIPT_READY=false

    print_message "Downloading swap-setup.sh..."
    if [ -n "$SWAP_TMP_DIR" ] && download_verified_url "$SWAP_SCRIPT_URL" "$SWAP_SCRIPT_PATH" "$SWAP_SCRIPT_SHA256"; then
        if validate_shell_script "$SWAP_SCRIPT_PATH" bash; then
            SWAP_SCRIPT_READY=true
        else
            print_error "Refusing to run invalid swap-setup.sh"
        fi
    fi

    if [ "$SWAP_SCRIPT_READY" = true ]; then
        print_message "Swap script downloaded successfully"
        chmod +x "$SWAP_SCRIPT_PATH"

        # Install to system path for future use
        install -m 0755 -o root -g root "$SWAP_SCRIPT_PATH" "$SWAP_INSTALL_PATH" || {
            print_error "Failed to install swap management script"
            exit 1
        }
        print_message "Installed to $SWAP_INSTALL_PATH for future use"

        # swap-setup.sh installs zram-tools, so let any background apt run finish
        SWAP_SETUP_EXIT_CODE=0
        wait_for_apt_locks || SWAP_SETUP_EXIT_CODE=1
        if [ "$SWAP_SETUP_EXIT_CODE" -ne 0 ]; then
            print_error "Skipping swap setup: the APT locks never became available"
        elif [ "$SWAP_INTERACTIVE" = true ]; then
            print_message "Starting swap interactive wizard..."
            if bash "$SWAP_SCRIPT_PATH"; then
                :
            else
                SWAP_SETUP_EXIT_CODE=$?
            fi
        else
            print_message "Running swap auto-detect mode..."
            if bash "$SWAP_SCRIPT_PATH" --yes; then
                :
            else
                SWAP_SETUP_EXIT_CODE=$?
            fi
        fi

        case "$SWAP_SETUP_EXIT_CODE" in
            130|143)
                print_error "Swap setup was interrupted (exit code: $SWAP_SETUP_EXIT_CODE)"
                exit "$SWAP_SETUP_EXIT_CODE"
                ;;
        esac

        # Cleanup temp file
        rm -f "$SWAP_SCRIPT_PATH"

        echo ""
        print_header "═══════════════════════════════════════════════════"
        if [ "$SWAP_SETUP_EXIT_CODE" -eq 0 ] && swapon --show --noheadings | grep -q .; then
            SWAP_SETUP_OK=true
            print_message "Swap configuration completed; active swap verified"
        elif [ "$SWAP_SETUP_EXIT_CODE" -eq 0 ]; then
            print_error "Swap installer exited successfully but no active swap was found"
        else
            print_error "Swap setup encountered an error (exit code: $SWAP_SETUP_EXIT_CODE)"
            print_warning "Swap configuration may be incomplete; check status before relying on it"
        fi
        print_message "You can manage swap later: sudo swap-setup.sh --status"
        print_header "═══════════════════════════════════════════════════"
        echo ""
    else
        print_error "Failed to download or validate swap-setup.sh"
        print_message "You can manually install it later:"
        print_message "  Review the pinned source commit: $SWAP_SCRIPT_COMMIT"
    fi
else
    print_message "Skipping swap configuration (not requested)"
fi

# ============================================
# RUN BBR NETWORK OPTIMIZER
# ============================================

if [ "$RUN_BBR_OPTIMIZER" = "y" ] || [ "$RUN_BBR_OPTIMIZER" = "Y" ]; then
    echo ""
    print_header "═══════════════════════════════════════════════════"
    print_header "   Running BBR Network Optimizer"
    print_header "═══════════════════════════════════════════════════"
    echo ""
    
    BBR_SCRIPT_COMMIT="0007bdbd3c5014b307354b12f53ca3de086d9469"
    BBR_SCRIPT_SHA256="99f315d6f3b36c46c3a3b5d394355a3bc346fa39d3d0ea7c7f696d734d3f291f"
    BBR_SCRIPT_URL="https://raw.githubusercontent.com/civisrom/Linux_NetworkOptimizer/${BBR_SCRIPT_COMMIT}/bbr.sh"
    if create_temp_dir "bbr-optimizer"; then
        BBR_TMP_DIR="$SYSTEM_SETUP_CREATED_TEMP_DIR"
    else
        BBR_TMP_DIR=""
    fi
    BBR_SCRIPT_PATH="${BBR_TMP_DIR}/bbr_optimizer.sh"
    BBR_WRAPPER_PATH="${BBR_TMP_DIR}/bbr_wrapper.sh"
    BBR_SCRIPT_READY=false
    
    print_message "Downloading BBR Network Optimizer script..."
    if [ -n "$BBR_TMP_DIR" ] && download_verified_url "$BBR_SCRIPT_URL" "$BBR_SCRIPT_PATH" "$BBR_SCRIPT_SHA256"; then
        if validate_shell_script "$BBR_SCRIPT_PATH" bash; then
            BBR_SCRIPT_READY=true
        else
            print_error "Refusing to run invalid BBR Network Optimizer script"
        fi
    fi

    if [ "$BBR_SCRIPT_READY" = true ]; then
        print_message "BBR script downloaded successfully"
        chmod +x "$BBR_SCRIPT_PATH"
        
        # Create a modified version of the BBR script with optional functions
        print_message "Configuring BBR script options..."
        
        # Create a wrapper script that will call functions based on user's choices
        cat > "$BBR_WRAPPER_PATH" << 'EOFWRAPPER'
#!/bin/bash

# Define print_message in case bbr.sh doesn't provide it
print_message() {
    echo -e "\033[0;32m[INFO]\033[0m $1"
}

# Source the original BBR script (may override print_message)
if [ -z "${1:-}" ] || [ ! -f "$1" ]; then
    echo "BBR optimizer script path is missing or invalid" >&2
    exit 1
fi
# shellcheck source=/dev/null
source "$1"
shift

# Run selected functions based on parameters
if [ "${1:-}" = "force_ipv4" ]; then
    force_ipv4_apt || exit $?
fi

if [ "${2:-}" = "full_update" ]; then
    full_update_upgrade || exit $?
fi

if [ "${3:-}" = "fix_hosts" ]; then
    fix_etc_hosts || exit $?
fi

if [ "${4:-}" = "fix_dns" ]; then
    fix_dns || exit $?
fi

# Always run the main optimization — this handles network tuning via sysctl
# with adaptive RAM-based profiles (low/mid/high), including:
# BBR congestion control, qdisc (fq_codel/cake), TCP buffers, VM settings
# system-setup.sh only writes IPv6/security params when BBR is enabled
print_message "Applying BBR adaptive network optimizations..."
intelligent_settings
EOFWRAPPER
        
        chmod +x "$BBR_WRAPPER_PATH"
        
        # Prepare parameters based on user choices
        PARAM1="skip"
        PARAM2="skip"
        PARAM3="skip"
        PARAM4="skip"
        
        if [ "$BBR_FORCE_IPV4" = "y" ] || [ "$BBR_FORCE_IPV4" = "Y" ]; then
            PARAM1="force_ipv4"
        fi
        
        if [ "$BBR_FULL_UPDATE" = "y" ] || [ "$BBR_FULL_UPDATE" = "Y" ]; then
            PARAM2="full_update"
        fi
        
        if [ "$BBR_FIX_HOSTS" = "y" ] || [ "$BBR_FIX_HOSTS" = "Y" ]; then
            PARAM3="fix_hosts"
        fi
        
        if [ "$BBR_FIX_DNS" = "y" ] || [ "$BBR_FIX_DNS" = "Y" ]; then
            # Skip BBR DNS fix if systemd-resolved is configured (would conflict)
            if [ "$CONFIGURE_RESOLVED" = "y" ] || [ "$CONFIGURE_RESOLVED" = "Y" ]; then
                print_warning "Skipping BBR fix_dns — systemd-resolved is configured separately"
            else
                PARAM4="fix_dns"
            fi
        fi
        
        print_message "Running BBR Network Optimizer with selected options..."
        print_message "Options: Force IPv4: $PARAM1, Full Update: $PARAM2, Fix Hosts: $PARAM3, Fix DNS: $PARAM4"
        echo ""

        # The optimizer runs apt-get update/upgrade of its own.
        wait_for_apt_locks || print_warning "Continuing with busy APT locks; the optimizer may fail to install packages"

        if bash "$BBR_WRAPPER_PATH" "$BBR_SCRIPT_PATH" "$PARAM1" "$PARAM2" "$PARAM3" "$PARAM4"; then
            BBR_OK=true
            echo ""
            print_header "═══════════════════════════════════════════════════"
            print_message "BBR Network Optimizer completed"
            print_header "═══════════════════════════════════════════════════"
            echo ""
        else
            print_error "BBR Network Optimizer failed"
        fi
    else
        print_error "Failed to download or validate BBR Network Optimizer script"
        print_message "You can manually run it later from: $BBR_SCRIPT_URL"
    fi
else
    print_message "Skipping BBR Network Optimizer (not requested)"
fi

# ============================================
# CONFIGURE SYSCTL
# ============================================
# NOTE: This section is intentionally placed AFTER all network-dependent
# operations (Docker, Go, ipset, pip, MOTD, UFW rules, swap, BBR, opt.7z).
# Reason: sysctl disables IPv6 at runtime, which breaks DNS resolution
# on systems where the resolver depends on IPv6 upstream DNS.
# By running this last, we avoid the need for fragile DNS recovery hacks.

# Configure sysctl
if [ "$CONFIGURE_SYSCTL" = "y" ] || [ "$CONFIGURE_SYSCTL" = "Y" ]; then
    print_message "Configuring system parameters (sysctl)..."

    SYSCTL_MAIN_FILE="/etc/sysctl.conf"
    SYSCTL_TARGET_FILE="$SYSCTL_MAIN_FILE"
    SYSCTL_DROPIN_FILE="/etc/sysctl.d/99-system-setup.conf"

    # Use the traditional /etc/sysctl.conf when it exists. Minimal images may
    # omit it; then keep all script-managed parameters in a sysctl.d drop-in.
    if [ -f "$SYSCTL_MAIN_FILE" ]; then
        print_message "Detected ${SYSCTL_MAIN_FILE}; using standard sysctl.conf configuration"
    else
        mkdir -p /etc/sysctl.d
        SYSCTL_TARGET_FILE="$SYSCTL_DROPIN_FILE"
        print_message "${SYSCTL_MAIN_FILE} not found; using ${SYSCTL_TARGET_FILE}"
    fi

    # Backup original sysctl configuration file
    if [ -f "$SYSCTL_TARGET_FILE" ]; then
        cp "$SYSCTL_TARGET_FILE" "${SYSCTL_TARGET_FILE}.backup.$(date +%Y%m%d-%H%M%S)~"
        print_message "Original ${SYSCTL_TARGET_FILE} backed up"
    fi

    # Preserve the existing file and replace only our managed block.
    SYSCTL_TMP=$(mktemp)
    if [ -f "$SYSCTL_TARGET_FILE" ]; then
        strip_managed_block "$SYSCTL_TARGET_FILE" sysctl > "$SYSCTL_TMP" || {
            print_error "Unbalanced managed sysctl markers; existing configuration was preserved"
            exit 1
        }
    else
        : > "$SYSCTL_TMP"
    fi

    SYSCTL_MANAGED_BLOCK=""

    # Mode 1 (basic): static parameters written directly to the selected sysctl file
    # Mode 2 (full): bbr.sh handles all sysctl tuning (no params written here)
    if [ "$SYSCTL_MODE" = "2" ]; then
        # === Full mode: bbr.sh manages all network/sysctl parameters ===
        print_message "Skipping sysctl params — all tuning handled by Linux NetworkOptimizer (bbr.sh)"
    else
        # === Basic mode: full static parameters ===
        print_message "Applying basic sysctl configuration (static parameters)"
        SYSCTL_MANAGED_BLOCK="${SYSCTL_MANAGED_BLOCK}

# IPv6 Disable
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1

# Network Tuning (BBR + TCP/UDP optimization)
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.wmem_default = 2097152
net.core.netdev_max_backlog = 10240
net.core.somaxconn = 8192

# Security
net.ipv4.tcp_syncookies = 1

# TCP Optimization
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_max_syn_backlog = 10240
net.ipv4.tcp_max_tw_buckets = 5000
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_mem = 25600 51200 102400
net.ipv4.udp_mem = 25600 51200 102400
net.ipv4.tcp_rmem = 16384 262144 8388608
net.ipv4.tcp_wmem = 32768 524288 16777216
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_slow_start_after_idle = 0

# System Limits
fs.inotify.max_user_instances = 8192
net.ipv4.ip_local_port_range = 1024 45000

# Netfilter
net.netfilter.nf_conntrack_max = 131072
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 30
net.netfilter.nf_conntrack_tcp_timeout_established = 86400
net.netfilter.nf_conntrack_tcp_loose = 0
"
    fi

    # === IP forwarding (appended separately to not break existing entries) ===
    if [ "$ENABLE_IP_FORWARD" = "y" ] || [ "$ENABLE_IP_FORWARD" = "Y" ]; then
        SYSCTL_MANAGED_BLOCK="${SYSCTL_MANAGED_BLOCK}

# IP Forwarding (Docker, NAT, VPN, routing)
net.ipv4.ip_forward = 1
"
        print_message "IP forwarding enabled (net.ipv4.ip_forward = 1)"
    else
        print_message "IP forwarding not enabled (skipped by user)"
    fi

    {
        cat "$SYSCTL_TMP"
        if [ -n "$SYSCTL_MANAGED_BLOCK" ]; then
            [ -s "$SYSCTL_TMP" ] && printf '\n'
            printf '%s\n' "# BEGIN system-setup.sh managed sysctl"
            printf '%s\n' "$SYSCTL_MANAGED_BLOCK"
            printf '%s\n' "# END system-setup.sh managed sysctl"
        fi
    } > "${SYSCTL_TARGET_FILE}.new"
    rm -f "$SYSCTL_TMP"
    write_file_atomic "$SYSCTL_TARGET_FILE" 0644 root:root < "${SYSCTL_TARGET_FILE}.new" || {
        print_error "Failed to install sysctl configuration"
        exit 1
    }
    rm -f -- "${SYSCTL_TARGET_FILE}.new"
    print_message "sysctl configuration written to ${SYSCTL_TARGET_FILE} (mode: $([ "$SYSCTL_MODE" = "2" ] && echo "full/BBR" || echo "basic/static"))"

    # Apply sysctl settings (|| true to prevent set -e exit on unsupported params)
    print_message "Applying sysctl settings from ${SYSCTL_TARGET_FILE}..."
    if sysctl -p "$SYSCTL_TARGET_FILE"; then
        SYSCTL_OK=true
    else
        print_error "Some sysctl parameters failed; review kernel support and permissions"
    fi

    # Install systemd service for sysctl enforcement on boot
    if [ "$INSTALL_SYSCTL_SERVICE" = "y" ] || [ "$INSTALL_SYSCTL_SERVICE" = "Y" ]; then
        print_message "Installing sysctl enforcement service (disable-ipv6.service)..."
        cat > /etc/systemd/system/disable-ipv6.service << EOF
[Unit]
Description=Apply sysctl settings
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/sbin/sysctl -p ${SYSCTL_TARGET_FILE}
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        if systemctl enable --now disable-ipv6.service; then
            SYSCTL_SERVICE_OK=true
            print_message "sysctl enforcement service installed and enabled"
        else
            print_error "Failed to enable/start sysctl enforcement service"
        fi
    fi

    # Minimal DNS recovery: ensure resolv.conf has IPv4 DNS after IPv6 disable
    # Skip if systemd-resolved will be configured next (avoid creating conflicting drop-ins)
    if [ "$CONFIGURE_RESOLVED" = "y" ] || [ "$CONFIGURE_RESOLVED" = "Y" ]; then
        print_message "Skipping DNS recovery — systemd-resolved will be configured next"
    else
        ensure_dns_works "sysctl-ipv6-disable"
    fi
else
    print_message "Skipping sysctl configuration (not requested)"
fi

# ============================================
# CONFIGURE SYSTEMD-RESOLVED
# ============================================
# NOTE: Placed after sysctl (which disables IPv6 and recovers DNS)
# so resolved is configured with final DNS settings.
# Steps:
#   1. Install libnss-resolve (updates /etc/nsswitch.conf automatically)
#   2. Write /etc/systemd/resolved.conf
#   3. Preserve and replace /etc/resolv.conf with a symlink
#   4. Enable and restart systemd-resolved

configure_systemd_resolved() {
    local config_dir=/etc/systemd/resolved.conf.d
    local config_file="$config_dir/99-system-setup.conf"
    local resolv_file=/etc/resolv.conf backup_dir
    local had_config=false had_resolv=false old_active=false old_enabled
    local dot=no stub=yes ready=true target=/run/systemd/resolve/stub-resolv.conf

    if ! python3 - "$RESOLVED_DNS" <<'PYDNS'
import ipaddress
import sys
try:
    address, *hostname = sys.argv[1].split('#')
    ipaddress.ip_address(address)
    if hostname and (len(hostname) != 1 or not hostname[0] or
                     any(c not in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-' for c in hostname[0])):
        raise ValueError('invalid TLS hostname')
except ValueError:
    sys.exit(1)
PYDNS
    then
        print_error "Invalid DNS server address"
        return 1
    fi

    if [[ "$RESOLVED_DNS" == 127.* ]] &&
       ! ss -H -lntu 2>/dev/null | awk '{print $5}' | grep -Eq '(^127\.0\.0\.1:53$|^0\.0\.0\.0:53$|^\*:53$)'; then
        print_error "Selected local DNS server has no listener on port 53"
        return 1
    fi

    # Capture the manager-owned symlink itself, not only its current target.
    install -d -m 0700 /var/backups || return 1
    backup_dir=$(mktemp -d /var/backups/system-setup-resolved.XXXXXX) || return 1
    if [ -e "$config_file" ] || [ -L "$config_file" ]; then
        cp -a -- "$config_file" "$backup_dir/dropin.conf" || return 1
        had_config=true
    fi
    if [ -e "$resolv_file" ] || [ -L "$resolv_file" ]; then
        cp -a -- "$resolv_file" "$backup_dir/resolv.conf" || return 1
        had_resolv=true
    fi
    systemctl is-active --quiet systemd-resolved && old_active=true
    old_enabled=$(systemctl is-enabled systemd-resolved 2>/dev/null || true)

    # Explicitly install the daemon as well as its NSS module on minimal images.
    if ! apt-get install -y systemd-resolved libnss-resolve; then
        print_error "Could not install systemd-resolved and libnss-resolve"
        ready=false
    fi
    mkdir -p "$config_dir" || ready=false
    is_yes "$RESOLVED_DNS_OVER_TLS" && dot=yes
    if is_yes "$RESOLVED_STUB_LISTENER_OFF"; then
        stub=no
        target=/run/systemd/resolve/resolv.conf
    fi

    # A drop-in preserves administrator settings in resolved.conf. Reset the
    # accumulated DNS list so our earlier emergency ipv4-dns.conf cannot win.
    if [ "$ready" = true ] && write_file_atomic "$config_file" 0644 root:root <<REOF
[Resolve]
DNS=
DNS=${RESOLVED_DNS}
FallbackDNS=
DNSOverTLS=${dot}
DNSStubListener=${stub}
REOF
    then
        if systemctl enable systemd-resolved && systemctl restart systemd-resolved &&
           systemctl is-active --quiet systemd-resolved && [ -s "$target" ] &&
           ln -sfn -- "$target" "$resolv_file" &&
           { getent ahostsv4 deb.debian.org >/dev/null || getent ahostsv4 archive.ubuntu.com >/dev/null; }; then
            print_success "systemd-resolved configured; service and DNS resolution verified"
            print_message "Managed DNS config: $config_file (backup: $backup_dir)"
            return 0
        fi
    fi

    print_error "systemd-resolved configuration failed; restoring previous resolver state"
    if [ "$had_config" = true ]; then
        cp -a --remove-destination -- "$backup_dir/dropin.conf" "$config_file" || return 1
    else
        rm -f -- "$config_file"
    fi
    if [ "$had_resolv" = true ]; then
        cp -a --remove-destination -- "$backup_dir/resolv.conf" "$resolv_file" || return 1
    else
        rm -f -- "$resolv_file"
    fi
    if [ "$old_active" = true ]; then
        systemctl restart systemd-resolved || print_error "Could not restart previous resolver configuration"
    else
        systemctl stop systemd-resolved || true
    fi
    case "$old_enabled" in
        enabled) systemctl enable systemd-resolved >/dev/null 2>&1 || true ;;
        masked) systemctl mask systemd-resolved >/dev/null 2>&1 || true ;;
        *) systemctl disable systemd-resolved >/dev/null 2>&1 || true ;;
    esac
    return 1
}

if is_yes "$CONFIGURE_RESOLVED"; then
    print_message "Configuring systemd-resolved..."
    ensure_dns_works "pre-systemd-resolved"
    if configure_systemd_resolved; then
        RESOLVED_OK=true
    else
        print_error "systemd-resolved setup did not complete"
    fi
else
    print_message "Skipping systemd-resolved configuration (not requested)"
fi

# ============================================
# DISABLE IPv6 VIA GRUB (Debian and Ubuntu)
# ============================================
# Adds 'ipv6.disable=1' to BOTH GRUB_CMDLINE_LINUX_DEFAULT and
# GRUB_CMDLINE_LINUX. The DEFAULT variant only applies to the normal boot
# menu entry; the bare _LINUX variant applies to ALL entries (including
# recovery/single-user), so setting both is the reliable form.

if { [ "$OS" = "debian" ] || [ "$OS" = "ubuntu" ]; } && \
   { [ "$DISABLE_IPV6_GRUB" = "y" ] || [ "$DISABLE_IPV6_GRUB" = "Y" ]; }; then
    print_message "Disabling IPv6 at kernel level via GRUB..."

    GRUB_CONFIG="/etc/default/grub"

    if [ ! -f "$GRUB_CONFIG" ]; then
        print_error "GRUB config file not found: $GRUB_CONFIG"
        print_warning "Skipping IPv6 GRUB disable"
    elif ! command -v update-grub >/dev/null 2>&1; then
        print_error "update-grub not found — system may use systemd-boot or similar"
        print_warning "Skipping IPv6 GRUB disable"
    else
        GRUB_BACKUP="${GRUB_CONFIG}.backup.$(date +%Y%m%d-%H%M%S)~"
        cp -p -- "$GRUB_CONFIG" "$GRUB_BACKUP" || { print_error "Cannot back up GRUB configuration"; exit 1; }
        GRUB_STAGE=$(mktemp) || exit 1
        GRUB_UPDATE_LOG=$(mktemp "${TMPDIR:-/tmp}/grub-update.XXXXXX") || exit 1
        if prepare_grub_ipv6 "$GRUB_CONFIG" > "$GRUB_STAGE" &&
           write_file_atomic "$GRUB_CONFIG" < "$GRUB_STAGE" &&
           update-grub > "$GRUB_UPDATE_LOG" 2>&1; then
            GRUB_OK=true
            print_success "GRUB configuration updated successfully"
            print_warning "IPv6 will be disabled at kernel level after reboot"
        else
            print_error "Failed to prepare or update GRUB; restoring this run's backup"
            if cp -p -- "$GRUB_BACKUP" "$GRUB_CONFIG" && update-grub >> "$GRUB_UPDATE_LOG" 2>&1; then
                print_warning "Previous GRUB configuration restored and regenerated"
            else
                print_error "GRUB rollback failed; review $GRUB_UPDATE_LOG before rebooting"
            fi
        fi
        cat "$GRUB_UPDATE_LOG"
        rm -f -- "$GRUB_STAGE"

        # Show resulting state
        print_message "Resulting GRUB cmdline lines:"
        grep -E '^GRUB_CMDLINE_LINUX(_DEFAULT)?=' "$GRUB_CONFIG" | sed 's/^/  /'
    fi
    echo ""
else
    if [ "$OS" = "debian" ] || [ "$OS" = "ubuntu" ]; then
        print_message "Skipping IPv6 GRUB disable (not requested)"
    fi
fi

# ============================================
# COMMENT IPv6 IN /etc/network/interfaces
# ============================================

if [ "$COMMENT_IPV6_INTERFACES" = "y" ] || [ "$COMMENT_IPV6_INTERFACES" = "Y" ]; then
    print_message "Commenting out IPv6 configuration in /etc/network/interfaces..."

    INTERFACES_FILE="/etc/network/interfaces"

    if [ ! -f "$INTERFACES_FILE" ]; then
        print_warning "File $INTERFACES_FILE not found"
        print_message "Your system may use netplan or NetworkManager instead"
        print_message "Skipping /etc/network/interfaces IPv6 configuration"
    else
        # Backup original interfaces file
        cp "$INTERFACES_FILE" "${INTERFACES_FILE}.backup.$(date +%Y%m%d-%H%M%S)~"
        print_message "Original $INTERFACES_FILE backed up"

        # Check if there are any inet6 lines
        if grep -q "inet6" "$INTERFACES_FILE"; then
            print_message "Found IPv6 configuration in $INTERFACES_FILE"

            # Create temporary file
            TEMP_FILE=$(mktemp)

            # Comment out all lines containing inet6 or related to IPv6
            # This includes iface lines with inet6 and their parameters
            # Also removes IPv6 addresses from dns-nameservers in IPv4 blocks
            awk '
            /^[[:space:]]*iface.*inet6/ {
                # This is an inet6 interface definition
                print "#" $0
                in_inet6_block = 1
                in_inet4_block = 0
                next
            }
            /^[[:space:]]*iface.*inet[[:space:]]/ {
                # This is an inet4 interface definition
                in_inet4_block = 1
                in_inet6_block = 0
                print $0
                next
            }
            in_inet6_block {
                # We are in an inet6 block
                if (/^[[:space:]]*$/ || /^[[:space:]]*#/ || /^[[:space:]]*auto/ || /^[[:space:]]*iface/) {
                    # End of inet6 block
                    in_inet6_block = 0
                    print $0
                } else {
                    # This line is part of inet6 configuration
                    print "#" $0
                }
                next
            }
            in_inet4_block && /^[[:space:]]*dns-nameservers/ {
                # In IPv4 block: remove IPv6 addresses from dns-nameservers
                # Extract leading whitespace
                match($0, /^[[:space:]]*/)
                leading = substr($0, RSTART, RLENGTH)
                # Build new line with only IPv4 addresses (skip anything containing ":")
                result = leading "dns-nameservers"
                has_ipv4 = 0
                for (i = 2; i <= NF; i++) {
                    if ($i !~ /:/) {
                        result = result " " $i
                        has_ipv4 = 1
                    }
                }
                if (has_ipv4) {
                    print result
                }
                # If no IPv4 addresses remain, skip the line entirely
                next
            }
            in_inet4_block {
                # Check if we are leaving the inet4 block
                if (/^[[:space:]]*$/ || /^[[:space:]]*auto/ || /^[[:space:]]*iface/) {
                    in_inet4_block = 0
                }
                print $0
                next
            }
            {
                # Regular line, print as is
                print $0
            }
            ' "$INTERFACES_FILE" > "$TEMP_FILE"

            # Verify the temporary file is not empty
            if [ -s "$TEMP_FILE" ]; then
                # Replace original file
                write_file_atomic "$INTERFACES_FILE" < "$TEMP_FILE" || { print_error "Failed to update interfaces file"; exit 1; }
                rm -f -- "$TEMP_FILE"
                INTERFACES_OK=true
                print_success "IPv6 configuration commented out in $INTERFACES_FILE"

                echo ""
                print_message "Modified $INTERFACES_FILE preview:"
                print_header "─────────────────────────────────────────────"
                grep -A 2 -B 2 "inet6" "$INTERFACES_FILE" 2>/dev/null || print_message "No IPv6 lines remaining (all commented)"
                print_header "─────────────────────────────────────────────"
                echo ""

                # Remove IPv6 nameservers from /etc/resolv.conf
                # Skip if systemd-resolved manages resolv.conf (it's a symlink)
                RESOLV_FILE="/etc/resolv.conf"
                if [ -L "$RESOLV_FILE" ]; then
                    print_message "Skipping resolv.conf cleanup — managed by systemd-resolved"
                elif [ -f "$RESOLV_FILE" ]; then
                    if grep -qE "^[[:space:]]*nameserver[[:space:]]+[0-9a-fA-F]*:" "$RESOLV_FILE"; then
                        cp "$RESOLV_FILE" "${RESOLV_FILE}.backup.$(date +%Y%m%d-%H%M%S)~"
                        print_message "Original $RESOLV_FILE backed up"
                        TEMP_RESOLV=$(mktemp)
                        # Remove lines with IPv6 nameservers (addresses containing ":")
                        grep -vE "^[[:space:]]*nameserver[[:space:]]+[0-9a-fA-F]*:" "$RESOLV_FILE" > "$TEMP_RESOLV"
                        # Check if any IPv4 nameservers remain after removing IPv6 ones
                        if grep -qE "^[[:space:]]*nameserver[[:space:]]+[0-9]+\.[0-9]+" "$TEMP_RESOLV" && [ -s "$TEMP_RESOLV" ]; then
                            write_file_atomic "$RESOLV_FILE" 0644 root:root < "$TEMP_RESOLV" || exit 1
                            rm -f -- "$TEMP_RESOLV"
                            print_success "IPv6 nameservers removed from $RESOLV_FILE"
                        else
                            # No IPv4 nameservers remain - add fallback DNS
                            print_warning "No IPv4 nameservers would remain, adding fallback DNS"
                            grep -vE "^[[:space:]]*nameserver" "$RESOLV_FILE" > "$TEMP_RESOLV" 2>/dev/null || true
                            echo "nameserver 1.1.1.1" >> "$TEMP_RESOLV"
                            echo "nameserver 8.8.8.8" >> "$TEMP_RESOLV"
                            write_file_atomic "$RESOLV_FILE" 0644 root:root < "$TEMP_RESOLV" || exit 1
                            rm -f -- "$TEMP_RESOLV"
                            print_success "IPv6 nameservers replaced with Cloudflare and Google DNS"
                        fi
                    else
                        print_message "No IPv6 nameservers found in $RESOLV_FILE"
                    fi
                fi

                print_warning "Network configuration changed. You may need to restart networking:"
                print_message "  sudo systemctl restart networking"
                print_message "  OR reboot the system"
            else
                print_error "Failed to create modified interfaces file"
                rm -f "$TEMP_FILE"
                # Restore from backup
                LATEST_BACKUP=$(ls -t ${INTERFACES_FILE}.backup.*~ 2>/dev/null | head -1)
                if [ ! -z "$LATEST_BACKUP" ]; then
                    cp "$LATEST_BACKUP" "$INTERFACES_FILE"
                    print_message "Restored from backup"
                fi
            fi
        else
            INTERFACES_OK=true
            print_message "No IPv6 configuration found in $INTERFACES_FILE"
            print_message "File is already without IPv6 or uses different format"
        fi
    fi
    echo ""
else
    print_message "Skipping IPv6 commenting in /etc/network/interfaces (not requested)"
fi

# ============================================
# DISABLE IPv6 IN NETPLAN (Ubuntu default, also possible on Debian)
# ============================================
# Edits every /etc/netplan/*.yaml|*.yml via python3+pyyaml (safe AST edit, not sed).
# For each interface across ethernets/wifis/bonds/bridges/vlans/tunnels:
#   - drop IPv6 addresses from 'addresses'
#   - drop 'gateway6'
#   - drop IPv6 entries from 'nameservers.addresses'
#   - drop routes whose 'to' or 'via' contain ':'
#   - set dhcp6: false, accept-ra: false, link-local: [ipv4]
# Validates the result with 'netplan generate' (writes to /run, harmless until apply).
# Rolls back on failure. NEVER auto-applies — avoids killing SSH on IPv6-routed boxes.

if [ "$DISABLE_IPV6_NETPLAN" = "y" ] || [ "$DISABLE_IPV6_NETPLAN" = "Y" ]; then
    print_message "Disabling IPv6 in /etc/netplan/*.yaml ..."

    NETPLAN_DIR="/etc/netplan"

    if [ ! -d "$NETPLAN_DIR" ]; then
        print_warning "$NETPLAN_DIR not found — system does not use netplan"
        print_message "Skipping netplan IPv6 disable"
    elif ! command -v netplan >/dev/null 2>&1; then
        print_warning "'netplan' command not found — skipping"
    elif ! command -v python3 >/dev/null 2>&1; then
        print_error "python3 not available — required for safe YAML editing"
        print_message "Skipping netplan IPv6 disable"
    else
        # Ensure pyyaml is available. On netplan-using systems python3-yaml is
        # already a dep of netplan.io, but defend against minimal images.
        if ! python3 -c "import yaml" 2>/dev/null; then
            print_message "Installing python3-yaml (required for netplan editing)..."
            apt-get install -y python3-yaml >/dev/null 2>&1 || \
                print_warning "Failed to install python3-yaml"
        fi

        if ! python3 -c "import yaml" 2>/dev/null; then
            print_error "python3 yaml module unavailable — skipping netplan IPv6 disable"
        else
            # Collect netplan files
            NETPLAN_FILES=()
            while IFS= read -r -d '' f; do
                NETPLAN_FILES+=("$f")
            done < <(find "$NETPLAN_DIR" -maxdepth 1 -type f \
                          \( -name '*.yaml' -o -name '*.yml' \) -print0 | sort -z)

            if [ "${#NETPLAN_FILES[@]}" -eq 0 ]; then
                print_warning "No .yaml/.yml files found in $NETPLAN_DIR"
            else
                NETPLAN_TS=$(date +%Y%m%d-%H%M%S)
                NETPLAN_CHANGED_FILES=()

                for f in "${NETPLAN_FILES[@]}"; do
                    print_message "Processing: $f"
                    cp -p "$f" "${f}.backup.${NETPLAN_TS}~" || { print_error "Cannot back up netplan file: $f"; exit 1; }

                    set +e
                    python3 - "$f" <<'PYEOF'
import os
import stat
import sys
import tempfile
import yaml

path = sys.argv[1]

try:
    with open(path, 'r') as fp:
        cfg = yaml.safe_load(fp)
except yaml.YAMLError:
    print("  YAML parse error; original file was left unchanged")
    sys.exit(2)

if not isinstance(cfg, dict) or 'network' not in cfg \
        or not isinstance(cfg['network'], dict):
    print("  no 'network:' key — leaving file untouched")
    sys.exit(0)

net = cfg['network']
changed = False

def _addr_has_colon(item):
    # netplan 'addresses' entries: "192.0.2.1/24" or {"2001:db8::1/64": {...}}
    if isinstance(item, str):
        return ':' in item
    if isinstance(item, dict) and item:
        return ':' in next(iter(item))
    return False

for dev_type in ('ethernets', 'wifis', 'bonds', 'bridges', 'vlans', 'tunnels'):
    devs = net.get(dev_type)
    if not isinstance(devs, dict):
        continue
    for iface_name, iface in devs.items():
        if not isinstance(iface, dict):
            continue

        # dhcp6 → false (force, regardless of prior value)
        if iface.get('dhcp6') is not False:
            iface['dhcp6'] = False
            changed = True

        # accept-ra → false
        if iface.get('accept-ra') is not False:
            iface['accept-ra'] = False
            changed = True

        # Netplan defaults to IPv6 link-local. Remove it without enabling IPv4.
        link_local = [family for family in iface.get('link-local', ['ipv6']) if family != 'ipv6']
        if iface.get('link-local') != link_local:
            iface['link-local'] = link_local
            changed = True

        # addresses: drop IPv6 entries
        if isinstance(iface.get('addresses'), list):
            new_addrs = [a for a in iface['addresses'] if not _addr_has_colon(a)]
            if len(new_addrs) != len(iface['addresses']):
                changed = True
            if new_addrs:
                iface['addresses'] = new_addrs
            else:
                del iface['addresses']

        # gateway6
        if 'gateway6' in iface:
            del iface['gateway6']
            changed = True

        # nameservers: drop IPv6 entries
        ns = iface.get('nameservers')
        if isinstance(ns, dict) and isinstance(ns.get('addresses'), list):
            new_ns = [a for a in ns['addresses'] if ':' not in str(a)]
            if len(new_ns) != len(ns['addresses']):
                changed = True
            if new_ns:
                ns['addresses'] = new_ns
            else:
                del ns['addresses']
            if not ns:
                del iface['nameservers']

        # routes: drop IPv6 entries
        if isinstance(iface.get('routes'), list):
            new_routes = []
            for r in iface['routes']:
                if isinstance(r, dict) and (':' in str(r.get('to', '')) \
                                            or ':' in str(r.get('via', ''))):
                    changed = True
                    continue
                new_routes.append(r)
            if new_routes:
                iface['routes'] = new_routes
            else:
                iface.pop('routes', None)

if changed:
    fd, temporary = tempfile.mkstemp(prefix='.netplan-', dir=os.path.dirname(path))
    try:
        with os.fdopen(fd, 'w') as fp:
            yaml.safe_dump(cfg, fp, default_flow_style=False, sort_keys=False)
        os.chmod(temporary, stat.S_IMODE(os.stat(path).st_mode))
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    print("  CHANGED: IPv6 settings disabled")
    sys.exit(10)
else:
    print("  no IPv6 config found — file unchanged")
    sys.exit(0)
PYEOF
                    rc=$?
                    set +e
                    if [ "$rc" -eq 10 ]; then
                        NETPLAN_CHANGED_FILES+=("$f")
                        # netplan since 0.106 (Ubuntu 23.10+) requires 0600 on YAML
                        chmod 600 "$f"
                    elif [ "$rc" -eq 2 ]; then
                        print_error "  YAML parse failed for $f — restoring backup"
                        cp "${f}.backup.${NETPLAN_TS}~" "$f"
                    elif [ "$rc" -ne 0 ]; then
                        print_error "  netplan edit helper failed for $f (exit code: $rc) — restoring backup"
                        cp "${f}.backup.${NETPLAN_TS}~" "$f"
                    fi
                done

                if [ "${#NETPLAN_CHANGED_FILES[@]}" -eq 0 ]; then
                    if netplan generate >/dev/null 2>&1; then NETPLAN_OK=true; fi
                    print_message "No netplan files changed"
                else
                    print_message "Validating netplan config with 'netplan generate'..."
                    NETPLAN_LOG=$(mktemp "${TMPDIR:-/tmp}/netplan-generate.${NETPLAN_TS}.XXXXXX")
                    chmod 600 "$NETPLAN_LOG"
                    if netplan generate >"$NETPLAN_LOG" 2>&1; then
                        NETPLAN_OK=true
                        print_success "Netplan config is valid"
                        print_message "Modified files:"
                        for f in "${NETPLAN_CHANGED_FILES[@]}"; do
                            print_message "  - $f (backup: ${f}.backup.${NETPLAN_TS}~)"
                        done
                        echo ""
                        print_warning "Changes are NOT applied yet — run when you're ready:"
                        print_warning "  sudo netplan apply"
                        print_warning "If the box's only working route is IPv6, applying will drop SSH."
                    else
                        print_error "netplan generate FAILED — see $NETPLAN_LOG"
                        cat "$NETPLAN_LOG" | sed 's/^/    /'
                        print_warning "Restoring all modified netplan files from backup..."
                        for f in "${NETPLAN_CHANGED_FILES[@]}"; do
                            cp "${f}.backup.${NETPLAN_TS}~" "$f"
                            chmod 600 "$f"
                            print_message "  Restored: $f"
                        done
                        netplan generate >>"$NETPLAN_LOG" 2>&1 || print_error "Could not regenerate netplan runtime files after rollback"
                    fi
                fi
            fi
        fi
    fi
    echo ""
else
    print_message "Skipping IPv6 netplan disable (not requested)"
fi

# ============================================
# FINAL MESSAGE
# ============================================

# Final message
echo ""
print_header "═════════════════════════════════════════"
if final_exit_code; then
    print_message "System setup completed successfully!"
else
    print_header "System setup completed with errors; review the execution log below"
fi
print_header "═════════════════════════════════════════"
print_message "Summary:"
print_message "- OS: $OS $VERSION ($VERSION_CODENAME)"
print_message "- Packages installed"

if [ "$INSTALL_RUSTDESK" = "y" ] || [ "$INSTALL_RUSTDESK" = "Y" ]; then
    if systemctl is-enabled --quiet rustdesk-compose.service 2>/dev/null; then
        print_message "- RustDesk Server: Installed and enabled"
        print_message "  Directory: /opt/rustdesk"
        print_message "  Service: rustdesk-compose.service"
        if systemctl is-active --quiet rustdesk-compose.service; then
            print_message "  Status: Running"
        else
            print_message "  Status: Enabled (will start with Docker)"
        fi
        if systemctl is-enabled --quiet rustdesk-update.timer 2>/dev/null; then
            print_message "  Auto-update: rustdesk-update.timer (weekly, Sun 04:00)"
        fi
    else
        print_message "- RustDesk Server: Installation attempted but service not enabled"
    fi
else
    print_message "- RustDesk Server: Not installed"
fi

if [ "$SET_ROOT_PASSWORD" = "y" ] || [ "$SET_ROOT_PASSWORD" = "Y" ]; then
    report_setup_result "Root password" "${ROOT_PASSWORD_OK:-false}"
else
    print_message "- Root password: NOT SET"
fi

if [ ! -z "$NEW_USERNAME" ]; then
    print_message "- User account: $NEW_USERNAME ($CREATE_USER)"
    if [ "$CONFIGURE_USER_SSH_KEY" = "y" ] || [ "$CONFIGURE_USER_SSH_KEY" = "Y" ]; then
        report_setup_result "SSH key" "${USER_SSH_KEY_OK:-false}"
    fi
    if [ "$INSTALL_ZSH" = "y" ] || [ "$INSTALL_ZSH" = "Y" ]; then
        if [ "${OH_MY_ZSH_OK:-false}" = true ]; then
            print_message "  - Oh My Zsh installed at the pinned commit"
            report_setup_result "Zsh plugins, configuration and login shell" "${ZSH_CONFIG_OK:-false}"
        else
            print_message "  - Oh My Zsh installation FAILED or incomplete"
        fi
    fi
else
    print_message "- New user: NOT CREATED"
fi

if [ "$CONFIGURE_CRONTAB" = "y" ] || [ "$CONFIGURE_CRONTAB" = "Y" ]; then
    report_setup_result "Root crontab" "${CRONTAB_OK:-false}"
else
    print_message "- Crontab: NOT CONFIGURED"
fi

if [ "$CONFIGURE_SSH" = "y" ] || [ "$CONFIGURE_SSH" = "Y" ]; then
    print_message "- SSH configured (Port: $SSH_PORT, AllowUsers: ${SSH_ALLOW_USERS:-not set})"
    if [ ! -z "$SSH_PUBKEY_AUTH" ]; then
        print_message "  - PubkeyAuthentication: $SSH_PUBKEY_AUTH"
    fi
    if [ ! -z "$SSH_PASSWORD_AUTH" ]; then
        print_message "  - PasswordAuthentication: $SSH_PASSWORD_AUTH"
    fi
    if [ ! -z "$SSH_EMPTY_PASSWORDS" ]; then
        print_message "  - PermitEmptyPasswords: $SSH_EMPTY_PASSWORDS (security enforced)"
    fi
    if [ ! -z "$SSH_ROOT_LOGIN" ]; then
        print_message "  - PermitRootLogin: $SSH_ROOT_LOGIN"
    fi
    if [ ! -z "$SSH_PRINT_MOTD" ]; then
        print_message "  - PrintMotd: $SSH_PRINT_MOTD"
    fi
else
    print_message "- SSH: NOT CONFIGURED"
fi

if [ "$CONFIGURE_YUBIKEY_SSH" = "y" ] || [ "$CONFIGURE_YUBIKEY_SSH" = "Y" ]; then
    report_setup_result "YubiKey/FIDO2 SSH" "${YUBIKEY_SSH_OK:-false}"
    print_message "  User: ${YUBIKEY_SSH_USER:-not set}"
    if [ -n "$YUBIKEY_SSH_PUBLIC_KEY" ]; then
        print_message "  Public key: added to authorized_keys"
    else
        print_message "  Public key: not provided (server-side support only)"
    fi
    if [ -f /etc/ssh/sshd_config.d/00-yubikey-fido2.conf ]; then
        print_message "  sshd drop-in: /etc/ssh/sshd_config.d/00-yubikey-fido2.conf"
    fi
    print_message "  Password authentication disabled: $([ "$YUBIKEY_SSH_DISABLE_PASSWORD_AUTH" = "y" ] || [ "$YUBIKEY_SSH_DISABLE_PASSWORD_AUTH" = "Y" ] && echo "YES" || echo "NO")"
else
    print_message "- YubiKey/FIDO2 SSH: Not configured"
fi

if [ "$CREATE_VENV" = "y" ] || [ "$CREATE_VENV" = "Y" ]; then
    report_setup_result "Python venv ($VENV_PATH)" "${VENV_CREATED_OK:-false}"
    report_setup_result "Python packages" "${VENV_PACKAGES_OK:-false}"
else
    print_message "- Python venv: NOT CREATED"
fi

if [ "$CONFIGURE_SYSCTL" = "y" ] || [ "$CONFIGURE_SYSCTL" = "Y" ]; then
    if [ "$SYSCTL_MODE" = "2" ]; then
        print_message "- sysctl: Full optimization (Linux NetworkOptimizer / bbr.sh)"
    else
        print_message "- sysctl: Basic optimization (static parameters)"
    fi
    report_setup_result "sysctl application" "${SYSCTL_OK:-false}"
    print_message "  sysctl config file: ${SYSCTL_TARGET_FILE:-/etc/sysctl.conf}"
    if [ "$ENABLE_IP_FORWARD" = "y" ] || [ "$ENABLE_IP_FORWARD" = "Y" ]; then
        print_message "  IP forwarding: ENABLED"
    else
        print_message "  IP forwarding: not changed by this step"
    fi
    if [ "$INSTALL_SYSCTL_SERVICE" = "y" ] || [ "$INSTALL_SYSCTL_SERVICE" = "Y" ]; then
        report_setup_result "sysctl enforcement service" "${SYSCTL_SERVICE_OK:-false}"
    fi
else
    print_message "- sysctl: SKIPPED"
fi

if [ "$CONFIGURE_RESOLVED" = "y" ] || [ "$CONFIGURE_RESOLVED" = "Y" ]; then
    report_setup_result "systemd-resolved" "${RESOLVED_OK:-false}"
    print_message "  DNS: ${RESOLVED_DNS}"
    print_message "  DNSStubListener: $([ "$RESOLVED_STUB_LISTENER_OFF" = "y" ] || [ "$RESOLVED_STUB_LISTENER_OFF" = "Y" ] && echo "disabled" || echo "enabled")"
    print_message "  DNSOverTLS: $([ "$RESOLVED_DNS_OVER_TLS" = "y" ] || [ "$RESOLVED_DNS_OVER_TLS" = "Y" ] && echo "yes" || echo "no")"
    if [ -L /etc/resolv.conf ]; then
        print_message "  resolv.conf: symlink -> $(readlink /etc/resolv.conf 2>/dev/null)"
    fi
else
    print_message "- systemd-resolved: Not configured"
fi

if { [ "$OS" = "debian" ] || [ "$OS" = "ubuntu" ]; } && \
   { [ "$DISABLE_IPV6_GRUB" = "y" ] || [ "$DISABLE_IPV6_GRUB" = "Y" ]; }; then
    report_setup_result "GRUB IPv6 configuration" "${GRUB_OK:-false}"
    print_warning "  Note: Requires reboot to take effect"
fi

if [ "$CONFIGURE_REPOS" = "y" ] || [ "$CONFIGURE_REPOS" = "Y" ]; then
    if [ "$OS" = "debian" ]; then
        print_message "- Debian repositories configured"
    else
        print_message "- Ubuntu repositories configured (main, restricted, universe, multiverse)"
        if [ "$ADD_UBUNTU_PPAS" = "y" ] || [ "$ADD_UBUNTU_PPAS" = "Y" ]; then
            print_message "- Ubuntu PPA repositories:"
            if [ "$ADD_PPA_PHP" = "y" ] || [ "$ADD_PPA_PHP" = "Y" ]; then
                print_message "  ✓ ppa:ondrej/php (Latest PHP)"
                if [ "$INSTALL_PHP_CLI" = "y" ] || [ "$INSTALL_PHP_CLI" = "Y" ]; then
                    print_message "    - php-cli installed"
                    if [ "$INSTALL_PHP_EXTENSIONS" = "y" ] || [ "$INSTALL_PHP_EXTENSIONS" = "Y" ]; then
                        print_message "    - PHP extensions installed (mbstring, xml, curl, mysql)"
                    fi
                fi
            fi
            if [ "$ADD_PPA_GIT" = "y" ] || [ "$ADD_PPA_GIT" = "Y" ]; then
                print_message "  ✓ ppa:git-core/ppa (Latest Git)"
            fi
            if [ "$ADD_PPA_TOOLCHAIN" = "y" ] || [ "$ADD_PPA_TOOLCHAIN" = "Y" ]; then
                print_message "  ✓ ppa:ubuntu-toolchain-r/test (Latest GCC)"
            fi
        fi
    fi
fi

if [ "$OS" = "debian" ] || [ "$OS" = "ubuntu" ]; then
    if [ "$REMOVE_NGINX" = "y" ] || [ "$REMOVE_NGINX" = "Y" ]; then
        if [ -e /usr/sbin/nginx ] || command -v nginx >/dev/null 2>&1; then
            print_warning "- nginx removal requested but a binary may remain — check 'command -v nginx'"
        else
            print_message "- nginx completely removed (packages, configs, binaries, deps, symlinks)"
        fi
        [ -n "${NGINX_RM_BK:-}" ] && print_message "  Config backup: $NGINX_RM_BK"
    fi
    if [ "$ADD_NGINX_ORG" = "y" ] || [ "$ADD_NGINX_ORG" = "Y" ]; then
        print_message "- Official nginx.org repository added (https://nginx.org/packages/$OS)"
    fi
    if [ "$ADD_NGINX_MYGUARD" = "y" ] || [ "$ADD_NGINX_MYGUARD" = "Y" ]; then
        print_message "- Third-party deb.myguard.nl Nginx repository added"
    fi
    if [ "$ADD_NGINX_MODULES" = "y" ] || [ "$ADD_NGINX_MODULES" = "Y" ]; then
        print_message "- nginx-modules.com (Blendbyte) modules repository added"
    fi
    if { [ "$INSTALL_NGINX" = "y" ] || [ "$INSTALL_NGINX" = "Y" ]; } && command -v nginx >/dev/null 2>&1; then
        print_message "- nginx installed ($(nginx -v 2>&1 | sed 's#.*/##'))"
        print_message "  Remember to enable dynamic modules via load_module in /etc/nginx/nginx.conf"
    fi
fi

if [ "$COMMENT_IPV6_INTERFACES" = "y" ] || [ "$COMMENT_IPV6_INTERFACES" = "Y" ]; then
    if [ -f /etc/network/interfaces ]; then
        report_setup_result "IPv6 in /etc/network/interfaces" "${INTERFACES_OK:-false}"
        print_warning "  Note: May require network restart or reboot"
    fi
fi

if [ "$DISABLE_IPV6_NETPLAN" = "y" ] || [ "$DISABLE_IPV6_NETPLAN" = "Y" ]; then
    report_setup_result "Netplan IPv6 configuration (not applied)" "${NETPLAN_OK:-false}"
    print_warning "  Run 'sudo netplan apply' manually when ready"
fi

if [ "$CONFIGURE_UFW" = "y" ] || [ "$CONFIGURE_UFW" = "Y" ]; then
    report_setup_result "UFW firewall" "${UFW_CONFIG_OK:-false}"
    if [ "$BLOCK_ICMP" = "y" ] || [ "$BLOCK_ICMP" = "Y" ]; then
        print_message "- ICMP (ping) blocking: ENABLED"
    else
        print_message "- ICMP (ping) blocking: DISABLED (server responds to ping)"
    fi
    if [ ! -z "$CUSTOM_PORTS" ]; then
        print_message "- Custom UFW ports: $CUSTOM_PORTS"
    fi
else
    print_message "- UFW: SKIPPED"
fi

if [ "$ENABLE_NFTABLES" = "y" ] || [ "$ENABLE_NFTABLES" = "Y" ]; then
    if [ "${NFTABLES_OK:-false}" = true ]; then
        print_message "- nftables: rules applied and verified; service enabled for boot"
        print_message "  Runtime rules are loaded directly; an inactive oneshot service does not mean the firewall is off"
    else
        print_message "- nftables setup: FAILED; review rollback messages"
    fi
    if [ ! -z "$NFTABLES_PROFILE" ] && [ "$INSTALL_NFTABLES_CONF" != "skipped" ]; then
        print_message "  Profile: ${NFTABLES_PROFILE} (${NFTABLES_CONF_FILE})"
    fi
    if [ "$INSTALL_NFTABLES_LOGGING" = "y" ] || [ "$INSTALL_NFTABLES_LOGGING" = "Y" ]; then
        report_setup_result "nftables logging" "${NFT_LOGGING_OK:-false}"
    fi
    if dpkg -l ufw 2>/dev/null | grep -q "^ii"; then
        if [ "$(systemctl is-enabled ufw 2>/dev/null)" = masked ]; then
            print_message "  UFW: disabled and masked"
        fi
    fi
else
    print_message "- nftables: Not configured"
fi

if command -v docker &> /dev/null; then
    print_message "- Docker: Installed"
    if [ "$DOCKER_DISABLE_IPTABLES" = "y" ] || [ "$DOCKER_DISABLE_IPTABLES" = "Y" ]; then
        if [ -f /etc/docker/daemon.json ] && grep -q '"iptables"' /etc/docker/daemon.json 2>/dev/null; then
            print_message "  Docker iptables: DISABLED (daemon.json)"
        else
            print_message "  Docker iptables: daemon.json may not have been applied"
        fi
    fi
else
    print_message "- Docker: Not installed"
    if [ "$INSTALL_DOCKER" = "y" ] || [ "$INSTALL_DOCKER" = "Y" ]; then
        print_message "- Docker installation may have failed"
    fi
fi

if command -v ufw-docker &> /dev/null; then
    print_message "- ufw-docker binary: present"
    if is_yes "$INSTALL_UFW_DOCKER"; then report_setup_result "ufw-docker configuration" "${UFW_DOCKER_OK:-false}"; fi
else
    if [ "$INSTALL_UFW_DOCKER" = "y" ] || [ "$INSTALL_UFW_DOCKER" = "Y" ]; then
        print_message "- ufw-docker: Installation attempted but not found"
    else
        print_message "- ufw-docker: Not installed"
    fi
fi

if command -v go &> /dev/null || [ -f /usr/local/go/bin/go ]; then
    if [ -f /usr/local/go/bin/go ]; then
        GO_VERSION=$(/usr/local/go/bin/go version 2>/dev/null || echo "unknown")
        print_message "- Go: Installed ($GO_VERSION)"
        if [ ! -z "$NEW_USERNAME" ]; then
            USER_HOME=$(getent passwd "$NEW_USERNAME" | cut -d: -f6)
            if [ -f "$USER_HOME/.zshrc" ]; then
                print_message "  Configured in: $USER_HOME/.zshrc"
            elif [ -f "$USER_HOME/.bashrc" ]; then
                print_message "  Configured in: $USER_HOME/.bashrc"
            fi
        fi
    fi
else
    if [ "$INSTALL_GO" = "y" ] || [ "$INSTALL_GO" = "Y" ]; then
        print_message "- Go: Installation attempted but not found"
    else
        print_message "- Go: Not installed"
    fi
fi

if command -v ipset &> /dev/null; then
    IPSET_VERSION=$(ipset --version 2>/dev/null || echo "unknown")
    print_message "- ipset: Installed ($IPSET_VERSION)"
else
    if [ "$INSTALL_IPSET" = "y" ] || [ "$INSTALL_IPSET" = "Y" ]; then
        print_message "- ipset: Installation attempted but not found"
    else
        print_message "- ipset: Not installed"
    fi
fi

if command -v rclone &>/dev/null; then
    RCLONE_VERSION=$(rclone version 2>/dev/null | head -1 || echo "unknown")
    print_message "- rclone: Installed ($RCLONE_VERSION)"
else
    if [ "$INSTALL_RCLONE" = "y" ] || [ "$INSTALL_RCLONE" = "Y" ]; then
        print_message "- rclone: Installation attempted but not found"
    else
        print_message "- rclone: Not installed"
    fi
fi

if [ "$INSTALL_MOTD" = "y" ] || [ "$INSTALL_MOTD" = "Y" ]; then
    report_setup_result "Custom MOTD" "${MOTD_OK:-false}"
    print_warning "  Note: MOTD will be visible on next SSH login"
else
    print_message "- Custom MOTD: Not installed"
fi

if [ "$INSTALL_UFW_CUSTOM_RULES" = "y" ] || [ "$INSTALL_UFW_CUSTOM_RULES" = "Y" ]; then
    UFW_SCRIPT_PATH="/opt/ufw-docker-rules-v${UFW_RULES_VERSION}.sh"
    if [ "${UFW_CUSTOM_RULES_OK:-false}" = true ] && [ -f "$UFW_SCRIPT_PATH" ]; then
        UFW_SOURCE_TEXT="$([ "$UFW_INSTALL_SOURCE" = "2" ] && echo "from repository" || echo "from archive")"
        print_message "- Custom UFW Docker rules: Installed and executed (v${UFW_RULES_VERSION}, ${UFW_SOURCE_TEXT})"
        print_message "  Script location: $UFW_SCRIPT_PATH"
        # Show custom SSH port if configured
        if [ -n "$UFW_SSH_PORT" ] && [ "$UFW_SSH_PORT" != "22" ]; then
            print_message "  Custom SSH port configured: $UFW_SSH_PORT"
        fi
        # Show archive extraction info
        if [ "$UFW_INSTALL_SOURCE" = "1" ] && { [ "$EXTRACT_OPT_ARCHIVE" = "y" ] || [ "$EXTRACT_OPT_ARCHIVE" = "Y" ]; }; then
            print_message "  Archive extracted to: /opt"
            if [ -d "/opt/scripts" ]; then
                SCRIPT_COUNT=$(find /opt/scripts -type f ! -name "*.ini" | wc -l)
                print_message "  Executable scripts in /opt/scripts: $SCRIPT_COUNT"
            fi
        fi
    else
        print_message "- Custom UFW Docker rules: Installation attempted but failed"
    fi
else
    print_message "- Custom UFW Docker rules: Not installed"
fi

if [[ "$EXTRACT_OPT_ARCHIVE" =~ ^[yY]$ ]]; then
    if [ "$OPT_COPY_OK" = true ]; then
        print_message "- opt.7z: Extracted and copied to /opt"
    else
        print_message "- opt.7z: Extraction or copy FAILED"
    fi
fi

if [ "$CONFIGURE_SWAP" = "y" ] || [ "$CONFIGURE_SWAP" = "Y" ]; then
    if [ "${SWAP_SETUP_OK:-false}" = true ]; then
        print_message "- Swap Configuration: Configured (active swap verified)"
    else
        print_message "- Swap Configuration: FAILED or incomplete"
    fi
    if [ -f /usr/local/sbin/swap-setup.sh ]; then
        print_message "  Swap script installed: /usr/local/sbin/swap-setup.sh"
    fi
    print_message "  Check status: sudo swap-setup.sh --status"
else
    print_message "- Swap Configuration: Not configured"
fi

if [ "$SYSCTL_MODE" = "2" ]; then
    report_setup_result "Linux NetworkOptimizer (bbr.sh)" "${BBR_OK:-false}"
    print_message "  Force IPv4 APT: $([ "$BBR_FORCE_IPV4" = "y" ] || [ "$BBR_FORCE_IPV4" = "Y" ] && echo "YES" || echo "NO")"
    print_message "  Full Update: $([ "$BBR_FULL_UPDATE" = "y" ] || [ "$BBR_FULL_UPDATE" = "Y" ] && echo "YES" || echo "NO")"
    print_message "  Fix /etc/hosts: $([ "$BBR_FIX_HOSTS" = "y" ] || [ "$BBR_FIX_HOSTS" = "Y" ] && echo "YES" || echo "NO")"
    print_message "  Fix DNS: $([ "$BBR_FIX_DNS" = "y" ] || [ "$BBR_FIX_DNS" = "Y" ] && echo "YES" || echo "NO")"
fi

print_message ""

if [ "$CONFIGURE_SYSCTL" = "y" ] || [ "$CONFIGURE_SYSCTL" = "Y" ] || [ "$CONFIGURE_REPOS" = "y" ] || [ "$CONFIGURE_REPOS" = "Y" ] || [ "$CONFIGURE_SSH" = "y" ] || [ "$CONFIGURE_SSH" = "Y" ] || [ "$CONFIGURE_YUBIKEY_SSH" = "y" ] || [ "$CONFIGURE_YUBIKEY_SSH" = "Y" ] || [ "$BLOCK_ICMP" = "y" ] || [ "$BLOCK_ICMP" = "Y" ] || [ "$CONFIGURE_CRONTAB" = "y" ] || [ "$CONFIGURE_CRONTAB" = "Y" ] || [ "$CONFIGURE_RESOLVED" = "y" ] || [ "$CONFIGURE_RESOLVED" = "Y" ] || { { [ "$OS" = "debian" ] || [ "$OS" = "ubuntu" ]; } && { [ "$DISABLE_IPV6_GRUB" = "y" ] || [ "$DISABLE_IPV6_GRUB" = "Y" ]; }; } || [ "$DISABLE_IPV6_NETPLAN" = "y" ] || [ "$DISABLE_IPV6_NETPLAN" = "Y" ]; then
    print_message "Backup files saved with timestamp (format: filename.backup.YYYYMMDD-HHMMSS~):"
    if [ "$CONFIGURE_SYSCTL" = "y" ] || [ "$CONFIGURE_SYSCTL" = "Y" ]; then
        print_message "- ${SYSCTL_TARGET_FILE:-/etc/sysctl.conf}.backup.*~ (if original file existed)"
    fi
    if [ "$CONFIGURE_REPOS" = "y" ] || [ "$CONFIGURE_REPOS" = "Y" ]; then
        if [ "$OS" = "debian" ]; then
            print_message "- /etc/apt/sources.list.backup.*~"
        else
            print_message "- /etc/apt/sources.list.backup.*~"
            print_message "- /etc/apt/sources.list.d/ubuntu.sources.backup.*~"
        fi
    fi
    if [ "$CONFIGURE_SSH" = "y" ] || [ "$CONFIGURE_SSH" = "Y" ]; then
        print_message "- /etc/ssh/sshd_config.backup.*~"
        print_message "- /etc/ssh/sshd_config.d/10-system-setup.conf (managed drop-in)"
    fi
    if [ "$CONFIGURE_YUBIKEY_SSH" = "y" ] || [ "$CONFIGURE_YUBIKEY_SSH" = "Y" ]; then
        print_message "- /etc/ssh/sshd_config.backup.yubikey.*~"
        print_message "- /etc/ssh/sshd_config.d/00-yubikey-fido2.conf (managed drop-in)"
    fi
    if [ "$BLOCK_ICMP" = "y" ] || [ "$BLOCK_ICMP" = "Y" ]; then
        print_message "- /etc/ufw/before.rules.backup.*~"
    fi
    if [ "$CONFIGURE_CRONTAB" = "y" ] || [ "$CONFIGURE_CRONTAB" = "Y" ]; then
        print_message "- ${TMPDIR:-/tmp}/crontab.backup.*"
    fi
    if { [ "$OS" = "debian" ] || [ "$OS" = "ubuntu" ]; } && \
       { [ "$DISABLE_IPV6_GRUB" = "y" ] || [ "$DISABLE_IPV6_GRUB" = "Y" ]; }; then
        print_message "- /etc/default/grub.backup.*~"
    fi
    if [ "$DISABLE_IPV6_NETPLAN" = "y" ] || [ "$DISABLE_IPV6_NETPLAN" = "Y" ]; then
        print_message "- /etc/netplan/*.yaml.backup.*~ (per modified file)"
    fi
    if [ "$CONFIGURE_RESOLVED" = "y" ] || [ "$CONFIGURE_RESOLVED" = "Y" ]; then
        print_message "- /etc/systemd/resolved.conf.backup.*~"
        print_message "- /etc/resolv.conf.backup.*~ (if was a regular file)"
    fi
    print_message ""
fi

print_message "Execution log:"
if [ "${#SETUP_WARNINGS[@]}" -eq 0 ] && \
   [ "${#SETUP_ERRORS[@]}" -eq 0 ] && \
   [ "${#SETUP_ROLLBACKS[@]}" -eq 0 ]; then
    print_message "- No warnings, errors, or rollback events recorded"
else
    print_recorded_items "- Warnings:" "${SETUP_WARNINGS[@]}"
    print_recorded_items "- Errors:" "${SETUP_ERRORS[@]}"
    print_recorded_items "- Rollbacks/restores:" "${SETUP_ROLLBACKS[@]}"
fi
print_message ""

print_warning "Recommended next steps:"
STEP_NUM=1

if [ ! -z "$NEW_USERNAME" ]; then
    print_warning "$STEP_NUM. Test SSH connection with new user: ssh $NEW_USERNAME@hostname"
    if [ "$INSTALL_ZSH" = "y" ] || [ "$INSTALL_ZSH" = "Y" ]; then
        print_warning "   Note: zsh is configured, log in to see Oh My Zsh"
    fi
    STEP_NUM=$((STEP_NUM + 1))
fi

if [ "$CONFIGURE_SSH" = "y" ] || [ "$CONFIGURE_SSH" = "Y" ]; then
    if [ "$SSH_PORT" != "22" ]; then
        print_warning "$STEP_NUM. IMPORTANT: SSH port changed to $SSH_PORT"
        print_warning "   Make sure to update your SSH client before logging out!"
        print_warning "   Test connection: ssh -p $SSH_PORT user@host"
        STEP_NUM=$((STEP_NUM + 1))
    fi
fi

if [ "$CONFIGURE_YUBIKEY_SSH" = "y" ] || [ "$CONFIGURE_YUBIKEY_SSH" = "Y" ]; then
    if [ -n "$YUBIKEY_SSH_PUBLIC_KEY" ]; then
        print_warning "$STEP_NUM. Test YubiKey SSH before closing this session: ssh ${YUBIKEY_SSH_USER:-user}@hostname"
    else
        print_warning "$STEP_NUM. Add a YubiKey public key later to ~/.ssh/authorized_keys for the target user"
    fi
    STEP_NUM=$((STEP_NUM + 1))
fi

if [ "$CONFIGURE_UFW" = "y" ] || [ "$CONFIGURE_UFW" = "Y" ]; then
    print_warning "$STEP_NUM. Review UFW status: sudo ufw status verbose"
    STEP_NUM=$((STEP_NUM + 1))
fi

if [ "$ENABLE_NFTABLES" = "y" ] || [ "$ENABLE_NFTABLES" = "Y" ]; then
    print_warning "$STEP_NUM. Check nftables: nft list ruleset"
    STEP_NUM=$((STEP_NUM + 1))
fi

if [ "$CONFIGURE_SYSCTL" = "y" ] || [ "$CONFIGURE_SYSCTL" = "Y" ]; then
    print_warning "$STEP_NUM. Check sysctl: sysctl net.ipv4.tcp_congestion_control"
    STEP_NUM=$((STEP_NUM + 1))
fi

if [ "$CONFIGURE_RESOLVED" = "y" ] || [ "$CONFIGURE_RESOLVED" = "Y" ]; then
    print_warning "$STEP_NUM. Check DNS: resolvectl status"
    STEP_NUM=$((STEP_NUM + 1))
fi

if [ "$CREATE_VENV" = "y" ] || [ "$CREATE_VENV" = "Y" ]; then
    print_warning "$STEP_NUM. Activate Python venv: source $VENV_PATH/bin/activate"
    STEP_NUM=$((STEP_NUM + 1))
fi

if command -v docker &> /dev/null; then
    if [ ! -z "$NEW_USERNAME" ]; then
        print_warning "$STEP_NUM. User $NEW_USERNAME needs to log out and back in to use Docker without sudo"
        STEP_NUM=$((STEP_NUM + 1))
    fi
    if [ ! -z "$SUDO_USER" ] && [ "$SUDO_USER" != "$NEW_USERNAME" ]; then
        print_warning "$STEP_NUM. User $SUDO_USER needs to log out and back in to use Docker without sudo"
        STEP_NUM=$((STEP_NUM + 1))
    fi
fi

if [ "$CONFIGURE_SWAP" = "y" ] || [ "$CONFIGURE_SWAP" = "Y" ]; then
    print_warning "$STEP_NUM. Check swap status: sudo swap-setup.sh --status"
    STEP_NUM=$((STEP_NUM + 1))
fi

if [ "$CONFIGURE_CRONTAB" = "y" ] || [ "$CONFIGURE_CRONTAB" = "Y" ]; then
    print_warning "$STEP_NUM. Check crontab: sudo crontab -l"
    STEP_NUM=$((STEP_NUM + 1))
fi

if { [ "$OS" = "debian" ] || [ "$OS" = "ubuntu" ]; } && \
   { [ "$DISABLE_IPV6_GRUB" = "y" ] || [ "$DISABLE_IPV6_GRUB" = "Y" ]; }; then
    print_warning "$STEP_NUM. Check GRUB IPv6 disable after reboot: cat /proc/cmdline | grep ipv6"
    STEP_NUM=$((STEP_NUM + 1))
fi

if [ "$DISABLE_IPV6_NETPLAN" = "y" ] || [ "$DISABLE_IPV6_NETPLAN" = "Y" ]; then
    print_warning "$STEP_NUM. Apply netplan IPv6 disable when ready: sudo netplan apply"
    print_warning "   (skipped here on purpose to avoid breaking SSH if IPv6 was in use)"
    STEP_NUM=$((STEP_NUM + 1))
fi

if [ "$INSTALL_MOTD" = "y" ] || [ "$INSTALL_MOTD" = "Y" ]; then
    print_warning "$STEP_NUM. Test MOTD: Reconnect via SSH to see custom MOTD"
    STEP_NUM=$((STEP_NUM + 1))
fi

print_message ""
print_message "Useful commands:"
print_message "sudo ufw status verbose"
print_message "sudo ufw status numbered"
print_message "sudo nano ${SYSCTL_TARGET_FILE:-/etc/sysctl.conf}"
print_message "sudo nano /etc/apt/sources.list"
if [ "$OS" = "ubuntu" ]; then
    print_message "sudo nano /etc/apt/sources.list.d/ubuntu.sources"
fi
print_message "sudo nano /etc/ssh/sshd_config"
if [ "$CONFIGURE_SSH" = "y" ] || [ "$CONFIGURE_SSH" = "Y" ]; then
    print_message "sudo nano /etc/ssh/sshd_config.d/10-system-setup.conf  # Managed drop-in (overwritten on re-run!)"
    print_message "sudo sshd -T | less                    # Show effective sshd config (resolves all drop-ins)"
    print_warning "Note: /etc/ssh/sshd_config.d/10-system-setup.conf is REGENERATED every time this script runs."
    print_warning "      For permanent customization, create another drop-in that sorts BEFORE it,"
    print_warning "      e.g. /etc/ssh/sshd_config.d/01-local.conf  (first value wins in sshd)."
fi
if [ "$CONFIGURE_YUBIKEY_SSH" = "y" ] || [ "$CONFIGURE_YUBIKEY_SSH" = "Y" ]; then
    print_message "ssh-keygen -t ed25519-sk -O resident -O verify-required -C \"user@host\""
    print_message "ssh-keygen -K                         # Download resident YubiKey SSH keys"
    print_message "sudo nano /etc/ssh/sshd_config.d/00-yubikey-fido2.conf  # Managed drop-in (overwritten on re-run!)"
    print_message "sudo sshd -t                          # Validate SSH configuration"
fi
if [ "$ENABLE_NFTABLES" = "y" ] || [ "$ENABLE_NFTABLES" = "Y" ]; then
    print_message "nft list ruleset                       # Show nftables rules"
    print_message "sudo nano /etc/nftables.conf           # Edit nftables config"
    print_message "nft -c -f /etc/nftables.conf           # Verify syntax"
    print_message "nft -f /etc/nftables.conf              # Apply config"
    print_message "systemctl restart nftables             # Reload service"
    if [ ! -z "$NFTABLES_PROFILE" ]; then
        print_message "ls /opt/nftables/                      # Available configs"
        print_message "ls /opt/nftables/logging/              # Logging scripts"
    fi
    if dpkg -l ufw 2>/dev/null | grep -q "^ii"; then
        print_message "systemctl unmask ufw                   # Re-enable UFW (if needed)"
    fi
fi
if [ "$DOCKER_DISABLE_IPTABLES" = "y" ] || [ "$DOCKER_DISABLE_IPTABLES" = "Y" ]; then
    print_message "sudo nano /etc/docker/daemon.json  # Docker daemon config"
fi
if [ "$CONFIGURE_RESOLVED" = "y" ] || [ "$CONFIGURE_RESOLVED" = "Y" ]; then
    print_message "resolvectl status                      # Check resolved status"
    print_message "resolvectl query example.com           # Test DNS resolution"
    print_message "sudo nano /etc/systemd/resolved.conf   # Edit resolved config"
    print_message "systemctl restart systemd-resolved     # Restart resolved"
    print_message "ls -la /etc/resolv.conf                # Check resolv.conf symlink"
fi
print_message "sudo crontab -l"
if [ "$OS" = "debian" ]; then
    print_message "sudo nano /etc/default/grub"
    print_message "cat /proc/cmdline"
fi
if [ "$CONFIGURE_SWAP" = "y" ] || [ "$CONFIGURE_SWAP" = "Y" ]; then
    print_message "sudo swap-setup.sh --status    # Check swap"
    print_message "sudo swap-setup.sh --remove    # Remove swap"
fi
if [ "$INSTALL_MOTD" = "y" ] || [ "$INSTALL_MOTD" = "Y" ]; then
    print_message "run-parts /etc/update-motd.d/  # Test MOTD"
fi
if [ ! -z "$NEW_USERNAME" ]; then
    print_message "su - $NEW_USERNAME"
fi
print_warning "$STEP_NUM. Reboot system to apply all changes: sudo reboot"

if final_exit_code; then
    exit 0
fi
exit 1
