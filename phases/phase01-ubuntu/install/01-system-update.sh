#!/bin/bash
# Phase 01 - Step 01
# Usage: ./update_system.sh [--log-file PATH] [--no-reboot]

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
LOG_FILE=""
REBOOT=true

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --log-file)
            LOG_FILE="$2"
            shift 2
            ;;
        --no-reboot)
            REBOOT=false
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --log-file PATH    Save log to specified file"
            echo "  --no-reboot        Skip automatic reboot"
            echo "  --help             Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Setup logging
if [[ -n "$LOG_FILE" ]]; then
    exec > >(tee -a "$LOG_FILE") 2>&1
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}    System Update Started: $(date)${NC}"
echo -e "${GREEN}========================================${NC}"

# Check for root privileges (optional, only warn)
if [[ $EUID -ne 0 ]]; then
    echo -e "${YELLOW}Warning: Not running as root. Sudo will be used when needed.${NC}"
fi

# Check internet connectivity
echo -e "\n${YELLOW}Checking internet connectivity...${NC}"
if ! ping -c 1 -W 2 8.8.8.8 > /dev/null 2>&1; then
    echo -e "${RED}ERROR: No internet connection. Aborting.${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Internet connection OK${NC}"

# Update package lists
echo -e "\n${YELLOW}Step 1/3: Updating package lists...${NC}"
if sudo apt update; then
    echo -e "${GREEN}✓ Package lists updated successfully${NC}"
else
    echo -e "${RED}✗ Failed to update package lists${NC}"
    exit 1
fi

# Check if upgrades are available
echo -e "\n${YELLOW}Step 2/3: Checking for available upgrades...${NC}"
UPGRADE_COUNT=$(apt list --upgradable 2>/dev/null | grep -c upgradable || echo "0")
if [[ "$UPGRADE_COUNT" -eq 0 ]]; then
    echo -e "${GREEN}✓ No upgrades available. System is up to date.${NC}"
    echo -e "\n${YELLOW}Skipping upgrade step...${NC}"
else
    echo -e "${GREEN}Found $UPGRADE_COUNT packages to upgrade${NC}"
    
    echo -e "\n${YELLOW}Step 3/3: Performing full upgrade...${NC}"
    if sudo apt full-upgrade -y; then
        echo -e "${GREEN}✓ Upgrade completed successfully${NC}"
        
        # Clean up
        echo -e "\n${YELLOW}Cleaning up...${NC}"
        sudo apt autoremove -y
        sudo apt autoclean
        echo -e "${GREEN}✓ Cleanup completed${NC}"
    else
        echo -e "${RED}✗ Upgrade failed${NC}"
        exit 1
    fi
fi

# Summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}    System Update Completed: $(date)${NC}"
echo -e "${GREEN}========================================${NC}"

# Reboot if requested
if [[ "$REBOOT" == true ]]; then
    echo -e "\n${YELLOW}System will reboot in 10 seconds...${NC}"
    echo -e "${YELLOW}Press Ctrl+C to cancel${NC}"
    sleep 10
    echo -e "${GREEN}Rebooting now...${NC}"
    sudo reboot
else
    echo -e "\n${YELLOW}Reboot skipped as requested.${NC}"
    echo -e "${YELLOW}Please reboot manually to apply all updates.${NC}"
fi

exit 0