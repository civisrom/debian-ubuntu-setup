#!/bin/bash

set -euo pipefail

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

# Post-increment under errexit caused both the Docker wait loop and uninstall
# to abort on the first iteration. Keep the canonical implementation free of it.
if grep -nE '\(\((waited|removed)\+\+\)\)' \
    install-nft-docker-watch.sh config/nft-apply.sh system-setup.sh; then
    fail "unsafe post-increment remains under set -e"
fi

# Firewall replacement must be a single transaction, never a standalone flush.
if grep -nE '^[[:space:]]*nft[[:space:]]+flush[[:space:]]+ruleset' \
    system-setup.sh install-nft-docker-watch.sh config/nft-apply.sh; then
    fail "standalone nft flush ruleset remains"
fi

# The package stays opt-in, as required; selection is handled conditionally.
grep -q '^[[:space:]]*#ufw$' system-setup.sh || fail "ufw base package line changed"

# The EOL interim Ubuntu release must not be advertised as supported.
if grep -q 'Ubuntu 25\.10' system-setup.sh README.md; then
    fail "Ubuntu 25.10 is still advertised as supported"
fi

# Generated/installable scripts must retain executable modes in the repository.
[ -x config/nft-apply.sh ] || fail "config/nft-apply.sh is not executable"
[ -x config/rustdesk-safe-update.sh ] || fail "rustdesk-safe-update.sh is not executable"

assert_embedded_hash() {
    local source_file="$1"
    local variable_name="$2"
    local asset_file="$3"
    local expected actual

    expected=$(awk -F'"' -v name="$variable_name" '$0 ~ name "=" {print $2; exit}' "$source_file")
    actual=$(sha256sum "$asset_file" | awk '{print $1}')
    [ "$expected" = "$actual" ] || fail "$variable_name does not match $asset_file"
}

assert_embedded_hash install-nft-docker-watch.sh NFT_APPLY_SHA256 config/nft-apply.sh
assert_embedded_hash system-setup.sh NFT_WATCH_INSTALLER_SHA256 install-nft-docker-watch.sh
assert_embedded_hash system-setup.sh RUSTDESK_COMPOSE_SHA256 config/docker-compose.yml
assert_embedded_hash system-setup.sh RUSTDESK_SERVICE_SHA256 config/rustdesk-compose.service
assert_embedded_hash system-setup.sh RUSTDESK_UPDATE_SERVICE_SHA256 config/rustdesk-update.service
assert_embedded_hash system-setup.sh RUSTDESK_UPDATE_TIMER_SHA256 config/rustdesk-update.timer
assert_embedded_hash system-setup.sh RUSTDESK_UPDATE_SCRIPT_SHA256 config/rustdesk-safe-update.sh

grep -q 'SYSTEM_SETUP_REPOSITORY_COMMIT="$RESOLVED_COMMIT"' install.sh || \
    fail "install.sh does not pass its immutable commit to downloaded assets"
if grep -q 'rustdesk/rustdesk-server:latest' config/docker-compose.yml; then
    fail "RustDesk Compose image is not digest-pinned"
fi
grep -q 'readonly LOCK_FILE="/run/lock/nft-docker-watch.lock"' config/nft-apply.sh || \
    fail "canonical nftables lock is missing"
if grep -qE '7z[[:space:]]+x[[:space:]]+-p[^[:space:]]' system-setup.sh; then
    fail "archive password is exposed in a 7z command argument"
fi

printf 'Regression checks passed\n'
