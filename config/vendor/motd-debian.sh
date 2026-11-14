#!/bin/bash
# Source: https://raw.githubusercontent.com/civisrom/motd-ubuntu-debian/11f4fb44c4e8f906059212b99661156bac3f059e/scripts/debian.sh
# Local safety fixes; see README.md in this directory.
set -euo pipefail

# Check if running as root
if [ "$EUID" -ne 0 ]; then
	echo "Error: This script must be run as root (use sudo)"
	exit 1
fi

#clear
echo "Hi! This script will install custom MOTD for your Debian"
read -p "Continue? [Y/n] " -r REPLY || exit 0
if [[ $REPLY =~ ^[Yy]?$ ]] || [ -z "$REPLY" ]; then
    [[ ! -L /etc/update-motd.d ]] || { echo "MOTD directory must not be a symlink" >&2; exit 1; }
    WORK=$(mktemp -d)
    chmod 700 "$WORK"
    BACKUP=''
    BACKUP_READY=false
    STATIC_MOTD_EXISTED=false
    cleanup() {
        local rc=$?
        trap - EXIT INT TERM
        if ((rc != 0)) && [[ $BACKUP_READY == true ]]; then
            rm -rf -- /etc/update-motd.d
            cp -a "$BACKUP/update-motd.d" /etc/update-motd.d || rc=1
            if [[ -f $BACKUP/sshd_config ]]; then
                cp -p "$BACKUP/sshd_config" /etc/ssh/sshd_config || rc=1
            fi
            if [[ $STATIC_MOTD_EXISTED == true ]]; then
                rm -f /etc/motd
                cp -a "$BACKUP/static-motd" /etc/motd || rc=1
            else
                rm -f /etc/motd
            fi
            echo "MOTD installation failed; recovery backup: $BACKUP" >&2
        fi
        rm -rf -- "$WORK"
        exit "$rc"
    }
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    MOTD_COMMIT=11f4fb44c4e8f906059212b99661156bac3f059e
    MOTD_ARCHIVE_SHA256=36d3de568141f13322d57ce78bb8988d4f2fc138909fb08c88bdabe88806504e
    SOURCE="$WORK/motd-ubuntu-debian-$MOTD_COMMIT"
	# Install packages
	echo "Installing utilities (this may take up to 10 seconds):"
	echo -n "    - updating repos....."
	apt-get update >> /dev/null 2>&1
	echo "done"
	echo -n "    - toilet............."
	apt-get install toilet -y >> /dev/null 2>&1
	echo "done"
	echo -n "    - colorized-logs....."
	apt-get install colorized-logs -y >> /dev/null 2>&1
	echo "done"
	echo -n "    - lsb-release........"
	apt-get install lsb-release -y >> /dev/null 2>&1
	echo "done"
	echo "Utilities installed successfully"

	# Download the archive
	echo "Downloading motd"
	if ! curl -fsSL --proto '=https' --tlsv1.2 --connect-timeout 20 --max-time 300 \
        "https://codeload.github.com/civisrom/motd-ubuntu-debian/tar.gz/$MOTD_COMMIT" -o "$WORK/motd.tar.gz" ||
       ! printf '%s  %s\n' "$MOTD_ARCHIVE_SHA256" "$WORK/motd.tar.gz" | sha256sum -c --status ||
       ! tar -xzf "$WORK/motd.tar.gz" -C "$WORK"; then
		echo "Error: Failed to download or extract archive"
		exit 1
	fi

	# Verify extracted files exist
	if [ ! -d "$SOURCE/motd" ]; then
		echo "Error: Archive does not contain expected motd directory"
		exit 1
	fi

	# Move old motd files to directory
	mkdir -p /var/backups/system-setup /etc/update-motd.d
    BACKUP=$(mktemp -d /var/backups/system-setup/motd.XXXXXXXX)
    cp -a /etc/update-motd.d "$BACKUP/"
    if [[ -e /etc/motd || -L /etc/motd ]]; then cp -a /etc/motd "$BACKUP/static-motd"; STATIC_MOTD_EXISTED=true; fi
    BACKUP_READY=true
    echo "Previous MOTD saved to $BACKUP"
    find /etc/update-motd.d/ -maxdepth 1 \( -type f -o -type l \) -exec rm -- {} \;

	# Move unzipped motd files to /etc
	echo "Installing motd"
	if ! cp "$SOURCE"/motd/* /etc/update-motd.d/; then
		echo "Error: Failed to install MOTD files"
		exit 1
	fi

	# Disable duplicate MOTD display by SSH daemon
	echo "Configuring SSH"
    if [ -f /etc/ssh/sshd_config ]; then
        cp -p /etc/ssh/sshd_config "$BACKUP/sshd_config"
        { printf 'PrintMotd no\n'; sed '/^[[:space:]]*PrintMotd[[:space:]]/d' /etc/ssh/sshd_config; } > "$WORK/sshd_config"
        if ! /usr/sbin/sshd -t -f "$WORK/sshd_config"; then
            echo "Error: SSH configuration validation failed" >&2
            exit 1
        fi
        cat "$WORK/sshd_config" > /etc/ssh/sshd_config
    fi

	# Remove static /etc/motd to prevent duplicate display via pam_motd noupdate
	rm -f /etc/motd 2>/dev/null
	touch /etc/motd

	# Verify critical files were installed
	if [ ! -f "/etc/update-motd.d/colors.txt" ] || [ ! -f "/etc/update-motd.d/00-header" ]; then
		echo "Error: MOTD files were not installed correctly"
		exit 1
	fi

	echo "Setting permissions"
	chmod 755 /etc/update-motd.d/[0-9][0-9]-*
	chmod 644 /etc/update-motd.d/colors.txt /etc/update-motd.d/ivrit.flf

	# Prompt for custom name
	echo ""
    IFS= read -p "Enter your name for MOTD header: " -r MOTD_NAME || MOTD_NAME=''
    MOTD_NAME=${MOTD_NAME:-you name}
    MOTD_NAME=${MOTD_NAME:0:50}
    printf '%s\n' "$MOTD_NAME" > /etc/update-motd.d/header-name.txt
    chmod 0644 /etc/update-motd.d/header-name.txt
    sed -i 's/you name/${MOTD_HEADER_NAME}/g' /etc/update-motd.d/00-header
    sed -i '2a MOTD_HEADER_NAME="you name"; IFS= read -r MOTD_HEADER_NAME < /etc/update-motd.d/header-name.txt || true' /etc/update-motd.d/00-header
    # The public-IP lookup runs at login; use authenticated HTTPS.
    sed -i 's/curl -s --max-time 2 ifconfig.me/curl -fsS --max-time 2 https:\/\/ifconfig.me/' /etc/update-motd.d/11-processes

    # ip link displays peer suffixes that ip addr does not accept as names.
    sed -i '/^for iface in .*ip -o link show/a\    iface=${iface%%@*}' /etc/update-motd.d/11-processes
    # Only inspect certificate files, never generic PEM files or private directories.
    sed -i '/done < <(find "$dir"/c\        done < <(find "$dir" -regextype posix-extended \\( -type d \\( -iname private -o -iname keys -o -iname accounts \\) -prune \\) -o \\( -type f ! -iname "*key*" \\( -name "*.crt" -o -regex ".*/(cert|chain|fullchain)[0-9]*[.]pem" \\) -print0 \\) 2>/dev/null)' /etc/update-motd.d/11-processes
    # A process count does not need command arguments, which may contain secrets.
    sed -i 's/ps -ef | tail -n +2/ps -e -o pid=/' /etc/update-motd.d/08-processes

	# Clean up downloaded files
	echo "Cleaning up"


	echo "Done!"
else

	echo "Installation has been cancelled. Bye!"
fi
