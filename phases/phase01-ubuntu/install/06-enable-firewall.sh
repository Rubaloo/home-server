#!/bin/bash
# Phase 01 - Step 06

# Color output for better visibility
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Configuring UFW firewall for home server...${NC}"

# Reset to defaults (clears existing rules)
sudo ufw --force reset

# Set defaults
sudo ufw default deny incoming
sudo ufw default allow outgoing

# --- ESSENTIAL SERVICES ---
# SSH - Change port if you've moved it from 22!
sudo ufw allow 22/tcp comment 'SSH'

# --- ADD YOUR SERVICES BELOW ---
# Uncomment what you need:

# Web servers
# sudo ufw allow 80/tcp comment 'HTTP'
# sudo ufw allow 443/tcp comment 'HTTPS'

# Media servers
# sudo ufw allow 8096/tcp comment 'Jellyfin'
# sudo ufw allow 32400/tcp comment 'Plex'

# File sharing
# sudo ufw allow 445/tcp comment 'SMB'     # Samba
# sudo ufw allow 2049/tcp comment 'NFS'    # NFS

# Home automation
# sudo ufw allow 8123/tcp comment 'Home Assistant'

# Docker/Container services (if using bridge networks)
# sudo ufw allow 2375/tcp comment 'Docker API'  # ONLY if secure!

# --- RATE LIMITING ---
# Protect SSH from brute force
sudo ufw limit 22/tcp comment 'SSH rate-limited'

# --- LOGGING ---
sudo ufw logging on

# --- ENABLE FIREWALL ---
echo -e "${YELLOW}Enabling firewall...${NC}"
sudo ufw --force enable

# --- STATUS ---
echo -e "${GREEN}Firewall status:${NC}"
sudo ufw status verbose

# --- OPTIONAL: Show numbered rules for easy deletion ---
echo -e "\n${YELLOW}To delete a rule later: sudo ufw delete <number>${NC}"
sudo ufw status numbered

# --- OPTIONAL: Test SSH connectivity ---
echo -e "\n${GREEN}Testing SSH connection...${NC}"
if nc -zv localhost 22 2>&1 | grep -q succeeded; then
    echo -e "${GREEN}✓ SSH is accessible${NC}"
else
    echo -e "${RED}✗ SSH is NOT accessible - check your rules!${NC}"
fi