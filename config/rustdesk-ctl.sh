#!/bin/bash
# Manage the RustDesk server installed by system-setup.sh: version, health
# status, and the hbbs/hbbr key pair (-k _).

set -euo pipefail
umask 077

readonly RUSTDESK_DIR="/opt/rustdesk"
readonly DATA_DIR="${RUSTDESK_DIR}/data"
readonly BACKUP_ROOT="${RUSTDESK_DIR}/key-backups"
readonly IMAGE_REPOSITORY="rustdesk/rustdesk-server"
# Shared with rustdesk-safe-update.sh so an update and a rotation never overlap.
readonly LOCK_FILE="${RUSTDESK_DIR}/.update.lock"
readonly WAIT_SECONDS=30
readonly SERVICES=(hbbs hbbr)
readonly TCP_PORTS=(21115 21116 21117)
readonly UDP_PORTS=(21116)

usage() {
    cat <<'EOF'
Usage: rustdesk-ctl version
       rustdesk-ctl status
       rustdesk-ctl key show
       rustdesk-ctl key rotate [--yes]

  version     Show the pinned image, the running hbbs/hbbr versions and
              whether Docker Hub has a newer rustdesk-server image.
  status      Check the systemd services, containers, listening ports, the
              loaded key and recent errors. Exit code 1 if something failed.
  key show    Print the public key that clients enter in the "Key" field.
  key rotate  Back up the current key pair to /opt/rustdesk/key-backups/,
              generate a new one and restart hbbs/hbbr. Clients that still
              use the old public key can no longer use this server; enter the
              new key on every client you own.
EOF
}

die() {
    echo "rustdesk-ctl: $*" >&2
    exit 1
}

require_root() {
    [ "$(id -u)" -eq 0 ] || die "run as root"
    command -v docker >/dev/null 2>&1 || die "docker is not installed"
    [ -f "${RUSTDESK_DIR}/docker-compose.yml" ] || die "${RUSTDESK_DIR}/docker-compose.yml not found"
    cd "$RUSTDESK_DIR"
}

read_public_key() {
    local key
    [ -s "${DATA_DIR}/id_ed25519.pub" ] || return 1
    key=$(< "${DATA_DIR}/id_ed25519.pub")
    printf '%s\n' "$key"
}

pinned_image() {
    local images
    images=$(docker compose config --images)
    printf '%s\n' "${images%%$'\n'*}"
}

# Both containers log "Key: <public key>" once they have loaded the key file.
has_loaded_key() {
    docker compose logs --no-log-prefix "$1" 2>/dev/null | grep -qF "Key: $2"
}

# ---------------------------------------------------------------- version

show_version() {
    local image latest service
    require_root
    image=$(pinned_image)
    echo "Pinned image:  ${image}"
    for service in "${SERVICES[@]}"; do
        printf '%-14s ' "${service}:"
        docker compose exec -T "$service" "$service" --version 2>/dev/null || echo "not running"
    done
    if latest=$(docker buildx imagetools inspect "${IMAGE_REPOSITORY}:latest" \
            --format '{{json .Manifest.Digest}}' 2>/dev/null | tr -d '"[:space:]') &&
       [[ "$latest" =~ ^sha256:[0-9a-f]{64}$ ]]; then
        echo "Latest image:  ${IMAGE_REPOSITORY}@${latest}"
        if [ "${image##*@}" = "$latest" ]; then
            echo "Update:        not needed, the latest image is in use"
        else
            echo "Update:        available (systemctl start rustdesk-update.service)"
        fi
    else
        echo "Latest image:  unknown (Docker Hub is unreachable)"
    fi
}

# ----------------------------------------------------------------- status

failures=0
warnings=0
ok()   { printf '  [ OK ] %s\n' "$*"; }
warn() { printf '  [WARN] %s\n' "$*"; warnings=$((warnings + 1)); }
fail() { printf '  [FAIL] %s\n' "$*"; failures=$((failures + 1)); }

show_status() {
    local service state restarts started key port mode errors result last
    require_root

    echo "systemd:"
    if systemctl is-enabled --quiet rustdesk-compose.service 2>/dev/null; then
        ok "rustdesk-compose.service is enabled"
    else
        fail "rustdesk-compose.service is not enabled"
    fi
    state=$(systemctl show -p ActiveState --value rustdesk-compose.service 2>/dev/null || true)
    if [ "$state" = active ]; then
        ok "rustdesk-compose.service is active"
    else
        fail "rustdesk-compose.service is ${state:-unknown} (journalctl -u rustdesk-compose.service)"
    fi
    if systemctl is-enabled --quiet rustdesk-update.timer 2>/dev/null; then
        ok "rustdesk-update.timer is enabled, next run: $(systemctl show -p NextElapseUSecRealtime --value rustdesk-update.timer 2>/dev/null)"
        result=$(systemctl show -p Result --value rustdesk-update.service 2>/dev/null || true)
        last=$(systemctl show -p ExecMainExitTimestamp --value rustdesk-update.service 2>/dev/null || true)
        if [ -z "$last" ] || [ "$last" = n/a ]; then
            ok "auto-update has not run since boot"
        elif [ "$result" = success ]; then
            ok "last auto-update (${last}): success"
        else
            warn "last auto-update (${last}): ${result:-unknown} (journalctl -u rustdesk-update.service)"
        fi
    else
        warn "rustdesk-update.timer is not enabled (no automatic updates)"
    fi

    echo "containers:"
    for service in "${SERVICES[@]}"; do
        if ! state=$(docker inspect -f '{{.State.Status}} {{.RestartCount}} {{.State.StartedAt}}' "$service" 2>/dev/null); then
            fail "${service}: container does not exist"
            continue
        fi
        read -r state restarts started <<< "$state"
        if [ "$state" != running ]; then
            fail "${service}: ${state}"
        elif [ "$restarts" -gt 0 ]; then
            warn "${service}: running, but restarted ${restarts} time(s) since ${started}"
        else
            ok "${service}: running since ${started}"
        fi
    done

    echo "ports:"
    if command -v ss >/dev/null 2>&1; then
        for port in "${TCP_PORTS[@]}"; do
            if ss -Hltn "sport = :${port}" | grep -q .; then ok "tcp/${port} listening"; else fail "tcp/${port} not listening"; fi
        done
        for port in "${UDP_PORTS[@]}"; do
            if ss -Hlun "sport = :${port}" | grep -q .; then ok "udp/${port} listening"; else fail "udp/${port} not listening"; fi
        done
    else
        warn "ss is not installed; ports not checked"
    fi

    echo "key:"
    if key=$(read_public_key); then
        ok "public key: ${key}"
        for service in "${SERVICES[@]}"; do
            if has_loaded_key "$service" "$key"; then
                ok "${service} uses this key"
            else
                fail "${service} did not log this key (restart: systemctl restart rustdesk-compose.service)"
            fi
        done
    else
        fail "no public key in ${DATA_DIR}"
    fi
    mode=$(stat -c %a "$DATA_DIR" 2>/dev/null || echo "?")
    if [ "$mode" = 700 ]; then
        ok "${DATA_DIR} is private (700)"
    else
        warn "${DATA_DIR} has mode ${mode}; the private key is readable by other users (chmod 700 ${DATA_DIR})"
    fi

    echo "logs (last 24 h):"
    errors=$(docker compose logs --since 24h --no-log-prefix 2>&1 | grep -Ei 'error|panic|fatal' || true)
    if [ -z "$errors" ]; then
        ok "no errors"
    else
        warn "$(printf '%s\n' "$errors" | wc -l) error line(s); latest:"
        # Log lines may carry client-supplied text: drop terminal control characters.
        printf '%s\n' "$errors" | tail -n 5 | LC_ALL=C tr -cd '[:print:]\n' | sed 's/^/         /'
    fi

    echo
    if [ "$failures" -gt 0 ]; then
        echo "Result: ${failures} failure(s), ${warnings} warning(s)"
        return 1
    fi
    echo "Result: OK, ${warnings} warning(s)"
}

# -------------------------------------------------------------------- key

show_key() {
    read_public_key || die "no public key in ${DATA_DIR}; start rustdesk-compose.service first"
}

# Read by the EXIT trap, so they must be global.
backup_dir=""
keys_moved=false

restore() {
    echo "rustdesk-ctl: rotation failed; restoring the previous key" >&2
    docker compose down || true
    rm -f -- "${DATA_DIR}/id_ed25519" "${DATA_DIR}/id_ed25519.pub"
    mv -f -- "${backup_dir}/id_ed25519" "${backup_dir}/id_ed25519.pub" "${DATA_DIR}/" || return 1
    rmdir -- "$backup_dir" || true
    docker compose up -d --wait
}

finish() {
    local result=$?
    trap - EXIT INT TERM
    if [ "$result" -ne 0 ] && [ "$keys_moved" = true ]; then
        restore || echo "rustdesk-ctl: restore failed; the previous key is in ${backup_dir}" >&2
    fi
    exit "$result"
}

wait_for_loaded_key() {
    local i
    for ((i = 0; i < WAIT_SECONDS; i++)); do
        has_loaded_key "$1" "$2" && return 0
        sleep 1
    done
    echo "rustdesk-ctl: $1 did not load the expected key" >&2
    return 1
}

rotate_key() {
    local assume_yes="$1" answer old_key new_key i

    require_root
    command -v flock >/dev/null 2>&1 || die "flock is not installed"
    exec 9>"$LOCK_FILE"
    flock -n 9 || die "a RustDesk update or key rotation is already running"

    [ -s "${DATA_DIR}/id_ed25519" ] || die "no private key in ${DATA_DIR}; nothing to rotate"
    old_key=$(read_public_key) || die "no public key in ${DATA_DIR}"

    if [ "$assume_yes" != true ]; then
        [ -t 0 ] || die "refusing to rotate without a terminal; use --yes"
        echo "Current public key: ${old_key}"
        echo "Rotation disconnects every client until it is given the new key."
        read -r -p "Type 'yes' to rotate the RustDesk key: " answer
        [ "$answer" = yes ] || die "aborted"
    fi

    mkdir -p "$BACKUP_ROOT"
    chmod 0700 "$BACKUP_ROOT"
    backup_dir="${BACKUP_ROOT}/$(date -u +%Y%m%dT%H%M%SZ)"
    mkdir -m 0700 "$backup_dir" || die "backup directory ${backup_dir} already exists"

    trap finish EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    docker compose down
    keys_moved=true
    mv -- "${DATA_DIR}/id_ed25519" "${DATA_DIR}/id_ed25519.pub" "$backup_dir/"
    chmod 0700 "$DATA_DIR"

    # hbbr would create its own pair 300 ms after start if the file is still
    # missing, so let hbbs generate the pair alone before hbbr starts.
    docker compose up -d --wait --no-deps hbbs
    for ((i = 0; i < WAIT_SECONDS; i++)); do
        [ -s "${DATA_DIR}/id_ed25519.pub" ] && break
        sleep 1
    done
    new_key=$(read_public_key) || { echo "rustdesk-ctl: hbbs did not create a new key" >&2; exit 1; }
    [ "$new_key" != "$old_key" ] || { echo "rustdesk-ctl: the new key equals the old one" >&2; exit 1; }
    chmod 0600 "${DATA_DIR}/id_ed25519"

    docker compose up -d --wait
    wait_for_loaded_key hbbs "$new_key"
    wait_for_loaded_key hbbr "$new_key"

    keys_moved=false
    echo "RustDesk key rotated. Previous key pair: ${backup_dir}"
    echo "New public key (enter it in the \"Key\" field of every client):"
    printf '%s\n' "$new_key"
}

[ "$#" -le 3 ] || { usage >&2; exit 2; }
case "${1:-} ${2:-} ${3:-}" in
    "version  ")          show_version ;;
    "status  ")           show_status ;;
    "key show ")          show_key ;;
    "key rotate ")        rotate_key false ;;
    "key rotate --yes")   rotate_key true ;;
    "-h  "|"--help  "|"help  ") usage ;;
    *)                    usage >&2; exit 2 ;;
esac
