#!/bin/bash

#############################################
# System Setup Script for Debian and Ubuntu
# Description: Initial package installation and system configuration
#############################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored messages
print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run as root"
    exit 1
fi

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION=$VERSION_ID
else
    print_error "Cannot detect OS"
    exit 1
fi

print_message "Detected OS: $OS $VERSION"

# Validate OS
if [ "$OS" != "debian" ] && [ "$OS" != "ubuntu" ]; then
    print_error "This script only supports Debian and Ubuntu"
    exit 1
fi

# Update package lists
print_message "Updating package lists..."
apt update

# Common packages for both Debian and Ubuntu
COMMON_PACKAGES=(
    htop
    wget
    iptables
    ufw
    mc
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
    tilda
    ca-certificates
    lsb-release
    traceroute
    cron
    software-properties-common
    pwgen
    libwww-perl
    apg
    makepasswd
    mc-data
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
)

# Debian-specific packages
DEBIAN_PACKAGES=(
#    openvswitch-switch-dpdk
)

# Ubuntu-specific packages
UBUNTU_PACKAGES=(
    landscape-common
    update-notifier-common
    ubuntu-keyring
    openvswitch-switch-dpdk
)

# Install packages based on OS
print_message "Installing packages..."

if [ "$OS" = "debian" ]; then
    print_message "Installing common packages for Debian..."
    apt install -y "${COMMON_PACKAGES[@]}"
    
    print_message "Installing Debian-specific packages..."
    apt install -y "${DEBIAN_PACKAGES[@]}" || print_warning "Some Debian-specific packages may not be available"
    
elif [ "$OS" = "ubuntu" ]; then
    print_message "Installing common packages for Ubuntu..."
    apt install -y "${COMMON_PACKAGES[@]}"
    
    print_message "Installing Ubuntu-specific packages..."
    apt install -y "${UBUNTU_PACKAGES[@]}" || print_warning "Some Ubuntu-specific packages may not be available"
fi

# Configure sources.list for Debian only
if [ "$OS" = "debian" ]; then
    print_message "Configuring Debian repositories..."
    
    # Backup original sources.list
    if [ -f /etc/apt/sources.list ]; then
        cp /etc/apt/sources.list /etc/apt/sources.list.backup.$(date +%Y%m%d-%H%M%S)
        print_message "Original sources.list backed up"
    fi
    
    # Write new sources.list
    cat > /etc/apt/sources.list << 'EOF'
### Основные репозитории
deb     http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware

### Обновления безопасности
deb     http://deb.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware

### Обновления стабильного релиза
deb     http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware

### Backports (новые версии пакетов)
deb     http://deb.debian.org/debian bookworm-backports main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian bookworm-backports main contrib non-free non-free-firmware
EOF
    
    print_message "Debian repositories configured"
    apt update
fi

# Configure sysctl.conf
print_message "Configuring system parameters (sysctl.conf)..."

# Backup original sysctl.conf
if [ -f /etc/sysctl.conf ]; then
    cp /etc/sysctl.conf /etc/sysctl.conf.backup.$(date +%Y%m%d-%H%M%S)
    print_message "Original sysctl.conf backed up"
fi

# Remove only uncommented lines and preserve comments
grep '^#' /etc/sysctl.conf > /etc/sysctl.conf.new 2>/dev/null || true
grep '^$' /etc/sysctl.conf >> /etc/sysctl.conf.new 2>/dev/null || true

# Add new configuration
cat >> /etc/sysctl.conf.new << 'EOF'

# Custom Network Optimizations
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.wmem_default = 2097152
net.core.netdev_max_backlog = 10240
net.core.somaxconn = 8192
net.ipv4.tcp_syncookies = 1
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
fs.inotify.max_user_instances = 8192
net.ipv4.ip_local_port_range = 1024 45000
EOF

mv /etc/sysctl.conf.new /etc/sysctl.conf
print_message "sysctl.conf configured"

# Apply sysctl settings
print_message "Applying sysctl settings..."
sysctl -p

# Configure UFW
print_message "Configuring UFW firewall..."

# Allow SSH (port 22)
ufw allow 22/tcp comment 'SSH'
print_message "UFW rule added: Allow SSH (port 22)"

# Ask for additional port
read -p "Enter additional port to allow (or press Enter to skip): " CUSTOM_PORT

if [ ! -z "$CUSTOM_PORT" ]; then
    if [[ "$CUSTOM_PORT" =~ ^[0-9]+$ ]] && [ "$CUSTOM_PORT" -ge 1 ] && [ "$CUSTOM_PORT" -le 65535 ]; then
        ufw allow $CUSTOM_PORT/tcp comment "Custom port"
        print_message "UFW rule added: Allow port $CUSTOM_PORT"
    else
        print_warning "Invalid port number. Skipping custom port."
    fi
fi

# Enable UFW
print_message "Enabling UFW..."
echo "y" | ufw enable
ufw status verbose

# Install ufw-docker
print_message "Installing ufw-docker..."

if wget -O /usr/local/bin/ufw-docker https://github.com/chaifeng/ufw-docker/raw/master/ufw-docker; then
    chmod +x /usr/local/bin/ufw-docker
    print_message "ufw-docker installed successfully"
    
    # Run ufw-docker install
    print_message "Configuring ufw-docker..."
    /usr/local/bin/ufw-docker install
    print_message "ufw-docker configured successfully"
else
    print_error "Failed to download ufw-docker"
fi

# Final message
print_message "========================================="
print_message "System setup completed successfully!"
print_message "========================================="
print_message "Summary:"
print_message "- Packages installed"
print_message "- System parameters optimized (sysctl.conf)"
if [ "$OS" = "debian" ]; then
    print_message "- Debian repositories configured"
fi
print_message "- UFW firewall configured and enabled"
print_message "- ufw-docker installed and configured"
print_message ""
print_message "Please review the changes and reboot the system if needed."
print_message "Backup files are saved with timestamp in the same directory."

exit 0
