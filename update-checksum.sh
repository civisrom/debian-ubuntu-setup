#!/bin/bash

#############################################
# Utility script to update system-setup.sh checksum
# Run this after editing system-setup.sh
#############################################

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if system-setup.sh exists
if [ ! -f "system-setup.sh" ]; then
    echo "Error: system-setup.sh not found in current directory"
    exit 1
fi

# Generate new checksum
print_message "Calculating SHA256 checksum for system-setup.sh..."
sha256sum system-setup.sh > system-setup.sh.sha256

# Display result
CHECKSUM=$(cat system-setup.sh.sha256)
print_message "Checksum updated successfully:"
echo "  $CHECKSUM"
echo ""

# Check if file is staged
if git diff --cached --name-only | grep -q "system-setup.sh"; then
    print_warning "system-setup.sh is staged for commit"
    print_message "Don't forget to also stage the checksum file:"
    echo "  git add system-setup.sh.sha256"
fi

print_message "Done! Remember to commit and push both files:"
echo "  git add system-setup.sh system-setup.sh.sha256"
echo "  git commit -m 'Update system-setup.sh and checksum'"
echo "  git push"
