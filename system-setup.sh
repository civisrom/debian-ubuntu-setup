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
    # Ask about SSH configuration
    print_message "Do you want to configure SSH (change port and set AllowUsers)?"
    read -p "Configure SSH? (y/N): " CONFIGURE_SSH
    CONFIGURE_SSH=${CONFIGURE_SSH:-n}
    
    if [ "$CONFIGURE_SSH" = "y" ] || [ "$CONFIGURE_SSH" = "Y" ]; then
        read -p "Enter new SSH port (default 22): " SSH_PORT
        SSH_PORT=${SSH_PORT:-22}
        
        read -p "Enter username for AllowUsers (leave empty to skip): " SSH_ALLOW_USER
    else
        SSH_PORT="22"
        SSH_ALLOW_USER=""
    fi
    
    # Ask about Python virtual environment
    print_message "Do you want to create Python virtual environment?"
    read -p "Create Python venv? (y/N): " CREATE_VENV
    CREATE_VENV=${CREATE_VENV:-n}
    
    if [ "$CREATE_VENV" = "y" ] || [ "$CREATE_VENV" = "Y" ]; then
        read -p "Enter path for virtual environment (default: /root/skripts): " VENV_PATH
        VENV_PATH=${VENV_PATH:-/root/skripts}
    else
        VENV_PATH=""
    fi
    
    # Ask about Docker installation
    print_message "Do you want to install Docker?"
    read -p "Install Docker? (y/N): " INSTALL_DOCKER
    INSTALL_DOCKER=${INSTALL_DOCKER:-n}
    
    # Ask about ufw-docker installation (separate from Docker)
    print_message "Do you want to install ufw-docker (UFW integration for Docker)?"
    print_message "Note: This can be installed even without Docker"
    read -p "Install ufw-docker? (y/N): " INSTALL_UFW_DOCKER
    INSTALL_UFW_DOCKER=${INSTALL_UFW_DOCKER:-n}
    
    # Ask about UFW configuration
    print_message "Do you want to configure UFW firewall?"
    read -p "Configure UFW? (Y/n): " CONFIGURE_UFW
    CONFIGURE_UFW=${CONFIGURE_UFW:-y}
    
    # Ask about sysctl configuration
    print_message "Do you want to optimize system parameters (sysctl.conf)?"
    read -p "Configure sysctl? (Y/n): " CONFIGURE_SYSCTL
    CONFIGURE_SYSCTL=${CONFIGURE_SYSCTL:-y}
    
    # Ask about repository configuration
    if [ "$OS" = "debian" ]; then
        print_message "Do you want to configure Debian repositories?"
        read -p "Configure repositories? (Y/n): " CONFIGURE_REPOS
        CONFIGURE_REPOS=${CONFIGURE_REPOS:-y}
    else
        print_message "Do you want to configure Ubuntu repositories?"
        read -p "Configure repositories? (Y/n): " CONFIGURE_REPOS
        CONFIGURE_REPOS=${CONFIGURE_REPOS:-y}
    fi
    
    # Ask about MOTD installation
    print_message "Do you want to install custom MOTD (Message of the Day)?"
    read -p "Install MOTD? (y/N): " INSTALL_MOTD
    INSTALL_MOTD=${INSTALL_MOTD:-n}
    
    # Ask for UFW ports (if UFW is enabled)
    if [ "$CONFIGURE_UFW" = "y" ] || [ "$CONFIGURE_UFW" = "Y" ]; then
        echo ""
        print_message "UFW Firewall Configuration"
        print_message "Port $SSH_PORT (SSH) will be allowed automatically"
        echo ""
        read -p "Enter additional port to allow (press Enter to skip): " CUSTOM_PORT
    else
        CUSTOM_PORT=""
    fi
else
    # Default settings for non-interactive mode
    CONFIGURE_SSH="n"
    SSH_PORT="22"
    SSH_ALLOW_USER=""
    CREATE_VENV="n"
    VENV_PATH=""
    INSTALL_DOCKER="n"
    CONFIGURE_UFW="y"
    CONFIGURE_SYSCTL="y"
    CONFIGURE_REPOS="y"
    INSTALL_MOTD="n"
    CUSTOM_PORT=""
    INSTALL_UFW_DOCKER="n"
    
    print_message "Non-interactive mode - using default settings:"
    print_message "- SSH configuration: NO"
    print_message "- Python venv: NO"
    print_message "- Docker: NO"
    print_message "- ufw-docker: NO"
    print_message "- UFW: YES"
    print_message "- sysctl: YES"
    print_message "- Repositories: YES"
    print_message "- MOTD: NO"
    print_message "- Custom UFW Port: None"
fi
echo ""

# Confirm settings
print_header "═══════════════════════════════════════════════"
print_message "Configuration Summary:"
print_message "  OS: $OS $VERSION ($VERSION_CODENAME)"
print_message "  SSH Configuration: $([ "$CONFIGURE_SSH" = "y" ] || [ "$CONFIGURE_SSH" = "Y" ] && echo "YES (Port: $SSH_PORT, User: ${SSH_ALLOW_USER:-none})" || echo "NO")"
print_message "  Python venv: $([ "$CREATE_VENV" = "y" ] || [ "$CREATE_VENV" = "Y" ] && echo "YES (Path: $VENV_PATH)" || echo "NO")"
print_message "  Docker: $([ "$INSTALL_DOCKER" = "y" ] || [ "$INSTALL_DOCKER" = "Y" ] && echo "YES" || echo "NO")"
print_message "  ufw-docker: $([ "$INSTALL_UFW_DOCKER" = "y" ] || [ "$INSTALL_UFW_DOCKER" = "Y" ] && echo "YES" || echo "NO")"
print_message "  UFW Firewall: $([ "$CONFIGURE_UFW" = "y" ] || [ "$CONFIGURE_UFW" = "Y" ] && echo "YES" || echo "NO")"
print_message "  sysctl optimization: $([ "$CONFIGURE_SYSCTL" = "y" ] || [ "$CONFIGURE_SYSCTL" = "Y" ] && echo "YES" || echo "NO")"
print_message "  Repositories configuration: $([ "$CONFIGURE_REPOS" = "y" ] || [ "$CONFIGURE_REPOS" = "Y" ] && echo "YES" || echo "NO")"
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
    python3
    python3-venv
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

# Configure sources.list for Debian
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

# Configure sources.list for Ubuntu
if [ "$OS" = "ubuntu" ] && { [ "$CONFIGURE_REPOS" = "y" ] || [ "$CONFIGURE_REPOS" = "Y" ]; }; then
    print_message "Configuring Ubuntu repositories..."
    
    # Backup original sources.list
    if [ -f /etc/apt/sources.list ]; then
        cp /etc/apt/sources.list /etc/apt/sources.list.backup.$(date +%Y%m%d-%H%M%S)
        print_message "Original sources.list backed up"
    fi
    
    # Use detected or selected codename
    UBUNTU_CODENAME=${VERSION_CODENAME:-noble}
    
    # Write new sources.list
    cat > /etc/apt/sources.list << EOF
# Ubuntu Main Repositories
deb http://archive.ubuntu.com/ubuntu/ ${UBUNTU_CODENAME} main restricted universe multiverse
deb-src http://archive.ubuntu.com/ubuntu/ ${UBUNTU_CODENAME} main restricted universe multiverse

# Ubuntu Updates
deb http://archive.ubuntu.com/ubuntu/ ${UBUNTU_CODENAME}-updates main restricted universe multiverse
deb-src http://archive.ubuntu.com/ubuntu/ ${UBUNTU_CODENAME}-updates main restricted universe multiverse

# Ubuntu Security Updates
deb http://security.ubuntu.com/ubuntu/ ${UBUNTU_CODENAME}-security main restricted universe multiverse
deb-src http://security.ubuntu.com/ubuntu/ ${UBUNTU_CODENAME}-security main restricted universe multiverse

# Ubuntu Backports
deb http://archive.ubuntu.com/ubuntu/ ${UBUNTU_CODENAME}-backports main restricted universe multiverse
deb-src http://archive.ubuntu.com/ubuntu/ ${UBUNTU_CODENAME}-backports main restricted universe multiverse

# Canonical Partner Repository
# deb http://archive.canonical.com/ubuntu ${UBUNTU_CODENAME} partner
# deb-src http://archive.canonical.com/ubuntu ${UBUNTU_CODENAME} partner
EOF
    
    print_message "Ubuntu repositories configured for ${UBUNTU_CODENAME}"
    print_message "Repositories enabled: main, restricted, universe, multiverse"
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
    
    # Preserve only comments and empty lines from original file
    if [ -f /etc/sysctl.conf ]; then
        grep -E '^#|^$' /etc/sysctl.conf > /etc/sysctl.conf.new 2>/dev/null || true
    else
        touch /etc/sysctl.conf.new
    fi
    
    # Add new configuration with proper spacing
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

# Configure SSH
if [ "$CONFIGURE_SSH" = "y" ] || [ "$CONFIGURE_SSH" = "Y" ]; then
    print_message "Configuring SSH..."
    
    SSHD_CONFIG="/etc/ssh/sshd_config"
    
    # Backup original sshd_config
    if [ -f "$SSHD_CONFIG" ]; then
        cp "$SSHD_CONFIG" "${SSHD_CONFIG}.backup.$(date +%Y%m%d-%H%M%S)"
        print_message "Original sshd_config backed up"
    fi
    
    # Change SSH port
    if [ ! -z "$SSH_PORT" ] && [ "$SSH_PORT" != "22" ]; then
        # Check if Port line exists (commented or not)
        if grep -q "^#Port " "$SSHD_CONFIG" || grep -q "^Port " "$SSHD_CONFIG"; then
            # Replace existing Port line
            sed -i "s/^#Port .*/Port $SSH_PORT/" "$SSHD_CONFIG"
            sed -i "s/^Port .*/Port $SSH_PORT/" "$SSHD_CONFIG"
            print_message "SSH port changed to $SSH_PORT"
        else
            # Add Port line after Include directive
            sed -i "/^Include \/etc\/ssh\/sshd_config.d\/\*.conf/a Port $SSH_PORT" "$SSHD_CONFIG"
            print_message "SSH port set to $SSH_PORT"
        fi
    fi
    
    # Add AllowUsers if specified
    if [ ! -z "$SSH_ALLOW_USER" ]; then
        # Remove existing AllowUsers lines
        sed -i '/^AllowUsers /d' "$SSHD_CONFIG"
        
        # Add AllowUsers at the end of file
        echo "" >> "$SSHD_CONFIG"
        echo "# Allowed users" >> "$SSHD_CONFIG"
        echo "AllowUsers $SSH_ALLOW_USER" >> "$SSHD_CONFIG"
        print_message "AllowUsers set to: $SSH_ALLOW_USER"
    fi
    
    # Test SSH configuration
    print_message "Testing SSH configuration..."
    if sshd -t; then
        print_message "SSH configuration is valid"
        
        # Restart SSH service
        print_message "Restarting SSH service..."
        systemctl restart sshd || systemctl restart ssh
        print_message "SSH service restarted"
    else
        print_error "SSH configuration test failed!"
        print_error "Restoring backup..."
        cp "${SSHD_CONFIG}.backup."* "$SSHD_CONFIG"
        print_error "SSH configuration restored from backup"
    fi
else
    print_message "Skipping SSH configuration (not requested)"
fi

# Configure UFW
if [ "$CONFIGURE_UFW" = "y" ] || [ "$CONFIGURE_UFW" = "Y" ]; then
    print_message "Configuring UFW firewall..."
    
    # Set default policies
    print_message "Setting UFW default policies..."
    ufw --force default deny incoming
    ufw --force default allow outgoing
    ufw --force default deny forward
    ufw --force default deny routed
    print_message "UFW default policies configured"
    
    # Allow SSH (use configured port)
    ufw allow ${SSH_PORT}/tcp comment 'SSH'
    print_message "UFW rule added: Allow SSH (port ${SSH_PORT})"
    
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

# Install ufw-docker (independent of Docker installation)
if [ "$INSTALL_UFW_DOCKER" = "y" ] || [ "$INSTALL_UFW_DOCKER" = "Y" ]; then
    print_message "Installing ufw-docker..."
    
    if wget -O /usr/local/bin/ufw-docker https://github.com/chaifeng/ufw-docker/raw/master/ufw-docker; then
        chmod +x /usr/local/bin/ufw-docker
        print_message "ufw-docker downloaded successfully"
        
        # Run ufw-docker install
        print_message "Configuring ufw-docker..."
        /usr/local/bin/ufw-docker install
        print_message "ufw-docker configured successfully"
        
        if ! command -v docker &> /dev/null; then
            print_warning "Note: Docker is not installed. ufw-docker will be ready when you install Docker."
        fi
    else
        print_error "Failed to download ufw-docker"
    fi
else
    print_message "Skipping ufw-docker installation (not requested)"
fi

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
        source "$VENV_PATH/bin/activate"
        
        # Upgrade pip first
        pip install --upgrade pip
        
        # Install packages
        pip install --upgrade \
            requests \
            psutil \
            pytz \
            uvloop \
            ipaddress \
            pathlib \
            python-telegram-bot \
            nest_asyncio \
            aiohttp \
            charset-normalizer \
            maxminddb \
            geoipsets \
            setuptools \
            wheel \
            pip \
            passlib \
            bcrypt \
            tqdm \
            colorama \
            humanize \
            termcolor \
            rich \
            "python-telegram-bot[job-queue]" \
            urllib3 \
            chardet
        
        print_message "Python packages installed successfully"
        print_message "Virtual environment location: $VENV_PATH"
        print_message "To activate: source $VENV_PATH/bin/activate"
        
        deactivate
    else
        print_error "Failed to create virtual environment"
    fi
else
    print_message "Skipping Python virtual environment creation (not requested)"
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

if [ "$CONFIGURE_SSH" = "y" ] || [ "$CONFIGURE_SSH" = "Y" ]; then
    print_message "- SSH configured (Port: $SSH_PORT, AllowUsers: ${SSH_ALLOW_USER:-not set})"
else
    print_message "- SSH: NOT CONFIGURED"
fi

if [ "$CREATE_VENV" = "y" ] || [ "$CREATE_VENV" = "Y" ]; then
    print_message "- Python venv created at: $VENV_PATH"
else
    print_message "- Python venv: NOT CREATED"
fi

if [ "$CONFIGURE_SYSCTL" = "y" ] || [ "$CONFIGURE_SYSCTL" = "Y" ]; then
    print_message "- System parameters optimized (sysctl.conf)"
else
    print_message "- sysctl: SKIPPED"
fi

if [ "$CONFIGURE_REPOS" = "y" ] || [ "$CONFIGURE_REPOS" = "Y" ]; then
    if [ "$OS" = "debian" ]; then
        print_message "- Debian repositories configured"
    else
        print_message "- Ubuntu repositories configured (main, restricted, universe, multiverse)"
    fi
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
else
    print_message "- Docker: Not installed"
    if [ "$INSTALL_DOCKER" = "y" ] || [ "$INSTALL_DOCKER" = "Y" ]; then
        print_message "- Docker installation may have failed"
    fi
fi

if command -v ufw-docker &> /dev/null; then
    print_message "- ufw-docker: Installed and configured"
else
    if [ "$INSTALL_UFW_DOCKER" = "y" ] || [ "$INSTALL_UFW_DOCKER" = "Y" ]; then
        print_message "- ufw-docker: Installation attempted but not found"
    else
        print_message "- ufw-docker: Not installed"
    fi
fi

if [ "$INSTALL_MOTD" = "y" ] || [ "$INSTALL_MOTD" = "Y" ]; then
    print_message "- Custom MOTD: Installed"
else
    print_message "- Custom MOTD: Not installed"
fi

print_message ""

if [ "$CONFIGURE_SYSCTL" = "y" ] || [ "$CONFIGURE_SYSCTL" = "Y" ] || [ "$CONFIGURE_REPOS" = "y" ] || [ "$CONFIGURE_REPOS" = "Y" ] || [ "$CONFIGURE_SSH" = "y" ] || [ "$CONFIGURE_SSH" = "Y" ]; then
    print_message "Backup files saved with timestamp:"
    if [ "$CONFIGURE_SYSCTL" = "y" ] || [ "$CONFIGURE_SYSCTL" = "Y" ]; then
        print_message "- /etc/sysctl.conf.backup.*"
    fi
    if [ "$CONFIGURE_REPOS" = "y" ] || [ "$CONFIGURE_REPOS" = "Y" ]; then
        print_message "- /etc/apt/sources.list.backup.*"
    fi
    if [ "$CONFIGURE_SSH" = "y" ] || [ "$CONFIGURE_SSH" = "Y" ]; then
        print_message "- /etc/ssh/sshd_config.backup.*"
    fi
    print_message ""
fi

print_warning "Recommended next steps:"
STEP_NUM=1

if [ "$CONFIGURE_SSH" = "y" ] || [ "$CONFIGURE_SSH" = "Y" ]; then
    if [ "$SSH_PORT" != "22" ]; then
        print_warning "$STEP_NUM. IMPORTANT: SSH port changed to $SSH_PORT"
        print_warning "   Make sure to update your SSH client before logging out!"
        print_warning "   Test connection: ssh -p $SSH_PORT user@host"
        STEP_NUM=$((STEP_NUM + 1))
    fi
fi

if [ "$CONFIGURE_UFW" = "y" ] || [ "$CONFIGURE_UFW" = "Y" ]; then
    print_warning "$STEP_NUM. Review UFW status: sudo ufw status verbose"
    STEP_NUM=$((STEP_NUM + 1))
fi

if [ "$CONFIGURE_SYSCTL" = "y" ] || [ "$CONFIGURE_SYSCTL" = "Y" ]; then
    print_warning "$STEP_NUM. Check sysctl: sysctl net.ipv4.tcp_congestion_control"
    STEP_NUM=$((STEP_NUM + 1))
fi

if [ "$CREATE_VENV" = "y" ] || [ "$CREATE_VENV" = "Y" ]; then
    print_warning "$STEP_NUM. Activate Python venv: source $VENV_PATH/bin/activate"
    STEP_NUM=$((STEP_NUM + 1))
fi

if command -v docker &> /dev/null && [ ! -z "$SUDO_USER" ]; then
    print_warning "$STEP_NUM. Log out and back in to use Docker without sudo"
    STEP_NUM=$((STEP_NUM + 1))
fi

print_warning "$STEP_NUM. Reboot system to apply all changes: sudo reboot"

exit 0
