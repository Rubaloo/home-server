#!/bin/bash
# Phase 01 - Step 08
sudo systemctl enable ssh
sudo systemctl start ssh

# Advanced SSH configuration script with interactive mode

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root or with sudo${NC}"
    exit 1
fi

SSHD_CONFIG="/etc/ssh/sshd_config"
BACKUP_FILE="/etc/ssh/sshd_config.backup.$(date +%Y%m%d_%H%M%S)"

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}    SSH Secure Configuration Script${NC}"
echo -e "${BLUE}==================================================${NC}"

# Interactive confirmation
read -p "This will modify SSH configuration. Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Operation cancelled.${NC}"
    exit 0
fi

# Create backup
echo -e "${YELLOW}Creating backup...${NC}"
cp "$SSHD_CONFIG" "$BACKUP_FILE"
echo -e "${GREEN}✓ Backup: $BACKUP_FILE${NC}"

# Function to configure SSH
configure_ssh() {
    local param="$1"
    local value="$2"
    
    if grep -q "^#*[[:space:]]*$param" "$SSHD_CONFIG"; then
        sed -i "s/^#*[[:space:]]*$param.*/$param $value/" "$SSHD_CONFIG"
        echo -e "${GREEN}✓${NC} $param = $value"
    else
        echo "$param $value" >> "$SSHD_CONFIG"
        echo -e "${GREEN}✓${NC} $param = $value (added)"
    fi
}

echo -e "\n${BLUE}Applying configuration...${NC}"

# Core security settings
configure_ssh "PermitRootLogin" "no"
configure_ssh "PasswordAuthentication" "no"
configure_ssh "PubkeyAuthentication" "yes"
configure_ssh "PermitEmptyPasswords" "no"
configure_ssh "MaxAuthTries" "3"
configure_ssh "X11Forwarding" "no"

# Optional: Ask about port change
echo -e "\n${YELLOW}Do you want to change the SSH port? (recommended)${NC}"
read -p "Change port? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    read -p "Enter new SSH port (22-65535, default 2222): " NEW_PORT
    NEW_PORT=${NEW_PORT:-2222}
    if [[ $NEW_PORT =~ ^[0-9]+$ ]] && [ $NEW_PORT -ge 22 ] && [ $NEW_PORT -le 65535 ]; then
        configure_ssh "Port" "$NEW_PORT"
        echo -e "${YELLOW}Remember to update firewall rules for port $NEW_PORT${NC}"
    else
        echo -e "${RED}Invalid port number. Skipping...${NC}"
    fi
fi

# Optional: Ask about allowed users
echo -e "\n${YELLOW}Do you want to restrict SSH to specific users?${NC}"
read -p "Restrict to specific users? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    read -p "Enter usernames (space-separated): " USERS
    if [ -n "$USERS" ]; then
        configure_ssh "AllowUsers" "$USERS"
    fi
fi

# Test configuration
echo -e "\n${YELLOW}Testing SSH configuration...${NC}"
if sshd -t; then
    echo -e "${GREEN}✓ Configuration valid${NC}"
else
    echo -e "${RED}✗ Invalid configuration! Restoring backup...${NC}"
    cp "$BACKUP_FILE" "$SSHD_CONFIG"
    echo -e "${YELLOW}Backup restored.${NC}"
    exit 1
fi

# Restart SSH
echo -e "\n${YELLOW}Restarting SSH service...${NC}"
systemctl restart ssh

if systemctl is-active --quiet ssh; then
    echo -e "${GREEN}✓ SSH restarted successfully${NC}"
else
    echo -e "${RED}✗ Failed to restart SSH! Restoring backup...${NC}"
    cp "$BACKUP_FILE" "$SSHD_CONFIG"
    systemctl restart ssh
    echo -e "${YELLOW}Backup restored.${NC}"
    exit 1
fi

# Summary
echo -e "\n${BLUE}==================================================${NC}"
echo -e "${GREEN}✓ SSH configuration completed!${NC}"
echo -e "${BLUE}==================================================${NC}"

# Show what was changed
echo -e "\n${YELLOW}Changes applied:${NC}"
grep -E "^(PermitRootLogin|PasswordAuthentication|PubkeyAuthentication|PermitEmptyPasswords|MaxAuthTries|X11Forwarding|Port|AllowUsers)" "$SSHD_CONFIG" | while read line; do
    echo -e "${GREEN}  $line${NC}"
done

echo -e "\n${RED}⚠️  WARNING:${NC}"
echo -e "Make sure you have SSH keys set up before closing this session!"
echo -e "Test your SSH connection in a new terminal:"
echo -e "  ${BLUE}ssh -v user@$(hostname -I | awk '{print $1}')${NC}"
echo -e "\nBackup: ${BLUE}$BACKUP_FILE${NC}"
echo -e "Revert: ${BLUE}sudo cp $BACKUP_FILE $SSHD_CONFIG && sudo systemctl restart ssh${NC}"

echo -e "\n${GREEN}Done!${NC}"