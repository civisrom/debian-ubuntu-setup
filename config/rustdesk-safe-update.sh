#!/bin/bash
# Resolve the latest RustDesk digest, deploy it, and roll back on failure.

set -euo pipefail
umask 077

readonly RUSTDESK_DIR="/opt/rustdesk"
readonly ENV_FILE="${RUSTDESK_DIR}/.env"
readonly IMAGE_REPOSITORY="rustdesk/rustdesk-server"
readonly LOCK_FILE="/run/lock/rustdesk-update.lock"

cd "$RUSTDESK_DIR"
command -v docker >/dev/null 2>&1
command -v flock >/dev/null 2>&1

exec 9>"$LOCK_FILE"
flock -n 9 || { echo "RustDesk update already running" >&2; exit 75; }

current_image=$(docker compose config --images | head -1)
current_digest="${current_image##*@}"

latest_digest=$(docker buildx imagetools inspect "${IMAGE_REPOSITORY}:latest" \
    --format '{{json .Manifest.Digest}}' | tr -d '"[:space:]')
if ! [[ "$latest_digest" =~ ^sha256:[0-9a-f]{64}$ ]]; then
    echo "Invalid latest RustDesk digest: $latest_digest" >&2
    exit 1
fi

if [ "$latest_digest" = "$current_digest" ]; then
    echo "RustDesk already uses latest digest: $latest_digest"
    exit 0
fi

new_image="${IMAGE_REPOSITORY}@${latest_digest}"
env_backup=$(mktemp "${RUSTDESK_DIR}/.env.backup.XXXXXX")
if [ -f "$ENV_FILE" ]; then
    cp -- "$ENV_FILE" "$env_backup"
else
    : > "$env_backup"
fi

env_tmp=$(mktemp "${RUSTDESK_DIR}/.env.new.XXXXXX")
grep -v '^RUSTDESK_IMAGE=' "$env_backup" > "$env_tmp" || true
printf 'RUSTDESK_IMAGE=%s\n' "$new_image" >> "$env_tmp"
chmod 0600 "$env_tmp"
mv -f -- "$env_tmp" "$ENV_FILE"

rollback() {
    echo "RustDesk update failed; restoring $current_image" >&2
    if [ -s "$env_backup" ]; then
        cp -- "$env_backup" "$ENV_FILE"
    else
        printf 'RUSTDESK_IMAGE=%s\n' "$current_image" > "$ENV_FILE"
        chmod 0600 "$ENV_FILE"
    fi
    docker compose up -d --wait --remove-orphans || true
}

if ! docker compose pull; then
    rollback
    rm -f -- "$env_backup"
    exit 1
fi

if ! docker compose up -d --wait --remove-orphans; then
    rollback
    rm -f -- "$env_backup"
    exit 1
fi

running_services=$(docker compose ps --services --status running | sort)
if [ "$running_services" != $'hbbr\nhbbs' ]; then
    echo "RustDesk post-update service check failed" >&2
    rollback
    rm -f -- "$env_backup"
    exit 1
fi

rm -f -- "$env_backup"
docker image prune -f || true
echo "RustDesk updated successfully: $current_digest -> $latest_digest"
