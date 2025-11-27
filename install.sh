#!/bin/bash

#############################################
# One-line installer wrapper
# Downloads, runs, and cleans up system-setup.sh
#############################################

set -e

SCRIPT_URL="https://raw.githubusercontent.com/civisrom/debian-ubuntu-setup/main/system-setup.sh"
TEMP_SCRIPT="/tmp/system-setup-$$.sh"

# Colors
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

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run as root"
    exit 1
fi

# Download script
print_message "Downloading setup script..."
if wget -q "$SCRIPT_URL" -O "$TEMP_SCRIPT"; then
    print_message "Download complete"
else
    print_error "Failed to download script"
    exit 1
fi

# Make executable
chmod +x "$TEMP_SCRIPT"

# Run script
print_message "Running setup script..."
bash "$TEMP_SCRIPT"
EXIT_CODE=$?

# Cleanup
print_message "Cleaning up temporary files..."
rm -f "$TEMP_SCRIPT"

if [ $EXIT_CODE -eq 0 ]; then
    print_message "Setup completed successfully and temporary files removed"
else
    print_error "Setup failed with exit code $EXIT_CODE"
fi

exit $EXIT_CODE
