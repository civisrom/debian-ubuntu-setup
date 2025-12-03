#!/bin/bash

#############################################
# System Setup Script for Debian and Ubuntu
# Author: Auto-generated (Enhanced Version)
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
print_header "║   Initial Configuration Tool (Enhanced)       ║"
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
    # Ask about RustDesk installation
    print_message "Do you want to install RustDesk server in Docker?"
    print_message "This will create /root/rustdesk directory with docker-compose.yml"
    print_message "and install it as a systemd service"
    read -p "Install RustDesk? (y/N): " INSTALL_RUSTDESK
    INSTALL_RUSTDESK=${INSTALL_RUSTDESK:-n}
    
    echo ""
    
    # Ask about root password
    print_message "Do you want to set a password for root user?"
    read -p "Set root password? (y/N): " SET_ROOT_PASSWORD
    SET_ROOT_PASSWORD=${SET_ROOT_PASSWORD:-n}
    
    if [ "$SET_ROOT_PASSWORD" = "y" ] || [ "$SET_ROOT_PASSWORD" = "Y" ]; then
        while true; do
            read -s -p "Enter new root password: " ROOT_PASSWORD
            echo ""
            read -s -p "Confirm root password: " ROOT_PASSWORD_CONFIRM
            echo ""
            
            if [ "$ROOT_PASSWORD" = "$ROOT_PASSWORD_CONFIRM" ]; then
                if [ -z "$ROOT_PASSWORD" ]; then
                    print_error "Password cannot be empty"
                    continue
                fi
                print_message "Root password will be set"
                break
            else
                print_error "Passwords do not match. Please try again."
            fi
        done
    else
        ROOT_PASSWORD=""
    fi
    
    echo ""
    
    # Ask about creating new user
    print_message "Do you want to create a new user?"
    read -p "Create new user? (y/N): " CREATE_USER
    CREATE_USER=${CREATE_USER:-n}
    
    if [ "$CREATE_USER" = "y" ] || [ "$CREATE_USER" = "Y" ]; then
        read -p "Enter username for new user: " NEW_USERNAME
        
        if [ -z "$NEW_USERNAME" ]; then
            print_error "Username cannot be empty"
            CREATE_USER="n"
        else
            # Check if user already exists
            if id "$NEW_USERNAME" &>/dev/null; then
                print_warning "User $NEW_USERNAME already exists"
                read -p "Continue with existing user? (y/N): " USE_EXISTING
                USE_EXISTING=${USE_EXISTING:-n}
                
                if [ "$USE_EXISTING" != "y" ] && [ "$USE_EXISTING" != "Y" ]; then
                    CREATE_USER="n"
                    NEW_USERNAME=""
                else
                    CREATE_USER="existing"
                fi
            else
                while true; do
                    read -s -p "Enter password for $NEW_USERNAME: " NEW_USER_PASSWORD
                    echo ""
                    read -s -p "Confirm password: " NEW_USER_PASSWORD_CONFIRM
                    echo ""
                    
                    if [ "$NEW_USER_PASSWORD" = "$NEW_USER_PASSWORD_CONFIRM" ]; then
                        if [ -z "$NEW_USER_PASSWORD" ]; then
                            print_error "Password cannot be empty"
                            continue
                        fi
                        print_message "User $NEW_USERNAME will be created"
                        break
                    else
                        print_error "Passwords do not match. Please try again."
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
        read -p "Configure SSH key? (y/N): " CONFIGURE_USER_SSH_KEY
        CONFIGURE_USER_SSH_KEY=${CONFIGURE_USER_SSH_KEY:-n}
        
        if [ "$CONFIGURE_USER_SSH_KEY" = "y" ] || [ "$CONFIGURE_USER_SSH_KEY" = "Y" ]; then
            echo ""
            print_message "Enter SSH public key for $NEW_USERNAME"
            print_message "Example: ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAAB..."
            read -p "SSH public key: " USER_SSH_KEY
            
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
        read -p "Install zsh? (y/N): " INSTALL_ZSH
        INSTALL_ZSH=${INSTALL_ZSH:-n}
    else
        INSTALL_ZSH="n"
    fi
    
    echo ""
    
    # Ask about crontab configuration
    print_message "Do you want to configure crontab for root?"
    read -p "Configure crontab? (y/N): " CONFIGURE_CRONTAB
    CONFIGURE_CRONTAB=${CONFIGURE_CRONTAB:-n}
    
    if [ "$CONFIGURE_CRONTAB" = "y" ] || [ "$CONFIGURE_CRONTAB" = "Y" ]; then
        echo ""
        print_message "Crontab configuration mode:"
        print_message "You can add multiple cron tasks after the environment variables"
        print_message "1) Enter tasks manually (line by line)"
        print_message "2) Paste tasks from clipboard (recommended for multiple tasks)"
        print_message "3) Skip adding tasks (only set environment variables)"
        echo ""
        read -p "Choose option [1-3] (default: 3): " CRONTAB_MODE
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
    print_message "Do you want to configure SSH (change port and set AllowUsers)?"
    read -p "Configure SSH? (y/N): " CONFIGURE_SSH
    CONFIGURE_SSH=${CONFIGURE_SSH:-n}
    
    if [ "$CONFIGURE_SSH" = "y" ] || [ "$CONFIGURE_SSH" = "Y" ]; then
        read -p "Enter new SSH port (default 22): " SSH_PORT
        SSH_PORT=${SSH_PORT:-22}
        
        echo ""
        print_message "Enter usernames for AllowUsers (space-separated, leave empty to skip)"
        print_message "Example: user1 user2 user3"
        if [ ! -z "$NEW_USERNAME" ]; then
            print_message "Suggestion: $NEW_USERNAME"
        fi
        read -p "AllowUsers: " SSH_ALLOW_USERS
        
        echo ""
        print_header "Advanced SSH Security Parameters"
        print_message "Configure additional SSH security settings"
        echo ""
        
        # PubkeyAuthentication
        print_message "PubkeyAuthentication - Enable public key authentication"
        read -p "Configure PubkeyAuthentication? (y/N): " CONFIG_PUBKEY
        CONFIG_PUBKEY=${CONFIG_PUBKEY:-n}
        if [ "$CONFIG_PUBKEY" = "y" ] || [ "$CONFIG_PUBKEY" = "Y" ]; then
            read -p "Set PubkeyAuthentication to yes or no? (Y/n): " SSH_PUBKEY_AUTH
            SSH_PUBKEY_AUTH=${SSH_PUBKEY_AUTH:-y}
            if [ "$SSH_PUBKEY_AUTH" = "y" ] || [ "$SSH_PUBKEY_AUTH" = "Y" ]; then
                SSH_PUBKEY_AUTH="yes"
            else
                SSH_PUBKEY_AUTH="no"
            fi
        else
            SSH_PUBKEY_AUTH=""
        fi
        
        # PasswordAuthentication
        print_message "PasswordAuthentication - Enable password authentication"
        read -p "Configure PasswordAuthentication? (y/N): " CONFIG_PASSWORD
        CONFIG_PASSWORD=${CONFIG_PASSWORD:-n}
        if [ "$CONFIG_PASSWORD" = "y" ] || [ "$CONFIG_PASSWORD" = "Y" ]; then
            read -p "Set PasswordAuthentication to yes or no? (Y/n): " SSH_PASSWORD_AUTH
            SSH_PASSWORD_AUTH=${SSH_PASSWORD_AUTH:-y}
            if [ "$SSH_PASSWORD_AUTH" = "y" ] || [ "$SSH_PASSWORD_AUTH" = "Y" ]; then
                SSH_PASSWORD_AUTH="yes"
            else
                SSH_PASSWORD_AUTH="no"
            fi
        else
            SSH_PASSWORD_AUTH=""
        fi
        
        # PermitEmptyPasswords - ALWAYS set to no, only ask about uncommenting
        print_message "PermitEmptyPasswords - Prevent empty password authentication (ALWAYS set to 'no')"
        read -p "Configure PermitEmptyPasswords? (y/N): " CONFIG_EMPTY_PASS
        CONFIG_EMPTY_PASS=${CONFIG_EMPTY_PASS:-n}
        if [ "$CONFIG_EMPTY_PASS" = "y" ] || [ "$CONFIG_EMPTY_PASS" = "Y" ]; then
            SSH_EMPTY_PASSWORDS="no"  # ALWAYS no for security
        else
            SSH_EMPTY_PASSWORDS=""
        fi
        
        # PermitRootLogin
        print_message "PermitRootLogin - Allow root user to login via SSH"
        read -p "Configure PermitRootLogin? (y/N): " CONFIG_ROOT_LOGIN
        CONFIG_ROOT_LOGIN=${CONFIG_ROOT_LOGIN:-n}
        if [ "$CONFIG_ROOT_LOGIN" = "y" ] || [ "$CONFIG_ROOT_LOGIN" = "Y" ]; then
            read -p "Set PermitRootLogin to yes or no? (Y/n): " SSH_ROOT_LOGIN
            SSH_ROOT_LOGIN=${SSH_ROOT_LOGIN:-y}
            if [ "$SSH_ROOT_LOGIN" = "y" ] || [ "$SSH_ROOT_LOGIN" = "Y" ]; then
                SSH_ROOT_LOGIN="yes"
            else
                SSH_ROOT_LOGIN="no"
            fi
        else
            SSH_ROOT_LOGIN=""
        fi
    else
        SSH_PORT="22"
        SSH_ALLOW_USERS=""
        SSH_PUBKEY_AUTH=""
        SSH_PASSWORD_AUTH=""
        SSH_EMPTY_PASSWORDS=""
        SSH_ROOT_LOGIN=""
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
    
    # Ask about Go installation
    echo ""
    print_message "Do you want to install the latest version of Go?"
    if [ ! -z "$NEW_USERNAME" ]; then
        print_message "Go will be installed for user: $NEW_USERNAME"
    else
        print_message "Note: Go installation requires a user to be created"
    fi
    read -p "Install Go? (y/N): " INSTALL_GO
    INSTALL_GO=${INSTALL_GO:-n}
    
    # Ask about ipset installation
    echo ""
    print_message "Do you want to build and install the latest version of ipset?"
    print_message "This will compile ipset from source"
    read -p "Install ipset? (y/N): " INSTALL_IPSET
    INSTALL_IPSET=${INSTALL_IPSET:-n}
    
    echo ""
    
    # Ask about UFW configuration
    print_message "Do you want to configure UFW firewall?"
    read -p "Configure UFW? (Y/n): " CONFIGURE_UFW
    CONFIGURE_UFW=${CONFIGURE_UFW:-y}
    
    # Ask about ICMP blocking (only if UFW is enabled)
    if [ "$CONFIGURE_UFW" = "y" ] || [ "$CONFIGURE_UFW" = "Y" ]; then
        echo ""
        print_message "Do you want to block ICMP (ping) requests?"
        print_message "Note: This will make your server invisible to ping"
        read -p "Block ICMP? (y/N): " BLOCK_ICMP
        BLOCK_ICMP=${BLOCK_ICMP:-n}
        
        # Ask about custom UFW Docker rules
        echo ""
        print_message "Do you want to install custom UFW Docker rules script?"
        print_message "This will download and execute ufw-docker-rules-v4.sh from GitHub"
        print_message "Note: The script will run AFTER all other installations complete"
        read -p "Install custom UFW Docker rules? (y/N): " INSTALL_UFW_CUSTOM_RULES
        INSTALL_UFW_CUSTOM_RULES=${INSTALL_UFW_CUSTOM_RULES:-n}
        
        if [ "$INSTALL_UFW_CUSTOM_RULES" = "y" ] || [ "$INSTALL_UFW_CUSTOM_RULES" = "Y" ]; then
            echo ""
            print_message "The archive is password-protected. Please enter the password:"
            read -s -p "Password: " UFW_CUSTOM_RULES_PASSWORD
            echo ""
            if [ -z "$UFW_CUSTOM_RULES_PASSWORD" ]; then
                print_warning "No password provided. Custom UFW rules will not be installed."
                INSTALL_UFW_CUSTOM_RULES="n"
            fi
        fi
    else
        BLOCK_ICMP="n"
        INSTALL_UFW_CUSTOM_RULES="n"
    fi
    
    # Ask about sysctl configuration
    print_message "Do you want to optimize system parameters (sysctl.conf)?"
    read -p "Configure sysctl? (Y/n): " CONFIGURE_SYSCTL
    CONFIGURE_SYSCTL=${CONFIGURE_SYSCTL:-y}
    
    # Ask about repository configuration
    if [ "$OS" = "debian" ]; then
        print_message "Do you want to configure Debian repositories?"
        read -p "Configure repositories? (Y/n): " CONFIGURE_REPOS
        CONFIGURE_REPOS=${CONFIGURE_REPOS:-y}
        
        # Ask about Tataranovich repository (only for Debian)
        echo ""
        print_message "Do you want to add Tataranovich repository (custom mc build)?"
        print_message "This will install Midnight Commander from tataranovich.com"
        read -p "Add Tataranovich repository? (y/N): " ADD_TATARANOVICH_REPO
        ADD_TATARANOVICH_REPO=${ADD_TATARANOVICH_REPO:-n}
    else
        print_message "Do you want to configure Ubuntu repositories?"
        read -p "Configure repositories? (Y/n): " CONFIGURE_REPOS
        CONFIGURE_REPOS=${CONFIGURE_REPOS:-y}
        ADD_TATARANOVICH_REPO="n"
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
        print_message "You can add additional ports to UFW"
        print_message "Format examples:"
        print_message "  Single port:     8080"
        print_message "  With protocol:   8080/tcp  or  53/udp"
        print_message "  Multiple ports:  8080,8443,9000"
        print_message "  Mixed:          8080/tcp,53/udp,3000"
        echo ""
        read -p "Enter additional ports (comma-separated, press Enter to skip): " CUSTOM_PORTS
        
        if [ ! -z "$CUSTOM_PORTS" ]; then
            print_message "Custom ports will be configured: $CUSTOM_PORTS"
        fi
    else
        CUSTOM_PORTS=""
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
    CREATE_VENV="n"
    VENV_PATH=""
    INSTALL_DOCKER="n"
    CONFIGURE_UFW="y"
    BLOCK_ICMP="n"
    INSTALL_UFW_CUSTOM_RULES="n"
    UFW_CUSTOM_RULES_PASSWORD=""
    CONFIGURE_SYSCTL="y"
    CONFIGURE_REPOS="y"
    INSTALL_MOTD="n"
    CUSTOM_PORTS=""
    INSTALL_UFW_DOCKER="n"
    ADD_TATARANOVICH_REPO="n"
    INSTALL_GO="n"
    INSTALL_IPSET="n"
    
    print_message "Non-interactive mode - using default settings:"
    print_message "- Root password: NO"
    print_message "- Create user: NO"
    print_message "- SSH configuration: NO"
    print_message "- Python venv: NO"
    print_message "- Docker: NO"
    print_message "- ufw-docker: NO"
    print_message "- UFW: YES"
    print_message "- Block ICMP: NO"
    print_message "- sysctl: YES"
    print_message "- Repositories: YES"
    print_message "- MOTD: NO"
    print_message "- Custom UFW Port: None"
    print_message "- Crontab: NO"
fi
echo ""

# Confirm settings
print_header "═══════════════════════════════════════════════"
print_message "Configuration Summary:"
print_message "  OS: $OS $VERSION ($VERSION_CODENAME)"
print_message "  RustDesk Server: $([ "$INSTALL_RUSTDESK" = "y" ] || [ "$INSTALL_RUSTDESK" = "Y" ] && echo "YES (Docker)" || echo "NO")"
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
fi
print_message "  Python venv: $([ "$CREATE_VENV" = "y" ] || [ "$CREATE_VENV" = "Y" ] && echo "YES (Path: $VENV_PATH)" || echo "NO")"
print_message "  Docker: $([ "$INSTALL_DOCKER" = "y" ] || [ "$INSTALL_DOCKER" = "Y" ] && echo "YES" || echo "NO")"
print_message "  ufw-docker: $([ "$INSTALL_UFW_DOCKER" = "y" ] || [ "$INSTALL_UFW_DOCKER" = "Y" ] && echo "YES" || echo "NO")"
print_message "  Go language: $([ "$INSTALL_GO" = "y" ] || [ "$INSTALL_GO" = "Y" ] && echo "YES (latest version)" || echo "NO")"
print_message "  ipset: $([ "$INSTALL_IPSET" = "y" ] || [ "$INSTALL_IPSET" = "Y" ] && echo "YES (build from source)" || echo "NO")"
print_message "  UFW Firewall: $([ "$CONFIGURE_UFW" = "y" ] || [ "$CONFIGURE_UFW" = "Y" ] && echo "YES" || echo "NO")"
if [ "$CONFIGURE_UFW" = "y" ] || [ "$CONFIGURE_UFW" = "Y" ]; then
    print_message "  Block ICMP (ping): $([ "$BLOCK_ICMP" = "y" ] || [ "$BLOCK_ICMP" = "Y" ] && echo "YES" || echo "NO")"
    print_message "  Custom UFW Docker rules: $([ "$INSTALL_UFW_CUSTOM_RULES" = "y" ] || [ "$INSTALL_UFW_CUSTOM_RULES" = "Y" ] && echo "YES" || echo "NO")"
fi
print_message "  sysctl optimization: $([ "$CONFIGURE_SYSCTL" = "y" ] || [ "$CONFIGURE_SYSCTL" = "Y" ] && echo "YES" || echo "NO")"
print_message "  Repositories configuration: $([ "$CONFIGURE_REPOS" = "y" ] || [ "$CONFIGURE_REPOS" = "Y" ] && echo "YES" || echo "NO")"
if [ "$OS" = "debian" ] && { [ "$ADD_TATARANOVICH_REPO" = "y" ] || [ "$ADD_TATARANOVICH_REPO" = "Y" ]; }; then
    print_message "  Tataranovich repository: YES"
fi
print_message "  Custom MOTD: $([ "$INSTALL_MOTD" = "y" ] || [ "$INSTALL_MOTD" = "Y" ] && echo "YES" || echo "NO")"
if [ ! -z "$CUSTOM_PORTS" ]; then
    print_message "  UFW Custom Ports: $CUSTOM_PORTS"
else
    print_message "  UFW Custom Ports: None"
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

# ============================================
# INSTALL RUSTDESK SERVER (DOCKER)
# ============================================

if [ "$INSTALL_RUSTDESK" = "y" ] || [ "$INSTALL_RUSTDESK" = "Y" ]; then
    print_message "Installing RustDesk server in Docker..."
    echo ""
    
    RUSTDESK_DIR="/root/rustdesk"
    RUSTDESK_COMPOSE_URL="https://raw.githubusercontent.com/civisrom/debian-ubuntu-setup/refs/heads/main/config/docker-compose.yml"
    RUSTDESK_SERVICE_URL="https://raw.githubusercontent.com/civisrom/debian-ubuntu-setup/refs/heads/main/config/rustdesk-compose.service"
    RUSTDESK_SERVICE_PATH="/etc/systemd/system/rustdesk-compose.service"
    
    # Create rustdesk directory
    print_message "Creating directory: $RUSTDESK_DIR..."
    if mkdir -p "$RUSTDESK_DIR"; then
        print_message "Directory created successfully"
    else
        print_error "CRITICAL: Failed to create directory $RUSTDESK_DIR"
        print_error "Installation cannot continue"
        exit 1
    fi
    
    # Download docker-compose.yml
    print_message "Downloading docker-compose.yml..."
    if curl -fsSL "$RUSTDESK_COMPOSE_URL" -o "${RUSTDESK_DIR}/docker-compose.yml"; then
        print_message "docker-compose.yml downloaded successfully"
    else
        print_error "CRITICAL: Failed to download docker-compose.yml"
        print_error "Installation cannot continue"
        exit 1
    fi
    
    # Download systemd service file
    print_message "Downloading systemd service file..."
    if curl -fsSL "$RUSTDESK_SERVICE_URL" -o "$RUSTDESK_SERVICE_PATH"; then
        print_message "Service file downloaded successfully"
    else
        print_error "CRITICAL: Failed to download service file"
        print_error "Installation cannot continue"
        exit 1
    fi
    
    # Reload systemd daemon
    print_message "Reloading systemd daemon..."
    if systemctl daemon-reload; then
        print_message "Systemd daemon reloaded successfully"
    else
        print_error "CRITICAL: Failed to reload systemd daemon"
        print_error "Installation cannot continue"
        exit 1
    fi
    
    # Enable rustdesk service
    print_message "Enabling rustdesk-compose service..."
    if systemctl enable rustdesk-compose.service; then
        print_message "Service enabled successfully"
    else
        print_error "CRITICAL: Failed to enable rustdesk-compose service"
        print_error "Installation cannot continue"
        exit 1
    fi
    
    # Check if Docker is installed (needed to start the service)
    if command -v docker &> /dev/null; then
        print_message "Docker found, starting rustdesk-compose service..."
        if systemctl start rustdesk-compose.service; then
            print_message "RustDesk service started successfully"
            
            # Check service status
            sleep 3
            if systemctl is-active --quiet rustdesk-compose.service; then
                print_message "RustDesk service is running"
            else
                print_warning "RustDesk service is enabled but not running (Docker might not be installed yet)"
                print_message "Service will start automatically after Docker installation"
            fi
        else
            print_warning "Failed to start rustdesk-compose service"
            print_message "Service will start automatically after Docker installation"
        fi
    else
        print_message "Docker not installed yet - RustDesk service will start after Docker is installed"
    fi
    
    print_message "RustDesk installation completed"
    print_message "Directory: $RUSTDESK_DIR"
    print_message "Service: rustdesk-compose.service"
    echo ""
else
    print_message "Skipping RustDesk installation (not requested)"
fi

# Update package lists
print_message "Updating package lists..."
if apt update; then
    print_message "Package lists updated successfully"
else
    print_error "CRITICAL: Failed to update package lists"
    print_error "Installation cannot continue"
    exit 1
fi

# Common packages for both Debian and Ubuntu
COMMON_PACKAGES=(
    htop
    wget
    iptables
    ufw
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
    vim
    p7zip-full
)

# Add zsh if requested
if [ "$INSTALL_ZSH" = "y" ] || [ "$INSTALL_ZSH" = "Y" ]; then
    COMMON_PACKAGES+=(zsh)
fi

# Debian-specific packages
# Note: linux-headers-$(uname -r) will be automatically replaced with current kernel version
# You can comment out (#) any package to disable its installation
DEBIAN_PACKAGES=(
    linux-headers-$(uname -r)
    openvswitch-switch-dpdk
)

# Ubuntu-specific packages
# Note: linux-headers-$(uname -r) will be automatically replaced with current kernel version
# You can comment out (#) any package to disable its installation
UBUNTU_PACKAGES=(
    linux-headers-$(uname -r)
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
    
    if [ ${#DEBIAN_PACKAGES[@]} -gt 0 ]; then
        print_message "Installing Debian-specific packages..."
        apt install -y "${DEBIAN_PACKAGES[@]}" || print_warning "Some Debian-specific packages may not be available"
    else
        print_message "No Debian-specific packages to install"
    fi
    
elif [ "$OS" = "ubuntu" ]; then
    print_message "Installing common packages for Ubuntu..."
    apt install -y "${COMMON_PACKAGES[@]}"
    
    if [ ${#UBUNTU_PACKAGES[@]} -gt 0 ]; then
        print_message "Installing Ubuntu-specific packages..."
        apt install -y "${UBUNTU_PACKAGES[@]}" || print_warning "Some Ubuntu-specific packages may not be available"
    else
        print_message "No Ubuntu-specific packages to install"
    fi
fi

# ============================================
# SET ROOT PASSWORD
# ============================================

if [ "$SET_ROOT_PASSWORD" = "y" ] || [ "$SET_ROOT_PASSWORD" = "Y" ]; then
    print_message "Setting root password..."
    echo "root:$ROOT_PASSWORD" | chpasswd
    print_message "Root password set successfully"
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
        echo "$NEW_USERNAME:$NEW_USER_PASSWORD" | chpasswd
        print_message "Password set for $NEW_USERNAME"
        
        # Add user to sudo group
        gpasswd -a "$NEW_USERNAME" sudo
        print_message "User $NEW_USERNAME added to sudo group"
    else
        print_error "Failed to create user $NEW_USERNAME"
        CREATE_USER="n"
    fi
    echo ""
elif [ "$CREATE_USER" = "existing" ]; then
    print_message "Using existing user: $NEW_USERNAME"
    
    # Ensure user is in sudo group
    if ! groups "$NEW_USERNAME" | grep -q "\bsudo\b"; then
        gpasswd -a "$NEW_USERNAME" sudo
        print_message "User $NEW_USERNAME added to sudo group"
    else
        print_message "User $NEW_USERNAME is already in sudo group"
    fi
    echo ""
fi

# ============================================
# CONFIGURE SSH KEY FOR USER
# ============================================

if [ "$CONFIGURE_USER_SSH_KEY" = "y" ] || [ "$CONFIGURE_USER_SSH_KEY" = "Y" ] && [ ! -z "$NEW_USERNAME" ]; then
    print_message "Configuring SSH key for $NEW_USERNAME"
    
    USER_HOME=$(eval echo ~$NEW_USERNAME)
    
    # Create .ssh directory as user
    sudo -u "$NEW_USERNAME" bash << EOF
        mkdir -p "$USER_HOME/.ssh"
        chmod 700 "$USER_HOME/.ssh"
EOF
    
    print_message "Created .ssh directory for $NEW_USERNAME"
    
    # Add SSH key to authorized_keys
    sudo -u "$NEW_USERNAME" bash << EOF
        echo "$USER_SSH_KEY" > "$USER_HOME/.ssh/authorized_keys"
        chmod 600 "$USER_HOME/.ssh/authorized_keys"
EOF
    
    print_message "SSH key added to $USER_HOME/.ssh/authorized_keys"
    print_message "SSH key configured successfully for $NEW_USERNAME"
    echo ""
fi


# Configure sources.list for Debian
if [ "$OS" = "debian" ] && { [ "$CONFIGURE_REPOS" = "y" ] || [ "$CONFIGURE_REPOS" = "Y" ]; }; then
    print_message "Configuring Debian repositories..."
    
    # Backup original sources.list
    if [ -f /etc/apt/sources.list ]; then
        cp /etc/apt/sources.list /etc/apt/sources.list.backup.$(date +%Y%m%d-%H%M%S)~
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
    
    # Backup original sources.list if it exists and has content
    if [ -f /etc/apt/sources.list ] && [ -s /etc/apt/sources.list ]; then
        cp /etc/apt/sources.list /etc/apt/sources.list.backup.$(date +%Y%m%d-%H%M%S)~
        print_message "Original sources.list backed up"
        
        # Clear the main sources.list file
        cat > /etc/apt/sources.list << 'EOF'
# Ubuntu repositories are now managed in /etc/apt/sources.list.d/
# See /etc/apt/sources.list.d/ubuntu.sources for repository configuration
EOF
        print_message "Main sources.list cleared (repositories moved to sources.list.d)"
    fi
    
    # Use detected or selected codename
    UBUNTU_CODENAME=${VERSION_CODENAME:-noble}
    
    # Use ubuntu.sources (new DEB822 format) instead of ubuntu.list
    UBUNTU_SOURCES_FILE="/etc/apt/sources.list.d/ubuntu.sources"
    
    # Backup if exists
    if [ -f "$UBUNTU_SOURCES_FILE" ]; then
        cp "$UBUNTU_SOURCES_FILE" "/etc/apt/sources.list.d/ubuntu.sources.backup.$(date +%Y%m%d-%H%M%S)~"
        print_message "Existing ubuntu.sources backed up"
    fi
    
    # Write new ubuntu.sources in DEB822 format
    cat > "$UBUNTU_SOURCES_FILE" << EOF
## Ubuntu Main Repositories
Types: deb
URIs: http://archive.ubuntu.com/ubuntu/
Suites: ${UBUNTU_CODENAME} ${UBUNTU_CODENAME}-updates ${UBUNTU_CODENAME}-backports
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

## Ubuntu Security Updates
Types: deb
URIs: http://security.ubuntu.com/ubuntu/
Suites: ${UBUNTU_CODENAME}-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

## Ubuntu Sources (optional - uncomment to enable)
# Types: deb-src
# URIs: http://archive.ubuntu.com/ubuntu/
# Suites: ${UBUNTU_CODENAME} ${UBUNTU_CODENAME}-updates ${UBUNTU_CODENAME}-backports
# Components: main restricted universe multiverse
# Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

# Types: deb-src
# URIs: http://security.ubuntu.com/ubuntu/
# Suites: ${UBUNTU_CODENAME}-security
# Components: main restricted universe multiverse
# Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
    
    print_message "Ubuntu repositories configured in: $UBUNTU_SOURCES_FILE"
    print_message "Format: DEB822 (ubuntu.sources)"
    print_message "Repositories enabled: main, restricted, universe, multiverse"
    apt update
fi

# ============================================
# CONFIGURE TATARANOVICH REPOSITORY (DEBIAN ONLY)
# ============================================

if [ "$OS" = "debian" ] && { [ "$ADD_TATARANOVICH_REPO" = "y" ] || [ "$ADD_TATARANOVICH_REPO" = "Y" ]; }; then
    print_message "Configuring Tataranovich repository..."
    
    # Install required packages if not already installed
    print_message "Installing prerequisites for Tataranovich repository..."
    apt-get install -y curl gnupg
    
    # Download GPG key
    print_message "Downloading Tataranovich GPG key..."
    if curl -fsSL https://www.tataranovich.com/debian/gpg -o /etc/apt/trusted.gpg.d/tataranovich.gpg; then
        print_message "GPG key downloaded successfully"
        chmod 644 /etc/apt/trusted.gpg.d/tataranovich.gpg
    else
        print_error "Failed to download Tataranovich GPG key"
        print_warning "Skipping Tataranovich repository configuration"
        ADD_TATARANOVICH_REPO="n"
    fi
    
    if [ "$ADD_TATARANOVICH_REPO" = "y" ] || [ "$ADD_TATARANOVICH_REPO" = "Y" ]; then
        # Add repository
        print_message "Adding Tataranovich repository..."
        
        # Use detected codename for repository
        TATARANOVICH_CODENAME=${VERSION_CODENAME:-bookworm}
        
        echo "deb http://www.tataranovich.com/debian ${TATARANOVICH_CODENAME} main" | tee /etc/apt/sources.list.d/tataranovich.list > /dev/null
        print_message "Tataranovich repository added: /etc/apt/sources.list.d/tataranovich.list"
        
        # Update package lists
        print_message "Updating package lists with Tataranovich repository..."
        if apt-get update; then
            print_message "Package lists updated successfully"
            
            # Install mc from Tataranovich repository
            print_message "Installing Midnight Commander from Tataranovich repository..."
            if apt-get install -y mc; then
                print_message "Midnight Commander installed successfully from Tataranovich repository"
            else
                print_warning "Failed to install mc from Tataranovich repository"
                print_message "Installing mc from standard repositories..."
                apt-get install -y mc || print_warning "Failed to install mc"
            fi
        else
            print_warning "Failed to update package lists with Tataranovich repository"
            print_message "Installing mc from standard repositories..."
            apt-get install -y mc || print_warning "Failed to install mc"
        fi
    fi
    echo ""
else
    # Install mc from standard repositories if Tataranovich is not used
    print_message "Installing Midnight Commander from standard repositories..."
    apt-get install -y mc || print_warning "Failed to install mc"
    echo ""
fi

# ============================================
# INSTALL AND CONFIGURE ZSH FOR USER
# ============================================

if [ "$INSTALL_ZSH" = "y" ] || [ "$INSTALL_ZSH" = "Y" ] && [ ! -z "$NEW_USERNAME" ]; then
    print_message "Installing Oh My Zsh for $NEW_USERNAME"
    
    USER_HOME=$(eval echo ~$NEW_USERNAME)
    
    # Install Oh My Zsh as user
    print_message "Installing Oh My Zsh..."
    sudo -u "$NEW_USERNAME" -i bash << EOF
        export HOME="$USER_HOME"
        export RUNZSH=no
        export CHSH=no
        cd "\$HOME"
        sh -c "\$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
EOF
    
    if [ -d "$USER_HOME/.oh-my-zsh" ]; then
        print_message "Oh My Zsh installed successfully"
        
        # Install zsh plugins
        print_message "Installing zsh plugins..."
        
        sudo -u "$NEW_USERNAME" -i bash << EOF
            export HOME="$USER_HOME"
            cd "\$HOME"
            git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "\${ZSH_CUSTOM:-\$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting"
            git clone https://github.com/zsh-users/zsh-autosuggestions "\${ZSH_CUSTOM:-\$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions"
            git clone https://github.com/zsh-users/zsh-history-substring-search "\${ZSH_CUSTOM:-\$HOME/.oh-my-zsh/custom}/plugins/zsh-history-substring-search"
EOF
        
        print_message "Zsh plugins installed successfully"
        
        # Download custom .zshrc
        print_message "Downloading custom .zshrc configuration..."
        if sudo -u "$NEW_USERNAME" curl -fsSL https://raw.githubusercontent.com/civisrom/debian-ubuntu-setup/refs/heads/main/config/.zshrc -o "$USER_HOME/.zshrc"; then
            print_message "Custom .zshrc downloaded successfully"
            sudo -u "$NEW_USERNAME" chmod 644 "$USER_HOME/.zshrc"
        else
            print_warning "Failed to download custom .zshrc, using default"
        fi
        
        # Change default shell to zsh
        print_message "Changing default shell to zsh for $NEW_USERNAME"
        chsh -s $(which zsh) "$NEW_USERNAME"
        print_message "Default shell changed to zsh"
    else
        print_error "Oh My Zsh installation failed"
    fi
    echo ""
fi

# Configure sysctl.conf
if [ "$CONFIGURE_SYSCTL" = "y" ] || [ "$CONFIGURE_SYSCTL" = "Y" ]; then
    print_message "Configuring system parameters (sysctl.conf)..."
    
    # Backup original sysctl.conf
    if [ -f /etc/sysctl.conf ]; then
        cp /etc/sysctl.conf /etc/sysctl.conf.backup.$(date +%Y%m%d-%H%M%S)~
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
        cp "$SSHD_CONFIG" "/etc/ssh/sshd_config.backup.$(date +%Y%m%d-%H%M%S)~"
        print_message "Original sshd_config backed up"
    fi
    
    # Function to set or update SSH parameter
    configure_ssh_parameter() {
        local param_name="$1"
        local param_value="$2"
        local config_file="$3"
        
        # Check if parameter exists (commented or uncommented)
        if grep -q "^#*${param_name} " "$config_file"; then
            # Parameter exists, replace it in place
            # Find the first occurrence and replace it (whether commented or not)
            sed -i "0,/^#*${param_name} .*/{s/^#*${param_name} .*/${param_name} ${param_value}/}" "$config_file"
            
            # Remove any duplicate lines of this parameter (in case there were multiple)
            # Keep only the first occurrence (which we just modified)
            sed -i "0,/^${param_name} ${param_value}/b; /^#*${param_name} /d" "$config_file"
            
            print_message "SSH parameter set: ${param_name} ${param_value}"
        else
            # Parameter doesn't exist, add it at the end
            echo "" >> "$config_file"
            echo "# Custom SSH configuration" >> "$config_file"
            echo "${param_name} ${param_value}" >> "$config_file"
            print_message "SSH parameter added: ${param_name} ${param_value}"
        fi
    }
    
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
    
    # Configure PubkeyAuthentication
    if [ ! -z "$SSH_PUBKEY_AUTH" ]; then
        configure_ssh_parameter "PubkeyAuthentication" "$SSH_PUBKEY_AUTH" "$SSHD_CONFIG"
    fi
    
    # Configure PasswordAuthentication
    if [ ! -z "$SSH_PASSWORD_AUTH" ]; then
        configure_ssh_parameter "PasswordAuthentication" "$SSH_PASSWORD_AUTH" "$SSHD_CONFIG"
    fi
    
    # Configure PermitEmptyPasswords (ALWAYS no for security)
    if [ ! -z "$SSH_EMPTY_PASSWORDS" ]; then
        configure_ssh_parameter "PermitEmptyPasswords" "$SSH_EMPTY_PASSWORDS" "$SSHD_CONFIG"
        print_warning "PermitEmptyPasswords set to 'no' for security reasons"
    fi
    
    # Configure PermitRootLogin
    if [ ! -z "$SSH_ROOT_LOGIN" ]; then
        configure_ssh_parameter "PermitRootLogin" "$SSH_ROOT_LOGIN" "$SSHD_CONFIG"
    fi
    
    # Add AllowUsers if specified
    if [ ! -z "$SSH_ALLOW_USERS" ]; then
        # Remove existing AllowUsers lines
        sed -i '/^AllowUsers /d' "$SSHD_CONFIG"
        
        # Add AllowUsers at the end of file
        echo "" >> "$SSHD_CONFIG"
        echo "# Allowed users" >> "$SSHD_CONFIG"
        echo "AllowUsers $SSH_ALLOW_USERS" >> "$SSHD_CONFIG"
        print_message "AllowUsers set to: $SSH_ALLOW_USERS"
    fi
    
    # Test SSH configuration
    print_message "Testing SSH configuration..."
    if sshd -t; then
        print_message "SSH configuration is valid"
        
        # Restart SSH service
        print_message "Restarting SSH service..."
        if systemctl restart sshd 2>/dev/null; then
            print_message "SSH service restarted (sshd)"
        elif systemctl restart ssh 2>/dev/null; then
            print_message "SSH service restarted (ssh)"
        elif service ssh restart 2>/dev/null; then
            print_message "SSH service restarted (service ssh)"
        elif service sshd restart 2>/dev/null; then
            print_message "SSH service restarted (service sshd)"
        else
            print_error "Failed to restart SSH service"
            print_warning "Please restart SSH manually: sudo systemctl restart ssh"
        fi
    else
        print_error "SSH configuration test failed!"
        print_error "Restoring backup..."
        LATEST_BACKUP=$(ls -t /etc/ssh/sshd_config.backup.*~ 2>/dev/null | head -1)
        if [ ! -z "$LATEST_BACKUP" ]; then
            cp "$LATEST_BACKUP" "$SSHD_CONFIG"
            print_error "SSH configuration restored from backup"
        else
            print_error "No backup found to restore"
        fi
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
                    ufw allow ${PORT}/${PROTOCOL} comment "Custom ${PROTOCOL} port"
                    print_message "UFW rule added: Allow port ${PORT}/${PROTOCOL}"
                else
                    print_warning "Invalid port number: $PORT (must be 1-65535). Skipping."
                fi
            elif [[ "$PORT_SPEC" =~ ^[0-9]+$ ]]; then
                # Port without protocol - default to tcp
                PORT="$PORT_SPEC"
                
                if [ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ]; then
                    ufw allow ${PORT}/tcp comment "Custom tcp port"
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
    echo "y" | ufw enable
    ufw status verbose
else
    print_message "Skipping UFW configuration (not requested)"
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
            # Save original permissions
            ORIGINAL_PERMS=$(stat -c "%a" "$UFW_BEFORE_RULES" 2>/dev/null || stat -f "%Mp%Lp" "$UFW_BEFORE_RULES" 2>/dev/null)
            
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
                print "-A ufw-before-input -p icmp --icmp-type destination-unreachable -j DROP"
                print "-A ufw-before-input -p icmp --icmp-type source-quench -j DROP"
                print "-A ufw-before-input -p icmp --icmp-type time-exceeded -j DROP"
                print "-A ufw-before-input -p icmp --icmp-type parameter-problem -j DROP"
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
                ufw reload
                print_message "UFW reloaded"
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
                usermod -aG docker $SUDO_USER
                print_message "User $SUDO_USER added to docker group"
            fi
            
            if [ ! -z "$NEW_USERNAME" ] || [ ! -z "$SUDO_USER" ]; then
                print_warning "Users need to log out and log back in (or run 'newgrp docker') for docker group to take effect"
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
        
        USER_HOME=$(eval echo ~$NEW_USERNAME)
        
        # Get the latest Go version from official website
        print_message "Fetching latest Go version..."
        LATEST_GO_VERSION=$(curl -s https://go.dev/VERSION?m=text | head -1)
        
        if [ -z "$LATEST_GO_VERSION" ]; then
            print_warning "Could not fetch latest Go version, using fallback: go1.23.4"
            LATEST_GO_VERSION="go1.23.4"
        fi
        
        print_message "Latest Go version: $LATEST_GO_VERSION"
        
        # Download Go
        GO_ARCHIVE="${LATEST_GO_VERSION}.linux-amd64.tar.gz"
        GO_URL="https://go.dev/dl/${GO_ARCHIVE}"
        
        print_message "Downloading Go from: $GO_URL"
        if wget -q --show-progress "$GO_URL" -O "/tmp/${GO_ARCHIVE}"; then
            print_message "Go downloaded successfully"
            
            # Remove old Go installation
            if [ -d /usr/local/go ]; then
                print_message "Removing old Go installation..."
                rm -rf /usr/local/go
            fi
            
            # Extract Go
            print_message "Extracting Go..."
            tar -C /usr/local -xzf "/tmp/${GO_ARCHIVE}"
            print_message "Go extracted to /usr/local/go"
            
            # Cleanup
            rm "/tmp/${GO_ARCHIVE}"
            
            # Add Go to PATH for the user
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
                sudo -u "$NEW_USERNAME" bash << EOF
                    echo "" >> "$SHELL_RC"
                    echo "# Go language" >> "$SHELL_RC"
                    echo "export PATH=\$PATH:/usr/local/go/bin" >> "$SHELL_RC"
                    echo "export PATH=\$PATH:\$HOME/go/bin" >> "$SHELL_RC"
EOF
                print_message "Go PATH added to $SHELL_RC"
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
        else
            print_error "Failed to download Go"
        fi
        
        echo ""
    fi
else
    print_message "Skipping Go installation (not requested)"
fi

# ============================================
# BUILD AND INSTALL IPSET
# ============================================

if [ "$INSTALL_IPSET" = "y" ] || [ "$INSTALL_IPSET" = "Y" ]; then
    print_message "Building and installing latest version of ipset..."
    echo ""
    
    # Check if kernel headers are installed
    KERNEL_VERSION=$(uname -r)
    KERNEL_HEADERS_DIR="/lib/modules/${KERNEL_VERSION}/build"
    
    if [ ! -d "$KERNEL_HEADERS_DIR" ]; then
        print_error "Kernel headers not found at: $KERNEL_HEADERS_DIR"
        print_error "Installing kernel headers..."
        
        if apt install -y linux-headers-${KERNEL_VERSION}; then
            print_message "Kernel headers installed successfully"
        else
            print_error "Failed to install kernel headers"
            print_error "ipset compilation requires kernel headers"
            print_message "Try manually: sudo apt install linux-headers-$(uname -r)"
            print_message "Skipping ipset installation"
            INSTALL_IPSET="n"
        fi
    else
        print_message "Kernel headers found: $KERNEL_HEADERS_DIR"
    fi
    
    if [ "$INSTALL_IPSET" = "y" ] || [ "$INSTALL_IPSET" = "Y" ]; then
        # Get the latest ipset version
        print_message "Fetching latest ipset version..."
        LATEST_IPSET_VERSION=$(curl -s https://ipset.netfilter.org/ | grep -oP 'ipset-\K[0-9]+\.[0-9]+' | head -1)
        
        if [ -z "$LATEST_IPSET_VERSION" ]; then
            print_warning "Could not fetch latest ipset version, using fallback: 7.24"
            LATEST_IPSET_VERSION="7.24"
        fi
        
        print_message "Latest ipset version: $LATEST_IPSET_VERSION"
        
        # Download ipset
        IPSET_ARCHIVE="ipset-${LATEST_IPSET_VERSION}.tar.bz2"
        IPSET_URL="https://ipset.netfilter.org/${IPSET_ARCHIVE}"
        
        print_message "Downloading ipset from: $IPSET_URL"
        if wget -q --show-progress "$IPSET_URL" -O "/tmp/${IPSET_ARCHIVE}"; then
            print_message "ipset downloaded successfully"
            
            # Extract ipset
            print_message "Extracting ipset..."
            cd /tmp
            tar xjf "${IPSET_ARCHIVE}"
            
            IPSET_DIR="ipset-${LATEST_IPSET_VERSION}"
            
            if [ -d "/tmp/${IPSET_DIR}" ]; then
                cd "/tmp/${IPSET_DIR}"
                
                # Configure with proper kernel source
                print_message "Configuring ipset with kernel headers..."
                if ./configure --prefix=/usr --with-kmod=no; then
                    print_message "Configuration successful"
                    
                    # Build
                    print_message "Building ipset (using $(nproc) cores)..."
                    if make -j$(nproc); then
                        print_message "Build successful"
                        
                        # Install
                        print_message "Installing ipset..."
                        if make install; then
                            print_message "ipset installed successfully"
                            
                            # Verify installation
                            if ipset --version &> /dev/null; then
                                IPSET_INSTALLED_VERSION=$(ipset --version)
                                print_message "ipset version: $IPSET_INSTALLED_VERSION"
                            else
                                print_warning "ipset installed but version check failed"
                            fi
                        else
                            print_error "Failed to install ipset"
                        fi
                    else
                        print_error "Failed to build ipset"
                    fi
                else
                    print_error "Failed to configure ipset"
                    print_error "Check that kernel headers are properly installed"
                fi
                
                # Cleanup
                cd /tmp
                rm -rf "/tmp/${IPSET_DIR}" "/tmp/${IPSET_ARCHIVE}"
            else
                print_error "Failed to extract ipset"
            fi
        else
            print_error "Failed to download ipset"
        fi
    fi
    
    echo ""
else
    print_message "Skipping ipset installation (not requested)"
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

# ============================================
# CONFIGURE CRONTAB
# ============================================

if [ "$CONFIGURE_CRONTAB" = "y" ] || [ "$CONFIGURE_CRONTAB" = "Y" ]; then
    print_message "Configuring crontab for root..."
    
    # Backup existing crontab
    if crontab -l &>/dev/null; then
        crontab -l > /tmp/crontab.backup.$(date +%Y%m%d-%H%M%S)~
        print_message "Existing crontab backed up"
    fi
    
    # Create new crontab content with environment variables
    CRONTAB_CONTENT="# Crontab environment variables
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
    
    # Install new crontab
    echo "$CRONTAB_CONTENT" | crontab -
    print_message "Crontab configured successfully"
    
    # Display configured crontab
    print_message "Configured crontab:"
    echo "----------------------------------------"
    crontab -l
    echo "----------------------------------------"
    echo ""
else
    print_message "Skipping crontab configuration (not requested)"
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

# ============================================
# INSTALL CUSTOM UFW DOCKER RULES
# ============================================

if [ "$INSTALL_UFW_CUSTOM_RULES" = "y" ] || [ "$INSTALL_UFW_CUSTOM_RULES" = "Y" ]; then
    print_message "Installing custom UFW Docker rules..."
    echo ""
    
    # Check if p7zip is installed, install if needed
    if ! command -v 7z &> /dev/null; then
        print_message "Installing p7zip-full for archive extraction..."
        apt install -y p7zip-full
    fi
    
    UFW_ARCHIVE_URL="https://github.com/civisrom/debian-ubuntu-setup/raw/refs/heads/main/config/ufw-docker-rules-v4.7z"
    UFW_ARCHIVE_FILE="/tmp/ufw-docker-rules-v4.7z"
    UFW_EXTRACT_DIR="/tmp/ufw-docker-rules"
    UFW_SCRIPT_NAME="ufw-docker-rules-v4.sh"
    UFW_INSTALL_PATH="/opt/${UFW_SCRIPT_NAME}"
    
    print_message "Downloading custom UFW rules archive..."
    if wget -q --show-progress "$UFW_ARCHIVE_URL" -O "$UFW_ARCHIVE_FILE"; then
        print_message "Archive downloaded successfully"
        
        # Create extraction directory
        mkdir -p "$UFW_EXTRACT_DIR"
        
        # Extract with password
        print_message "Extracting archive..."
        if 7z x -p"${UFW_CUSTOM_RULES_PASSWORD}" -o"${UFW_EXTRACT_DIR}" "$UFW_ARCHIVE_FILE" -y > /dev/null 2>&1; then
            print_message "Archive extracted successfully"
            
            # Find the script file
            if [ -f "${UFW_EXTRACT_DIR}/${UFW_SCRIPT_NAME}" ]; then
                print_message "Installing script to ${UFW_INSTALL_PATH}..."
                
                # Copy script to /opt
                cp "${UFW_EXTRACT_DIR}/${UFW_SCRIPT_NAME}" "$UFW_INSTALL_PATH"
                
                # Set executable permissions
                chmod +x "$UFW_INSTALL_PATH"
                print_message "Script installed with executable permissions"
                
                # Execute the script
                print_message "Executing custom UFW Docker rules script..."
                echo ""
                print_header "═══════════════════════════════════════════════════"
                print_header "  Custom UFW Docker Rules Script Output"
                print_header "═══════════════════════════════════════════════════"
                echo ""
                
                if bash "$UFW_INSTALL_PATH"; then
                    echo ""
                    print_header "═══════════════════════════════════════════════════"
                    print_message "Custom UFW Docker rules applied successfully"
                else
                    echo ""
                    print_header "═══════════════════════════════════════════════════"
                    print_warning "Custom UFW Docker rules script completed with warnings"
                fi
            else
                print_error "Script file not found in archive: ${UFW_SCRIPT_NAME}"
            fi
            
            # Cleanup
            rm -rf "$UFW_EXTRACT_DIR"
            rm -f "$UFW_ARCHIVE_FILE"
        else
            print_error "Failed to extract archive. Check if password is correct."
            print_error "Password authentication failed or archive is corrupted"
            rm -f "$UFW_ARCHIVE_FILE"
        fi
    else
        print_error "Failed to download custom UFW rules archive"
    fi
    
    echo ""
else
    print_message "Skipping custom UFW Docker rules (not requested)"
fi

# Final message
echo ""
print_header "═════════════════════════════════════════"
print_message "System setup completed successfully!"
print_header "═════════════════════════════════════════"
print_message "Summary:"
print_message "- OS: $OS $VERSION ($VERSION_CODENAME)"
print_message "- Packages installed"

if [ "$INSTALL_RUSTDESK" = "y" ] || [ "$INSTALL_RUSTDESK" = "Y" ]; then
    if systemctl is-enabled --quiet rustdesk-compose.service 2>/dev/null; then
        print_message "- RustDesk Server: Installed and enabled"
        print_message "  Directory: /root/rustdesk"
        print_message "  Service: rustdesk-compose.service"
        if systemctl is-active --quiet rustdesk-compose.service; then
            print_message "  Status: Running"
        else
            print_message "  Status: Enabled (will start with Docker)"
        fi
    else
        print_message "- RustDesk Server: Installation attempted but service not enabled"
    fi
else
    print_message "- RustDesk Server: Not installed"
fi

if [ "$SET_ROOT_PASSWORD" = "y" ] || [ "$SET_ROOT_PASSWORD" = "Y" ]; then
    print_message "- Root password: SET"
else
    print_message "- Root password: NOT SET"
fi

if [ ! -z "$NEW_USERNAME" ]; then
    print_message "- New user created: $NEW_USERNAME"
    if [ "$CONFIGURE_USER_SSH_KEY" = "y" ] || [ "$CONFIGURE_USER_SSH_KEY" = "Y" ]; then
        print_message "  - SSH key configured"
    fi
    if [ "$INSTALL_ZSH" = "y" ] || [ "$INSTALL_ZSH" = "Y" ]; then
        print_message "  - zsh and Oh My Zsh installed"
    fi
else
    print_message "- New user: NOT CREATED"
fi

if [ "$CONFIGURE_CRONTAB" = "y" ] || [ "$CONFIGURE_CRONTAB" = "Y" ]; then
    print_message "- Crontab configured for root"
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
        if [ "$ADD_TATARANOVICH_REPO" = "y" ] || [ "$ADD_TATARANOVICH_REPO" = "Y" ]; then
            print_message "- Tataranovich repository: ADDED (custom mc)"
        fi
    else
        print_message "- Ubuntu repositories configured (main, restricted, universe, multiverse)"
    fi
fi

if [ "$CONFIGURE_UFW" = "y" ] || [ "$CONFIGURE_UFW" = "Y" ]; then
    print_message "- UFW firewall configured and enabled"
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

if command -v go &> /dev/null || [ -f /usr/local/go/bin/go ]; then
    if [ -f /usr/local/go/bin/go ]; then
        GO_VERSION=$(/usr/local/go/bin/go version 2>/dev/null || echo "unknown")
        print_message "- Go: Installed ($GO_VERSION)"
        if [ ! -z "$NEW_USERNAME" ]; then
            USER_HOME=$(eval echo ~$NEW_USERNAME)
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

if [ "$INSTALL_MOTD" = "y" ] || [ "$INSTALL_MOTD" = "Y" ]; then
    print_message "- Custom MOTD: Installed"
else
    print_message "- Custom MOTD: Not installed"
fi

if [ "$INSTALL_UFW_CUSTOM_RULES" = "y" ] || [ "$INSTALL_UFW_CUSTOM_RULES" = "Y" ]; then
    if [ -f "/opt/ufw-docker-rules-v4.sh" ]; then
        print_message "- Custom UFW Docker rules: Installed and executed"
        print_message "  Script location: /opt/ufw-docker-rules-v4.sh"
    else
        print_message "- Custom UFW Docker rules: Installation attempted but failed"
    fi
else
    print_message "- Custom UFW Docker rules: Not installed"
fi

print_message ""

if [ "$CONFIGURE_SYSCTL" = "y" ] || [ "$CONFIGURE_SYSCTL" = "Y" ] || [ "$CONFIGURE_REPOS" = "y" ] || [ "$CONFIGURE_REPOS" = "Y" ] || [ "$CONFIGURE_SSH" = "y" ] || [ "$CONFIGURE_SSH" = "Y" ] || [ "$BLOCK_ICMP" = "y" ] || [ "$BLOCK_ICMP" = "Y" ] || [ "$CONFIGURE_CRONTAB" = "y" ] || [ "$CONFIGURE_CRONTAB" = "Y" ]; then
    print_message "Backup files saved with timestamp (format: filename.backup.YYYYMMDD-HHMMSS~):"
    if [ "$CONFIGURE_SYSCTL" = "y" ] || [ "$CONFIGURE_SYSCTL" = "Y" ]; then
        print_message "- /etc/sysctl.conf.backup.*~"
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
    fi
    if [ "$BLOCK_ICMP" = "y" ] || [ "$BLOCK_ICMP" = "Y" ]; then
        print_message "- /etc/ufw/before.rules.backup.*~"
    fi
    if [ "$CONFIGURE_CRONTAB" = "y" ] || [ "$CONFIGURE_CRONTAB" = "Y" ]; then
        print_message "- /tmp/crontab.backup.*~"
    fi
    print_message ""
fi

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

if [ "$CONFIGURE_CRONTAB" = "y" ] || [ "$CONFIGURE_CRONTAB" = "Y" ]; then
    print_warning "$STEP_NUM. Check crontab: sudo crontab -l"
    STEP_NUM=$((STEP_NUM + 1))
fi

print_message ""
print_message "Useful commands:"
print_message "sudo ufw status verbose"
print_message "sudo ufw status numbered"
print_message "sudo nano /etc/sysctl.conf"
print_message "sudo nano /etc/apt/sources.list"
if [ "$OS" = "ubuntu" ]; then
    print_message "sudo nano /etc/apt/sources.list.d/ubuntu.list"
fi
print_message "sudo nano /etc/ssh/sshd_config"
print_message "sudo crontab -l"
if [ ! -z "$NEW_USERNAME" ]; then
    print_message "su - $NEW_USERNAME"
fi
print_warning "$STEP_NUM. Reboot system to apply all changes: sudo reboot"

exit 0
