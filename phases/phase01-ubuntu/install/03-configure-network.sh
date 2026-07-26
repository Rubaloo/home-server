#!/bin/bash
# Phase 01 - Step 03
# Configure server as static IP

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root or with sudo${NC}"
    exit 1
fi

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}    NetPlan Static IP Configuration${NC}"
echo -e "${BLUE}==================================================${NC}"

# Detect network interfaces
echo -e "\n${YELLOW}Detecting network interfaces...${NC}"

# Get all physical network interfaces (excluding loopback and virtual)
INTERFACES=$(ls /sys/class/net/ | grep -v lo | grep -v docker | grep -v veth | grep -v br-)
if [ -z "$INTERFACES" ]; then
    echo -e "${RED}No physical network interfaces found!${NC}"
    exit 1
fi

echo -e "${GREEN}Detected interfaces:${NC}"
i=1
declare -a IFACE_ARRAY
for iface in $INTERFACES; do
    # Check if interface has an IP
    IP_ADDR=$(ip -4 addr show $iface 2>/dev/null | grep inet | awk '{print $2}' | cut -d/ -f1 | head -n1)
    if [ -n "$IP_ADDR" ]; then
        echo -e "  ${GREEN}$i)${NC} $iface (IP: $IP_ADDR)"
    else
        echo -e "  ${YELLOW}$i)${NC} $iface (No IP)"
    fi
    IFACE_ARRAY[$i]=$iface
    ((i++))
done

# Let user select interface or auto-detect
echo -e "\n${YELLOW}Select network interface to configure:${NC}"
read -p "Enter number (1-${#IFACE_ARRAY[@]}) or press Enter for auto-detect: " SELECTION

if [ -z "$SELECTION" ]; then
    # Auto-detect: try to find interface with default route
    INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
    if [ -z "$INTERFACE" ]; then
        # If no default route, use first physical interface
        INTERFACE=$(echo "$INTERFACES" | head -n1)
    fi
    echo -e "${GREEN}Auto-selected:${NC} $INTERFACE"
else
    if [[ $SELECTION =~ ^[0-9]+$ ]] && [ $SELECTION -ge 1 ] && [ $SELECTION -le ${#IFACE_ARRAY[@]} ]; then
        INTERFACE=${IFACE_ARRAY[$SELECTION]}
        echo -e "${GREEN}Selected:${NC} $INTERFACE"
    else
        echo -e "${RED}Invalid selection! Using first interface:${NC} ${IFACE_ARRAY[1]}"
        INTERFACE=${IFACE_ARRAY[1]}
    fi
fi

# Get current IP info
CURRENT_IP=$(ip -4 addr show $INTERFACE 2>/dev/null | grep inet | awk '{print $2}' | cut -d/ -f1 | head -n1)
CURRENT_GATEWAY=$(ip route | grep default | grep $INTERFACE | awk '{print $3}' | head -n1)
CURRENT_NETMASK=$(ip -4 addr show $INTERFACE 2>/dev/null | grep inet | awk '{print $2}' | cut -d/ -f2 | head -n1)

echo -e "\n${BLUE}Current network configuration:${NC}"
echo -e "  Interface: ${GREEN}$INTERFACE${NC}"
echo -e "  IP: ${GREEN}${CURRENT_IP:-Not set}${NC}"
echo -e "  Gateway: ${GREEN}${CURRENT_GATEWAY:-Not set}${NC}"

# Ask for static IP configuration
echo -e "\n${YELLOW}Enter static IP configuration:${NC}"
read -p "IP Address (e.g., 192.168.1.50): " STATIC_IP
STATIC_IP=${STATIC_IP:-192.168.1.50}

read -p "Netmask (e.g., 24): " NETMASK
NETMASK=${NETMASK:-24}

read -p "Gateway (e.g., 192.168.1.1): " GATEWAY
GATEWAY=${GATEWAY:-192.168.1.1}

read -p "DNS servers (space-separated, e.g., 8.8.8.8 8.8.4.4): " DNS_SERVERS
if [ -z "$DNS_SERVERS" ]; then
    DNS_SERVERS="8.8.8.8 8.8.4.4 1.1.1.1"
fi

# Create DNS array for YAML
DNS_ARRAY=""
for dns in $DNS_SERVERS; do
    DNS_ARRAY="$DNS_ARRAY\n          - $dns"
done

# Create netplan configuration
NETPLAN_FILE="/etc/netplan/01-netcfg.yaml"
BACKUP_FILE="/etc/netplan/01-netcfg.yaml.backup.$(date +%Y%m%d_%H%M%S)"

# Backup existing config
if [ -f "$NETPLAN_FILE" ]; then
    echo -e "\n${YELLOW}Backing up existing netplan configuration...${NC}"
    cp "$NETPLAN_FILE" "$BACKUP_FILE"
    echo -e "${GREEN}✓ Backup: $BACKUP_FILE${NC}"
fi

# Create the netplan configuration
echo -e "\n${YELLOW}Creating netplan configuration...${NC}"

cat > "$NETPLAN_FILE" << EOF
network:
  ethernets:
    $INTERFACE:
      dhcp4: false
      dhcp6: false
      addresses:
        - $STATIC_IP/$NETMASK
      routes:
        - to: default
          via: $GATEWAY
      nameservers:
        addresses:
$DNS_ARRAY
        search: []
  version: 2
EOF

echo -e "${GREEN}✓ Created: $NETPLAN_FILE${NC}"

# Set correct permissions
chmod 600 "$NETPLAN_FILE"
echo -e "${GREEN}✓ Permissions set to 600${NC}"

# Test the configuration
echo -e "\n${YELLOW}Testing netplan configuration...${NC}"
if netplan try --timeout 5; then
    echo -e "${GREEN}✓ Configuration validated successfully${NC}"
else
    echo -e "${RED}✗ Configuration test failed! Restoring backup...${NC}"
    if [ -f "$BACKUP_FILE" ]; then
        cp "$BACKUP_FILE" "$NETPLAN_FILE"
        echo -e "${YELLOW}Backup restored.${NC}"
    fi
    exit 1
fi

# Apply the configuration
echo -e "\n${YELLOW}Applying netplan configuration...${NC}"
netplan apply

echo -e "${GREEN}✓ Configuration applied successfully${NC}"

# Verify the new configuration
echo -e "\n${YELLOW}Verifying network configuration...${NC}"
sleep 2  # Wait for network to stabilize

NEW_IP=$(ip -4 addr show $INTERFACE 2>/dev/null | grep inet | awk '{print $2}' | cut -d/ -f1 | head -n1)
NEW_GATEWAY=$(ip route | grep default | awk '{print $3}' | head -n1)

echo -e "\n${BLUE}New network configuration:${NC}"
echo -e "  Interface: ${GREEN}$INTERFACE${NC}"
echo -e "  IP: ${GREEN}${NEW_IP}${NC}"
echo -e "  Gateway: ${GREEN}${NEW_GATEWAY}${NC}"

# Test connectivity
echo -e "\n${YELLOW}Testing connectivity...${NC}"
if ping -c 2 -W 2 $GATEWAY >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Gateway reachable${NC}"
else
    echo -e "${RED}✗ Gateway not reachable! Check your configuration.${NC}"
fi

if ping -c 2 -W 2 8.8.8.8 >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Internet connectivity detected${NC}"
else
    echo -e "${YELLOW}⚠ No internet connectivity. Check DNS or gateway settings.${NC}"
fi

echo -e "\n${BLUE}==================================================${NC}"
echo -e "${GREEN}✓ Netplan configuration complete!${NC}"
echo -e "${BLUE}==================================================${NC}"

echo -e "\n${YELLOW}Configuration details:${NC}"
echo -e "  File: ${BLUE}$NETPLAN_FILE${NC}"
echo -e "  Interface: ${GREEN}$INTERFACE${NC}"
echo -e "  IP: ${GREEN}$STATIC_IP/$NETMASK${NC}"
echo -e "  Gateway: ${GREEN}$GATEWAY${NC}"
echo -e "  DNS: ${GREEN}$DNS_SERVERS${NC}"
echo -e "  Backup: ${BLUE}$BACKUP_FILE${NC}"

echo -e "\n${YELLOW}To revert changes:${NC}"
echo -e "  sudo cp $BACKUP_FILE $NETPLAN_FILE"
echo -e "  sudo netplan apply"

echo -e "\n${GREEN}Done!${NC}"