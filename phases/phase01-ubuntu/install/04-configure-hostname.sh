#!/bin/bash
# Phase 01 - Step 04
# set hostname as homeserver and configure /etc/hosts
HOSTNAME_VALUE="${HOSTNAME_VALUE:-homeserver}"
sudo hostnamectl set-hostname "$HOSTNAME_VALUE"

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

HOSTS_FILE="/etc/hosts"
BACKUP_FILE="/etc/hosts.backup.$(date +%Y%m%d_%H%M%S)"

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}    Advanced /etc/hosts Configuration${NC}"
echo -e "${BLUE}==================================================${NC}"

# Interactive confirmation
read -p "This will modify /etc/hosts. Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Operation cancelled.${NC}"
    exit 0
fi

# Create backup
echo -e "${YELLOW}Creating backup...${NC}"
cp "$HOSTS_FILE" "$BACKUP_FILE"
echo -e "${GREEN}✓ Backup: $BACKUP_FILE${NC}"

# Function to clean up duplicate entries only
cleanup_hosts() {
    echo -e "\n${YELLOW}Cleaning up duplicate entries...${NC}"
    
    # Remove duplicate 127.0.0.1 entries (keep only first)
    sed -i '/^127\.0\.0\.1/!b;n;/^127\.0\.0\.1/d' "$HOSTS_FILE"
    
    echo -e "${GREEN}✓ Cleanup complete${NC}"
}

# Function to add/update standard entries
add_standard_entries() {
    echo -e "\n${YELLOW}Checking standard entries...${NC}"
    
    # Ensure 127.0.0.1 localhost exists
    if ! grep -q "^127\.0\.0\.1[[:space:]]localhost" "$HOSTS_FILE"; then
        echo "127.0.0.1 localhost" >> "$HOSTS_FILE"
        echo -e "${GREEN}✓ Added: 127.0.0.1 localhost${NC}"
    else
        echo -e "${GREEN}✓ 127.0.0.1 localhost already exists${NC}"
    fi
    
    # Check if 127.0.1.1 entry exists
    if grep -q "^127\.0\.1\.1" "$HOSTS_FILE"; then
        # Check if it already has the correct hostname
        if grep -q "^127\.0\.1\.1[[:space:]]$HOSTNAME_VALUE" "$HOSTS_FILE"; then
            echo -e "${GREEN}✓ 127.0.1.1 $HOSTNAME_VALUE already exists correctly${NC}"
        else
            # It exists but with a different name - replace it
            echo -e "${YELLOW}Found 127.0.1.1 entry with different hostname. Replacing with $HOSTNAME_VALUE...${NC}"
            sed -i "s/^127\.0\.1\.1[[:space:]].*/127.0.1.1 $HOSTNAME_VALUE/" "$HOSTS_FILE"
            echo -e "${GREEN}✓ Replaced with: 127.0.1.1 $HOSTNAME_VALUE${NC}"
        fi
    else
        # No 127.0.1.1 entry exists at all - add it
        echo "127.0.1.1 $HOSTNAME_VALUE" >> "$HOSTS_FILE"
        echo -e "${GREEN}✓ Added: 127.0.1.1 $HOSTNAME_VALUE${NC}"
    fi
}

# Function to ensure IPv6 entries
add_ipv6_entries() {
    echo -e "\n${YELLOW}Checking IPv6 entries...${NC}"
    
    # Check if IPv6 section exists
    if ! grep -q "^::1.*ip6-localhost" "$HOSTS_FILE"; then
        echo "" >> "$HOSTS_FILE"
        echo "# The following lines are desirable for IPv6 capable hosts" >> "$HOSTS_FILE"
        echo "::1     ip6-localhost ip6-loopback" >> "$HOSTS_FILE"
        echo "fe00::0 ip6-localnet" >> "$HOSTS_FILE"
        echo "ff00::0 ip6-mcastprefix" >> "$HOSTS_FILE"
        echo "ff02::1 ip6-allnodes" >> "$HOSTS_FILE"
        echo "ff02::2 ip6-allrouters" >> "$HOSTS_FILE"
        echo -e "${GREEN}✓ Added IPv6 entries${NC}"
    else
        echo -e "${GREEN}✓ IPv6 entries already exist${NC}"
    fi
}

# Function to add custom entries
add_custom_entries() {
    echo -e "\n${YELLOW}Do you want to add custom host entries?${NC}"
    read -p "Add custom entries? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}Enter custom entries (one per line, empty line to finish):${NC}"
        echo -e "${BLUE}Example: 192.168.1.100 myserver.local${NC}"
        
        while true; do
            read -p "> " CUSTOM_ENTRY
            if [ -z "$CUSTOM_ENTRY" ]; then
                break
            fi
            echo "$CUSTOM_ENTRY" >> "$HOSTS_FILE"
            echo -e "${GREEN}✓ Added: $CUSTOM_ENTRY${NC}"
        done
    fi
}

# Main execution
cleanup_hosts
add_standard_entries
add_ipv6_entries

# Ask about custom entries
add_custom_entries

# Show the result
echo -e "\n${BLUE}Final /etc/hosts content:${NC}"
echo -e "${BLUE}==================================================${NC}"
cat "$HOSTS_FILE"
echo -e "${BLUE}==================================================${NC}"

# Test network resolution
echo -e "\n${YELLOW}Testing hostname resolution...${NC}"
if ping -c 1 -W 1 "$HOSTNAME_VALUE" &>/dev/null; then
    echo -e "${GREEN}✓ $HOSTNAME_VALUE resolves correctly${NC}"
else
    echo -e "${RED}✗ $HOSTNAME_VALUE does not resolve. Check your configuration.${NC}"
fi

echo -e "\n${GREEN}✓ /etc/hosts updated successfully!${NC}"
echo -e "${YELLOW}Backup:${NC} $BACKUP_FILE"
echo -e "${YELLOW}Restore:${NC} sudo cp $BACKUP_FILE $HOSTS_FILE"

echo -e "\n${GREEN}Done!${NC}"