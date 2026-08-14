#!/bin/bash

# HACS Installation Script for Home Assistant Container
# This script installs HACS (Home Assistant Community Store) into your Home Assistant configuration

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
HA_CONFIG_DIR="/srv/docker/homeassistant/config"
HA_CONTAINER_NAME="homeassistant"
BACKUP_DIR="${HA_CONFIG_DIR}.backup-$(date +%Y%m%d-%H%M%S)"

# Function to print colored output
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to check if running as root or with sudo
check_sudo() {
    if [ "$EUID" -ne 0 ]; then 
        print_message "$RED" "Please run this script with sudo or as root"
        exit 1
    fi
}

# Function to verify HACS installation
verify_hacs_installation() {
    local hacs_dir="${HA_CONFIG_DIR}/custom_components/hacs"
    
    print_message "$YELLOW" "Verifying HACS installation..."
    
    # Check if directory exists
    if [ ! -d "$hacs_dir" ]; then
        print_message "$RED" "HACS directory not found!"
        return 1
    fi
    
    # Check for essential files
    local essential_files=("__init__.py" "manifest.json")
    local missing_files=()
    
    for file in "${essential_files[@]}"; do
        if [ ! -f "${hacs_dir}/${file}" ]; then
            missing_files+=("$file")
        fi
    done
    
    if [ ${#missing_files[@]} -ne 0 ]; then
        print_message "$RED" "Missing essential files: ${missing_files[*]}"
        return 1
    fi
    
    print_message "$GREEN" "HACS installation verified successfully!"
    return 0
}

# Main installation process
main() {
    # Check for sudo
    check_sudo
    
    print_message "$GREEN" "=== HACS Installation Script ==="
    print_message "$YELLOW" "Home Assistant Config Directory: $HA_CONFIG_DIR"
    
    # Step 1: Create backup
    print_message "$YELLOW" "Step 1: Creating backup of Home Assistant configuration..."
    if [ -d "$BACKUP_DIR" ]; then
        print_message "$RED" "Backup directory already exists: $BACKUP_DIR"
        print_message "$YELLOW" "Removing old backup..."
        rm -rf "$BACKUP_DIR"
    fi
    
    cp -a "$HA_CONFIG_DIR" "$BACKUP_DIR"
    print_message "$GREEN" "Backup created: $BACKUP_DIR"
    
    # Step 2: Download and install HACS
    print_message "$YELLOW" "Step 2: Downloading and installing HACS..."
    cd "$HA_CONFIG_DIR" || exit 1
    
    # Download and run HACS installer
    if wget -O - https://get.hacs.xyz | bash -; then
        print_message "$GREEN" "HACS downloaded and installed"
    else
        print_message "$RED" "Failed to download and install HACS"
        exit 1
    fi
    
    # Step 3: Verify installation
    print_message "$YELLOW" "Step 3: Verifying installation..."
    if ! verify_hacs_installation; then
        print_message "$RED" "HACS installation verification failed"
        print_message "$YELLOW" "Attempting to fix installation..."
        
        # Remove incomplete installation
        rm -rf "${HA_CONFIG_DIR}/custom_components/hacs"
        
        # Retry installation
        print_message "$YELLOW" "Retrying HACS installation..."
        cd "$HA_CONFIG_DIR" || exit 1
        wget -O - https://get.hacs.xyz | bash -
        
        # Verify again
        if ! verify_hacs_installation; then
            print_message "$RED" "HACS installation failed. Please check the logs and try again."
            exit 1
        fi
    fi
    
    # Step 4: Set proper permissions
    print_message "$YELLOW" "Step 4: Setting proper permissions..."
    # Get the user who owns the config directory
    local config_owner=$(stat -c '%U' "$HA_CONFIG_DIR")
    chown -R "$config_owner:$config_owner" "${HA_CONFIG_DIR}/custom_components/hacs"
    print_message "$GREEN" "Permissions set for user: $config_owner"
    
    # Step 5: Restart Home Assistant
    print_message "$YELLOW" "Step 5: Restarting Home Assistant container..."
    if docker restart "$HA_CONTAINER_NAME"; then
        print_message "$GREEN" "Home Assistant container restarted"
    else
        print_message "$RED" "Failed to restart Home Assistant container"
        print_message "$YELLOW" "Please restart it manually with: docker restart $HA_CONTAINER_NAME"
        exit 1
    fi
    
    # Step 6: Final instructions
    print_message "$GREEN" "=== HACS Installation Complete! ==="
    print_message "$YELLOW" "Next steps:"
    echo "1. Wait 30-60 seconds for Home Assistant to start"
    echo "2. Clear your browser cache (or use incognito/private mode)"
    echo "3. Open Home Assistant"
    echo "4. Go to Settings → Devices & services"
    echo "5. You should see HACS listed there"
    echo ""
    print_message "$YELLOW" "Backup location: $BACKUP_DIR"
    print_message "$YELLOW" "To restore backup if needed:"
    echo "  sudo rm -rf $HA_CONFIG_DIR && sudo cp -a $BACKUP_DIR $HA_CONFIG_DIR"
    echo ""
    print_message "$GREEN" "Installation completed successfully!"
}

# Run the main function
main "$@"