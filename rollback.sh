#!/bin/bash

#############################################
# Rollback Script for System Setup
# Description: Restore original configuration files
#############################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run as root"
    exit 1
fi

print_warning "========================================="
print_warning "System Setup Rollback Script"
print_warning "========================================="
print_warning "This script will restore backup configuration files"
echo ""

# Find backup files
SYSCTL_BACKUPS=$(ls -t /etc/sysctl.conf.backup.* 2>/dev/null | head -5)
SOURCES_BACKUPS=$(ls -t /etc/apt/sources.list.backup.* 2>/dev/null | head -5)

# Restore sysctl.conf
if [ ! -z "$SYSCTL_BACKUPS" ]; then
    echo "Available sysctl.conf backups:"
    echo "$SYSCTL_BACKUPS" | nl
    echo ""
    read -p "Enter number to restore (or 0 to skip): " SYSCTL_CHOICE
    
    if [ "$SYSCTL_CHOICE" -gt 0 ] 2>/dev/null; then
        SELECTED_SYSCTL=$(echo "$SYSCTL_BACKUPS" | sed -n "${SYSCTL_CHOICE}p")
        if [ ! -z "$SELECTED_SYSCTL" ]; then
            cp "$SELECTED_SYSCTL" /etc/sysctl.conf
            print_message "sysctl.conf restored from $SELECTED_SYSCTL"
            sysctl -p
        fi
    fi
else
    print_warning "No sysctl.conf backups found"
fi

# Restore sources.list (Debian only)
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [ "$ID" = "debian" ] && [ ! -z "$SOURCES_BACKUPS" ]; then
        echo ""
        echo "Available sources.list backups:"
        echo "$SOURCES_BACKUPS" | nl
        echo ""
        read -p "Enter number to restore (or 0 to skip): " SOURCES_CHOICE
        
        if [ "$SOURCES_CHOICE" -gt 0 ] 2>/dev/null; then
            SELECTED_SOURCES=$(echo "$SOURCES_BACKUPS" | sed -n "${SOURCES_CHOICE}p")
            if [ ! -z "$SELECTED_SOURCES" ]; then
                cp "$SELECTED_SOURCES" /etc/apt/sources.list
                print_message "sources.list restored from $SELECTED_SOURCES"
                apt update
            fi
        fi
    fi
fi

# UFW management
echo ""
read -p "Do you want to disable UFW? (y/N): " DISABLE_UFW
if [ "$DISABLE_UFW" = "y" ] || [ "$DISABLE_UFW" = "Y" ]; then
    ufw disable
    print_message "UFW disabled"
fi

print_message "========================================="
print_message "Rollback completed"
print_message "========================================="

exit 0
