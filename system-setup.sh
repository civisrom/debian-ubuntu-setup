#!/bin/bash

#############################################
# System Setup Script for Debian and Ubuntu
# Author: Auto-generated
# Description: Initial package installation and system configuration
#############################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

print_header() {
    echo -e "${BLUE}$1${NC}"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run as root"
    exit 1
fi

# Detect if running interactively
if [ -t 0 ]; then
    INTERACTIVE=true
else
    INTERACTIVE=false
    print_warning "Running in non-interactive mode with default settings"
fi

# Print banner
echo ""
print_header "╔═══════════════════════════════════════════════╗"
print_header "║   Debian/Ubuntu System Setup Script          ║"
print_header "║   Initial Configuration Tool                  ║"
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
if [ -z "$DETECTED_OS" ] || { [ "$OS" != "debian" ] && [ "$OS" != "ubuntu" ]; }; then
    if [ "$INTERACTIVE" = true ]; then
        print_warning "Cannot detect OS or OS is not supported"
        echo ""
        print_message "Please select the operating system:"
        echo "  1) Debian 12 (Bookworm)"
        echo "  2) Ubuntu 24.04 (Noble)"
        echo ""
        read -p "Enter your choice [1-2]: " OS_CHOICE
        
        case $OS_CHOICE in
            1)
                OS="debian"
                VERSION="12"
                VERSION_CODENAME="bookworm"
                print_message "Selected: Debian 12 (Bookworm)"
                ;;
            2)
                OS="ubuntu"
                VERSION="24.04"
                VERSION_CODENAME="noble"
                print_message "Selected: Ubuntu 24.04 (Noble)"
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
    VERSION_CODENAME=${VERSION_CODENAME:-unknown}
    
    # Validate OS
    if [ "$OS" != "debian" ] && [ "$OS" != "ubuntu" ]; then
        print_error "This script only supports Debian and Ubuntu"
        exit 1
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
    # Ask about Docker installation
    print_message "Do you want to install Docker?"
    read -p "Install Docker? (y/N): " INSTALL_DOCKER
    INSTALL_DOCKER=${INSTALL_DOCKER:-n}
    
    # Ask about UFW configuration
    print_message "Do you want to configure UFW firewall?"
    read -p "Configure UFW? (Y/n): " CONFIGURE_UFW
    CONFIGURE_UFW=${CONFIGURE_UFW:-y}
    
    # Ask about ufw-docker (only if Docker will be installed)
    if [ "$INSTALL_DOCKER" = "y" ] || [ "$INSTALL_DOCKER" = "Y" ]; then
        print_message "Do you want to install ufw-docker (UFW integration for Docker)?"
        read -p "Install ufw-docker? (Y/n): " INSTALL_UFW_DOCKER
        INSTALL_UFW_DOCKER=${INSTALL_UFW_DOCKER:-y}
    else
        INSTALL_UFW_DOCKER="n"
    fi
    
    # Ask about sysctl configuration
    print_message "Do you want to optimize system parameters (sysctl.conf)?"
    read -p "Configure sysctl? (Y/n): " CONFIGURE_SYSCTL
    CONFIGURE_SYSCTL=${CONFIGURE_SYSCTL:-y}
    
    # Ask about repository configuration (Debian only)
    if [ "$OS" = "debian" ]; then
        print_message "Do you want to configure Debian repositories?"
        read -p "Configure repositories? (Y/n): " CONFIGURE_REPOS
        CONFIGURE_REPOS=${CONFIGURE_REPOS:-y}
    else
        CONFIGURE_REPOS="n"
    fi
    
    # Ask about MOTD installation
    print_message "Do you want to install custom MOTD (Message of the Day)?"
    read -p "Install MOTD? (y/N): " INSTALL_MOTD
    INSTALL_MOTD=${INSTALL_MOTD:-n}
    
    # Ask for UFW ports (if UFW is enabled)
    if [ "$CONFIGURE_UFW" = "y" ] || [ "$CONFIGURE_UFW" = "Y" ]; then
        echo ""
        print_message "UFW Firewall Configuration"
        print_message "Port 22 (SSH) will be allowed automatically"
        echo ""
        read -p "Enter additional port to allow (press Enter to skip): " CUSTOM_PORT
    else
        CUSTOM_PORT=""
    fi
else
    # Default settings for non-interactive mode
    INSTALL_DOCKER="n"
    CONFIGURE_UFW="y"
    INSTALL_UFW_DOCKER="y"
    CONFIGURE_SYSCTL="y"
    CONFIGURE_REPOS="y"
    INSTALL_MOTD="n"
    CUSTOM_PORT=""
    
    print_message "Non-interactive mode - using default settings:"
    print_message "- Docker: NO"
    print_message "- UFW: YES"
    print_message "- ufw-docker: YES (if Docker present)"
    print_message "- sysctl: YES"
    print_message "- Repositories: YES (Debian only)"
    print_message "- MOTD: NO"
    print_message "- Custom UFW Port: None"
fi
echo ""

# Confirm settings
print_header "═══════════════════════════════════════════════"
print_message "Configuration Summary:"
print_message "  OS: $OS $VERSION ($VERSION_CODENAME)"
print_message "  Docker: $([ "$INSTALL_DOCKER" = "y" ] || [ "$INSTALL_DOCKER" = "Y" ] && echo "YES" || echo "NO")"
print_message "  UFW Firewall: $([ "$CONFIGURE_UFW" = "y" ] || [ "$CONFIGURE_UFW" = "Y" ] && echo "YES" || echo "NO")"
if [ "$INSTALL_DOCKER" = "y" ] || [ "$INSTALL_DOCKER" = "Y" ]; then
    print_message "  ufw-docker: $([ "$INSTALL_UFW_DOCKER" = "y" ] || [ "$INSTALL_UFW_DOCKER" = "Y" ] && echo "YES" || echo "NO")"
fi
print_message "  sysctl optimization: $([ "$CONFIGURE_SYSCTL" = "y" ] || [ "$CONFIGURE_SYSCTL" = "Y" ] && echo "YES" || echo "NO")"
if [ "$OS" = "debian" ]; then
    print_message "  Debian repositories: $([ "$CONFIGURE_REPOS" = "y" ] || [ "$CONFIGURE_REPOS" = "Y" ] && echo "YES" || echo "NO")"
fi
print_message "  Custom MOTD: $([ "$INSTALL_MOTD" = "y" ] || [ "$INSTALL_MOTD" = "Y" ] && echo "YES" || echo "NO")"
if [ ! -z "$CUSTOM_PORT" ]; then
    print_message "  UFW Custom Port: $CUSTOM_PORT"
else
    print_message "  UFW Custom Port: None"
fi
print_header "═══════════════════════════════════════════════"
echo ""

if [ "$INTERACTIVE" = true ]; then
    read -p "Continue with these settings? (Y/n): " CONFIRM
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
    openvswitch-switch-dpdk
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
if [ "$OS" = "debian" ] && { [ "$CONFIGURE_REPOS" = "y" ] || [ "$CONFIGURE_REPOS" = "Y" ]; }; then
    print_message "Configuring Debian repositories..."
    
    # Backup original sources.list
    if [ -f /etc/apt/sources.list ]; then
        cp /etc/apt/sources.list /etc/apt/sources.list.backup.$(date +%Y%m%d-%H%M%S)
        print_message "Original sources.list backed up"
    fi
    
    # Use detected or selected codename
    DEBIAN_CODENAME=${VERSION_CODENAME:-bookworm}
    
    # Write new sources.list
    cat > /etc/apt/sources.list << EOF
### Основные репозитории
deb     http://deb.debian.org/debian ${DEBIAN_CODENAME} main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian ${DEBIAN_CODENAME} main contrib non-free non-free-firmware

### Обновления безопасности
deb     http://deb.debian.org/debian-security ${DEBIAN_CODENAME}-security main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian-security ${DEBIAN_CODENAME}-security main contrib non-free non-free-firmware

### Обновления стабильного релиза
deb     http://deb.debian.org/debian ${DEBIAN_CODENAME}-updates main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian ${DEBIAN_CODENAME}-updates main contrib non-free non-free-firmware

### Backports (новые версии пакетов)
deb     http://deb.debian.org/debian ${DEBIAN_CODENAME}-backports main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian ${DEBIAN_CODENAME}-backports main contrib non-free non-free-firmware
EOF
    
    print_message "Debian repositories configured for ${DEBIAN_CODENAME}"
    apt update
fi

# Configure sysctl.conf
if [ "$CONFIGURE_SYSCTL" = "y" ] || [ "$CONFIGURE_SYSCTL" = "Y" ]; then
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
else
    print_message "Skipping sysctl configuration (not requested)"
fi

# Configure UFW
if [ "$CONFIGURE_UFW" = "y" ] || [ "$CONFIGURE_UFW" = "Y" ]; then
    print_message "Configuring UFW firewall..."
    
    # Allow SSH (port 22)
    ufw allow 22/tcp comment 'SSH'
    print_message "UFW rule added: Allow SSH (port 22)"
    
    # Add custom port if specified
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
else
    print_message "Skipping UFW configuration (not requested)"
fi

# Install Docker if requested
if [ "$INSTALL_DOCKER" = "y" ] || [ "$INSTALL_DOCKER" = "Y" ]; then
    print_message "Installing Docker..."
    echo ""
    
    # Check if Docker is already installed
    if command -v docker &> /dev/null; then
        DOCKER_VERSION=$(docker --version 2>/dev/null || echo "unknown")
        print_warning "Docker is already installed: $DOCKER_VERSION"
        read -p "Do you want to reinstall Docker? (y/N): " REINSTALL_DOCKER
        REINSTALL_DOCKER=${REINSTALL_DOCKER:-n}
        
        if [ "$REINSTALL_DOCKER" != "y" ] && [ "$REINSTALL_DOCKER" != "Y" ]; then
            print_message "Skipping Docker installation"
            DOCKER_INSTALLED="yes"
        else
            print_message "Reinstalling Docker..."
            # Use Docker's official installation script
            if curl -fsSL https://get.docker.com -o /tmp/get-docker.sh; then
                sh /tmp/get-docker.sh
                rm /tmp/get-docker.sh
                print_message "Docker installed successfully"
                DOCKER_INSTALLED="yes"
            else
                print_error "Failed to download Docker installation script"
                DOCKER_INSTALLED="no"
            fi
        fi
    else
        # Install Docker using official script
        print_message "Downloading Docker installation script..."
        if curl -fsSL https://get.docker.com -o /tmp/get-docker.sh; then
            print_message "Running Docker installation script..."
            sh /tmp/get-docker.sh
            rm /tmp/get-docker.sh
            print_message "Docker installed successfully"
            DOCKER_INSTALLED="yes"
            
            # Start and enable Docker
            systemctl start docker
            systemctl enable docker
            
            # Add current user to docker group if not root
            if [ ! -z "$SUDO_USER" ]; then
                usermod -aG docker $SUDO_USER
                print_message "User $SUDO_USER added to docker group"
                print_warning "Please log out and log back in for docker group changes to take effect"
            fi
        else
            print_error "Failed to download Docker installation script"
            DOCKER_INSTALLED="no"
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
    fi
    
    echo ""
else
    print_message "Skipping Docker installation (not requested)"
    DOCKER_INSTALLED="no"
fi

# Install ufw-docker (only if Docker is installed and user wants it)
if command -v docker &> /dev/null; then
    if [ "$INSTALL_UFW_DOCKER" = "y" ] || [ "$INSTALL_UFW_DOCKER" = "Y" ]; then
        print_message "Docker detected. Installing ufw-docker..."
        
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
    else
        print_message "Skipping ufw-docker installation (not requested)"
    fi
else
    print_warning "Docker is not installed. Skipping ufw-docker installation."
    if [ "$INSTALL_DOCKER" = "y" ] || [ "$INSTALL_DOCKER" = "Y" ]; then
        print_warning "Note: Docker installation may have failed."
    fi
    print_warning "If you need Docker support later:"
    print_warning "  1. Install Docker first"
    print_warning "  2. Run: wget -O /usr/local/bin/ufw-docker https://github.com/chaifeng/ufw-docker/raw/master/ufw-docker"
    print_warning "  3. Run: chmod +x /usr/local/bin/ufw-docker"
    print_warning "  4. Run: ufw-docker install"
fi

# Install custom MOTD
if [ "$INSTALL_MOTD" = "y" ] || [ "$INSTALL_MOTD" = "Y" ]; then
    print_message "Installing custom MOTD (Message of the Day)..."
    echo ""
    
    MOTD_SCRIPT="/tmp/motd_install.sh"
    
    if [ "$OS" = "debian" ]; then
        MOTD_URL="https://raw.githubusercontent.com/civisrom/motd-ubuntu-debian/refs/heads/main/scripts/debian.sh"
    else
        MOTD_URL="https://raw.githubusercontent.com/civisrom/motd-ubuntu-debian/refs/heads/main/scripts/ubuntu.sh"
    fi
    
    print_message "Downloading MOTD installation script for $OS..."
    if curl -fsSL "$MOTD_URL" -o "$MOTD_SCRIPT"; then
        chmod +x "$MOTD_SCRIPT"
        print_message "Running MOTD installation script..."
        
        if bash "$MOTD_SCRIPT"; then
            print_message "Custom MOTD installed successfully"
            rm -f "$MOTD_SCRIPT"
        else
            print_warning "MOTD installation completed with warnings"
            rm -f "$MOTD_SCRIPT"
        fi
    else
        print_error "Failed to download MOTD installation script"
    fi
    
    echo ""
else
    print_message "Skipping MOTD installation (not requested)"
fi

# Final message
echo ""
print_header "═════════════════════════════════════════"
print_message "System setup completed successfully!"
print_header "═════════════════════════════════════════"
print_message "Summary:"
print_message "- OS: $OS $VERSION ($VERSION_CODENAME)"
print_message "- Packages installed"
if [ "$CONFIGURE_SYSCTL" = "y" ] || [ "$CONFIGURE_SYSCTL" = "Y" ]; then
    print_message "- System parameters optimized (sysctl.conf)"
else
    print_message "- sysctl: SKIPPED"
fi
if [ "$OS" = "debian" ] && { [ "$CONFIGURE_REPOS" = "y" ] || [ "$CONFIGURE_REPOS" = "Y" ]; }; then
    print_message "- Debian repositories configured"
fi
if [ "$CONFIGURE_UFW" = "y" ] || [ "$CONFIGURE_UFW" = "Y" ]; then
    print_message "- UFW firewall configured and enabled"
    if [ ! -z "$CUSTOM_PORT" ]; then
        print_message "- Custom UFW port: $CUSTOM_PORT"
    fi
else
    print_message "- UFW: SKIPPED"
fi
if command -v docker &> /dev/null; then
    print_message "- Docker: Installed"
    if [ "$INSTALL_UFW_DOCKER" = "y" ] || [ "$INSTALL_UFW_DOCKER" = "Y" ]; then
        if command -v ufw-docker &> /dev/null; then
            print_message "- ufw-docker: Installed and configured"
        else
            print_message "- ufw-docker: Installation attempted but not found"
        fi
    else
        print_message "- ufw-docker: Not installed (skipped by user)"
    fi
else
    print_message "- Docker: Not installed"
    if [ "$INSTALL_DOCKER" = "y" ] || [ "$INSTALL_DOCKER" = "Y" ]; then
        print_message "- Docker installation may have failed"
    fi
fi
if [ "$INSTALL_MOTD" = "y" ] || [ "$INSTALL_MOTD" = "Y" ]; then
    print_message "- Custom MOTD: Installed"
else
    print_message "- Custom MOTD: Not installed"
fi
print_message ""
if [ "$CONFIGURE_SYSCTL" = "y" ] || [ "$CONFIGURE_SYSCTL" = "Y" ] || [ "$CONFIGURE_REPOS" = "y" ] || [ "$CONFIGURE_REPOS" = "Y" ]; then
    print_message "Backup files saved with timestamp:"
    if [ "$CONFIGURE_SYSCTL" = "y" ] || [ "$CONFIGURE_SYSCTL" = "Y" ]; then
        print_message "- /etc/sysctl.conf.backup.*"
    fi
    if [ "$OS" = "debian" ] && { [ "$CONFIGURE_REPOS" = "y" ] || [ "$CONFIGURE_REPOS" = "Y" ]; }; then
        print_message "- /etc/apt/sources.list.backup.*"
    fi
    print_message ""
fi
print_warning "Recommended next steps:"
STEP_NUM=1
if [ "$CONFIGURE_UFW" = "y" ] || [ "$CONFIGURE_UFW" = "Y" ]; then
    print_warning "$STEP_NUM. Review UFW status: sudo ufw status verbose"
    STEP_NUM=$((STEP_NUM + 1))
fi
if [ "$CONFIGURE_SYSCTL" = "y" ] || [ "$CONFIGURE_SYSCTL" = "Y" ]; then
    print_warning "$STEP_NUM. Check sysctl: sysctl net.ipv4.tcp_congestion_control"
    STEP_NUM=$((STEP_NUM + 1))
fi
if command -v docker &> /dev/null && [ ! -z "$SUDO_USER" ]; then
    print_warning "$STEP_NUM. Log out and back in to use Docker without sudo"
    STEP_NUM=$((STEP_NUM + 1))
    print_warning "$STEP_NUM. Reboot system: sudo reboot"
else
    print_warning "$STEP_NUM. Reboot system if needed: sudo reboot"
fi

exit 0
