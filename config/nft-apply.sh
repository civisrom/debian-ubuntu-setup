#!/bin/bash
# Atomically apply /etc/nftables.conf after Docker is ready.

set -euo pipefail
umask 077

readonly NFT_CONF="${NFT_CONF:-/etc/nftables.conf}"
readonly NFT_BACKUP_DIR="${NFT_BACKUP_DIR:-/var/backups/nftables}"
readonly DOCKER_WAIT_TIMEOUT="${DOCKER_WAIT_TIMEOUT:-60}"
readonly DOCKER_SETTLE_DELAY="${DOCKER_SETTLE_DELAY:-2}"
readonly LOG_TAG="nft-apply"
readonly LOCK_FILE="/run/lock/nft-docker-watch.lock"

log() {
    local message="$1"
    local priority="${2:-info}"

    printf '%s\n' "$message" | systemd-cat -t "$LOG_TAG" -p "$priority" 2>/dev/null || true
    printf '%s\n' "$message"
}

build_transaction() {
    local source_file="$1"
    local transaction_file="$2"

    {
        printf 'flush ruleset\n'
        sed '1{/^#!/d;}' "$source_file"
    } > "$transaction_file"
}

rollback_ruleset() {
    local backup_file="$1"
    local rollback_file="$2"

    build_transaction "$backup_file" "$rollback_file"
    nft -c -f "$rollback_file" >/dev/null 2>&1
    nft -f "$rollback_file"
}

command -v nft >/dev/null 2>&1 || { log "ERROR: nft command not found" err; exit 1; }
command -v flock >/dev/null 2>&1 || { log "ERROR: flock command not found" err; exit 1; }
[ -s "$NFT_CONF" ] || { log "ERROR: missing or empty $NFT_CONF" err; exit 1; }

mkdir -p "$NFT_BACKUP_DIR"
chmod 0700 "$NFT_BACKUP_DIR"

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    log "Another nftables apply operation is already running" warning
    exit 75
fi

transaction_file=$(mktemp "${NFT_BACKUP_DIR}/transaction.XXXXXX.nft")
rollback_file=$(mktemp "${NFT_BACKUP_DIR}/rollback.XXXXXX.nft")
cleanup() {
    rm -f -- "$transaction_file" "$rollback_file"
}
trap cleanup EXIT INT TERM HUP

log "Waiting for Docker readiness (timeout: ${DOCKER_WAIT_TIMEOUT}s)..."
waited=0
while ! docker info >/dev/null 2>&1; do
    if [ "$waited" -ge "$DOCKER_WAIT_TIMEOUT" ]; then
        log "Docker did not become ready in ${DOCKER_WAIT_TIMEOUT}s; applying rules without it" warning
        break
    fi
    sleep 1
    ((++waited))
done

if [ "$waited" -lt "$DOCKER_WAIT_TIMEOUT" ]; then
    log "Docker ready after ${waited}s; waiting ${DOCKER_SETTLE_DELAY}s for networks"
    sleep "$DOCKER_SETTLE_DELAY"
fi

build_transaction "$NFT_CONF" "$transaction_file"
log "Validating atomic nftables transaction"
if ! nft_error=$(nft -c -f "$transaction_file" 2>&1); then
    log "Validation failed; live rules were not changed" err
    log "$nft_error" err
    exit 1
fi

backup_file=$(mktemp "${NFT_BACKUP_DIR}/ruleset-$(date +%Y%m%d-%H%M%S).XXXXXX.nft")
if ! nft list ruleset > "$backup_file" 2>/dev/null; then
    rm -f -- "$backup_file"
    log "Could not snapshot the live ruleset; refusing to apply without rollback" err
    exit 1
fi
log "Live ruleset backup: $backup_file"

if ! nft_error=$(nft -f "$transaction_file" 2>&1); then
    log "Atomic nftables apply failed; restoring previous ruleset" err
    log "$nft_error" err
    if rollback_ruleset "$backup_file" "$rollback_file"; then
        log "Rollback completed" warning
    else
        log "CRITICAL: rollback failed; use console access immediately" crit
    fi
    exit 1
fi

verification_failed=false
for table_spec in "ip filter" "ip dockernat" "ip6 filter"; do
    read -r family table_name <<< "$table_spec"
    if ! nft list table "$family" "$table_name" >/dev/null 2>&1; then
        log "Required table is missing after apply: table $family $table_name" err
        verification_failed=true
    fi
done

if [ "$verification_failed" = true ]; then
    if rollback_ruleset "$backup_file" "$rollback_file"; then
        log "Postcondition failed; previous ruleset restored" err
    else
        log "CRITICAL: postcondition failed and rollback failed" crit
    fi
    exit 1
fi

# Keep only the ten newest persistent snapshots. Temporary transaction files
# use different names and are removed by the trap.
find "$NFT_BACKUP_DIR" -maxdepth 1 -type f -name 'ruleset-*.nft' -printf '%T@ %p\0' \
    | sort -z -nr \
    | tail -z -n +11 \
    | cut -z -d' ' -f2- \
    | xargs -0r rm -f

log "nftables rules applied and verified successfully"
