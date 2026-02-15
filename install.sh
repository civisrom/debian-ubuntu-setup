#!/bin/bash

#############################################
# One-line installer wrapper
# Downloads, runs, and cleans up system-setup.sh
#############################################

set -e

SCRIPT_URL="https://raw.githubusercontent.com/civisrom/debian-ubuntu-setup/main/system-setup.sh"
CHECKSUM_URL="https://raw.githubusercontent.com/civisrom/debian-ubuntu-setup/main/system-setup.sh.sha256"
TEMP_SCRIPT="/tmp/system-setup-$$.sh"
TEMP_CHECKSUM="/tmp/system-setup-$$.sha256"

# Cleanup temporary files on exit (normal, error, or interrupt)
cleanup() {
    rm -f "$TEMP_SCRIPT" "$TEMP_CHECKSUM"
}
trap cleanup EXIT

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

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run as root"
    exit 1
fi

# Check if wget is available
if ! command -v wget &> /dev/null; then
    print_warning "wget not found, attempting to install..."
    if command -v apt-get &> /dev/null; then
        apt-get update -qq && apt-get install -y -qq wget
    else
        print_error "wget is required but not installed and cannot be auto-installed"
        exit 1
    fi
fi

# Download script
print_message "Downloading setup script..."
if wget --show-progress "$SCRIPT_URL" -O "$TEMP_SCRIPT" 2>&1 | grep -v "^$"; then
    print_message "Download complete"
else
    print_error "Failed to download script"
    exit 1
fi

# Download and verify checksum if available
print_message "Verifying integrity..."
if wget -q "$CHECKSUM_URL" -O "$TEMP_CHECKSUM" 2>/dev/null; then
    # Extract expected checksum
    EXPECTED_CHECKSUM=$(awk '{print $1}' "$TEMP_CHECKSUM")

    # Calculate actual checksum
    ACTUAL_CHECKSUM=$(sha256sum "$TEMP_SCRIPT" | awk '{print $1}')

    if [ "$EXPECTED_CHECKSUM" = "$ACTUAL_CHECKSUM" ]; then
        print_message "Integrity check passed"
    else
        print_error "Integrity check failed!"
        print_error "Expected: $EXPECTED_CHECKSUM"
        print_error "Got:      $ACTUAL_CHECKSUM"
        rm -f "$TEMP_SCRIPT" "$TEMP_CHECKSUM"
        exit 1
    fi
    rm -f "$TEMP_CHECKSUM"
else
    print_warning "Checksum file not available, skipping integrity check"
    print_warning "This is less secure. Consider adding a checksum file to the repository."
fi

# Make executable
chmod +x "$TEMP_SCRIPT"

# Run script (disable set -e to capture exit code properly)
print_message "Running setup script..."
set +e
bash "$TEMP_SCRIPT"
EXIT_CODE=$?
set -e

# Cleanup is handled by trap, but log it
print_message "Cleaning up temporary files..."

if [ $EXIT_CODE -eq 0 ]; then
    print_message "Setup completed successfully and temporary files removed"
else
    print_error "Setup failed with exit code $EXIT_CODE"
fi

exit $EXIT_CODE
