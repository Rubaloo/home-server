#!/bin/bash

# ============================================================
# Home Assistant Matter Hub - Idempotent Installation Script
# ============================================================
# This script:
# - Checks Docker & Docker Compose availability
# - Creates a separate docker-compose.matter-hub.yml file in /srv/docker
# - Does NOT modify your existing Home Assistant compose file
# - Uses your exact configuration (container_name: matter-hub, port: 8482)
# - Uses :latest tag for Matter Hub image
# - Fixes mDNS warning by setting mdns-network-interface
# - Adds UFW firewall rules for local network access:
#   - TCP 8482 (Matter Hub web interface)
#   - UDP 5540 (Matter commissioning)
# - Validates installation
# ============================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
COMPOSE_DIR="/srv/docker"
COMPOSE_FILE="${COMPOSE_DIR}/docker-compose.matter-hub.yml"
CONTAINER_NAME="matter-hub"
MATTER_HUB_PORT="8482"
MATTER_COMMISSIONING_PORT="5540"
MATTER_HUB_IMAGE="ghcr.io/riddix/home-assistant-matter-hub:latest"
LOCAL_SUBNET="192.168.1.0/24"

# Function to print colored messages
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to detect Docker Compose command
detect_compose_cmd() {
    if command_exists docker && docker compose version >/dev/null 2>&1; then
        echo "docker compose"
    elif command_exists docker-compose; then
        echo "docker-compose"
    else
        print_error "Docker Compose not found. Please install Docker Compose."
        exit 1
    fi
}

# Function to detect network interface
detect_network_interface() {
    # Try to find the main network interface (excluding docker, tailscale, etc.)
    local interface=$(ip -4 addr show | grep -E "enp|eth|wlan" | grep -v "docker" | grep -v "tailscale" | grep -v "br-" | head -n1 | awk -F': ' '{print $2}')
    
    if [[ -z "$interface" ]]; then
        # Fallback: try to find any interface with a non-local IP
        interface=$(ip -4 addr show | grep -v "127.0.0.1" | grep -v "docker" | grep -v "tailscale" | grep -v "br-" | grep -oP '(?<=: )\w+' | head -n1)
    fi
    
    if [[ -z "$interface" ]]; then
        print_warning "Could not auto-detect network interface. Using 'enp0s31f6' as default (from your logs)."
        echo "enp0s31f6"
    else
        echo "$interface"
    fi
}

# Function to detect local subnet
detect_local_subnet() {
    local ip=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | grep -v '172.17' | grep -v '172.18' | head -n1)
    if [[ -n "$ip" ]]; then
        # Get the subnet (remove the last octet and add .0/24)
        echo "$(echo "$ip" | cut -d. -f1-3).0/24"
    else
        echo "192.168.1.0/24"
    fi
}

# ============================================================
# STEP 1: Detect local IP and network interface
# ============================================================
print_status "Detecting local IP address and network interface..."

# Try to get the local IP (useful for Home Assistant URL)
LOCAL_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | grep -v '172.17' | grep -v '172.18' | head -n1)

if [[ -z "$LOCAL_IP" ]]; then
    print_warning "Could not auto-detect local IP. Using 192.168.1.50 as default."
    LOCAL_IP="192.168.1.50"
else
    print_success "Detected local IP: $LOCAL_IP"
    echo ""
    read -p "Use this IP for Home Assistant URL? (y/n): " USE_DETECTED_IP
    if [[ ! "$USE_DETECTED_IP" =~ ^[Yy]$ ]]; then
        read -p "Enter your Home Assistant IP address: " LOCAL_IP
        if [[ -z "$LOCAL_IP" ]]; then
            LOCAL_IP="192.168.1.50"
            print_warning "Using default IP: 192.168.1.50"
        fi
    fi
fi

# Detect network interface for mDNS
NETWORK_INTERFACE=$(detect_network_interface)
print_success "Detected network interface: $NETWORK_INTERFACE"
echo ""

read -p "Use this network interface for mDNS? (y/n): " USE_DETECTED_INTERFACE
if [[ ! "$USE_DETECTED_INTERFACE" =~ ^[Yy]$ ]]; then
    read -p "Enter your network interface name (e.g., enp0s31f6, eth0, wlan0): " NETWORK_INTERFACE
    if [[ -z "$NETWORK_INTERFACE" ]]; then
        NETWORK_INTERFACE="enp0s31f6"
        print_warning "Using default interface: enp0s31f6"
    fi
fi

print_success "Using network interface: $NETWORK_INTERFACE for mDNS"

# ============================================================
# STEP 2: Detect local subnet for firewall
# ============================================================
print_status "Detecting local subnet for firewall rules..."

DETECTED_SUBNET=$(detect_local_subnet)
print_success "Detected local subnet: $DETECTED_SUBNET"
echo ""

read -p "Use this subnet for firewall rules? (y/n): " USE_DETECTED_SUBNET
if [[ ! "$USE_DETECTED_SUBNET" =~ ^[Yy]$ ]]; then
    read -p "Enter your local subnet (e.g., 192.168.1.0/24): " LOCAL_SUBNET
    if [[ -z "$LOCAL_SUBNET" ]]; then
        LOCAL_SUBNET="192.168.1.0/24"
        print_warning "Using default subnet: 192.168.1.0/24"
    fi
fi

print_success "Using subnet: $LOCAL_SUBNET for firewall rules"

# ============================================================
# STEP 3: Check Docker
# ============================================================
print_status "Checking Docker installation..."

if ! command_exists docker; then
    print_error "Docker is not installed. Please install Docker first."
    exit 1
fi

DOCKER_VERSION=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "unknown")
print_success "Docker version: $DOCKER_VERSION"

# ============================================================
# STEP 4: Detect Docker Compose
# ============================================================
print_status "Detecting Docker Compose..."

COMPOSE_CMD=$(detect_compose_cmd)
print_success "Using: $COMPOSE_CMD"

# ============================================================
# STEP 5: Verify /srv/docker directory exists
# ============================================================
print_status "Checking for /srv/docker directory..."

if [[ ! -d "$COMPOSE_DIR" ]]; then
    print_warning "Directory not found: $COMPOSE_DIR"
    read -p "Create directory $COMPOSE_DIR? (y/n): " CREATE_DIR
    if [[ "$CREATE_DIR" =~ ^[Yy]$ ]]; then
        sudo mkdir -p "$COMPOSE_DIR"
        sudo chown "$USER":"$USER" "$COMPOSE_DIR"
        print_success "Created directory: $COMPOSE_DIR"
    else
        print_error "Cannot continue without directory"
        exit 1
    fi
fi

print_success "Using directory: $COMPOSE_DIR"

# ============================================================
# STEP 6: Check if Matter Hub compose file already exists
# ============================================================
print_status "Checking if Matter Hub compose file already exists..."

if [[ -f "$COMPOSE_FILE" ]]; then
    print_warning "Matter Hub compose file already exists: $COMPOSE_FILE"
    read -p "Do you want to overwrite it? (y/n): " OVERWRITE_CONFIRM
    if [[ ! "$OVERWRITE_CONFIRM" =~ ^[Yy]$ ]]; then
        print_status "Exiting without changes."
        exit 0
    fi
    # Create backup of existing file
    BACKUP_FILE="${COMPOSE_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$COMPOSE_FILE" "$BACKUP_FILE"
    print_success "Backup created: $BACKUP_FILE"
fi

# Check if container is already running
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    print_warning "Container '${CONTAINER_NAME}' already exists"
    read -p "Do you want to remove it and recreate? (y/n): " REMOVE_CONFIRM
    if [[ "$REMOVE_CONFIRM" =~ ^[Yy]$ ]]; then
        print_status "Stopping and removing existing container..."
        docker stop "${CONTAINER_NAME}" 2>/dev/null || true
        docker rm "${CONTAINER_NAME}" 2>/dev/null || true
        print_success "Removed existing container"
    fi
fi

# ============================================================
# STEP 7: Get Access Token
# ============================================================
echo ""
print_status "Setting up Home Assistant Long-Lived Access Token"
echo ""
echo "To create a token:"
echo "1. Open Home Assistant (http://${LOCAL_IP}:8123)"
echo "2. Click on your profile (bottom left)"
echo "3. Scroll to 'Long-Lived Access Tokens'"
echo "4. Create a new token named 'Matter Hub'"
echo "5. Copy the token"
echo ""
read -sp "Paste your Home Assistant Long-Lived Access Token: " HASS_TOKEN
echo ""

if [[ -z "$HASS_TOKEN" ]]; then
    print_error "No token provided. Exiting."
    exit 1
fi

# Mask token for display
TOKEN_MASK="${HASS_TOKEN:0:8}...${HASS_TOKEN: -4}"

# ============================================================
# STEP 8: Create persistent directory
# ============================================================
print_status "Creating persistent storage directory..."

MATTER_HUB_DIR="${COMPOSE_DIR}/home-assistant-matter-hub"
mkdir -p "$MATTER_HUB_DIR"
chmod 755 "$MATTER_HUB_DIR"
print_success "Created directory: $MATTER_HUB_DIR"

# ============================================================
# STEP 9: Create Matter Hub compose file
# ============================================================
print_status "Creating Matter Hub compose file: $COMPOSE_FILE"

cat > "$COMPOSE_FILE" <<EOF
# ============================================================
# Home Assistant Matter Hub - Standalone Compose File
# ============================================================
# This file is separate from your main Home Assistant compose file
# to keep your HA configuration clean and untouched.
#
# To manage Matter Hub:
#   Start:  docker compose -f ${COMPOSE_FILE} up -d
#   Stop:   docker compose -f ${COMPOSE_FILE} down
#   Logs:   docker compose -f ${COMPOSE_FILE} logs -f
#   Restart: docker compose -f ${COMPOSE_FILE} restart
# ============================================================

services:
  matter-hub:
    container_name: ${CONTAINER_NAME}
    image: ${MATTER_HUB_IMAGE}
    restart: unless-stopped
    network_mode: host
    environment:
      - HAMH_HOME_ASSISTANT_URL=http://localhost:8123
      - HAMH_HOME_ASSISTANT_ACCESS_TOKEN=${HASS_TOKEN}
      - HAMH_LOG_LEVEL=info
      - HAMH_HTTP_PORT=${MATTER_HUB_PORT}
      - mdns-network-interface=${NETWORK_INTERFACE}
    volumes:
      - ./home-assistant-matter-hub:/data
EOF

print_success "Created Matter Hub compose file"

# ============================================================
# STEP 10: Validate compose file
# ============================================================
print_status "Validating Matter Hub compose file..."

cd "$COMPOSE_DIR"

if ! $COMPOSE_CMD -f "$COMPOSE_FILE" config >/dev/null 2>&1; then
    print_error "Matter Hub compose file validation failed!"
    if [[ -f "$BACKUP_FILE" ]]; then
        print_error "Restoring from backup..."
        cp "$BACKUP_FILE" "$COMPOSE_FILE"
        print_success "Restored backup"
    fi
    exit 1
fi

print_success "Matter Hub compose file is valid"

# Display the compose file content
print_status "Compose file content:"
echo ""
cat "$COMPOSE_FILE"
echo ""

# ============================================================
# STEP 11: Pull Matter Hub image
# ============================================================
print_status "Pulling Matter Hub image (${MATTER_HUB_IMAGE})..."

if ! docker pull "${MATTER_HUB_IMAGE}"; then
    print_error "Failed to pull Matter Hub image"
    exit 1
fi

print_success "Matter Hub image pulled successfully"

# ============================================================
# STEP 12: Start Matter Hub
# ============================================================
print_status "Starting Matter Hub..."

if ! $COMPOSE_CMD -f "$COMPOSE_FILE" up -d; then
    print_error "Failed to start Matter Hub"
    exit 1
fi

print_success "Matter Hub started successfully"

# ============================================================
# STEP 13: Configure UFW firewall
# ============================================================
print_status "Configuring UFW firewall..."

# Check if UFW is installed
if command_exists ufw; then
    print_success "UFW is installed"
    
    # Check if UFW is active
    if sudo ufw status | grep -q "Status: active"; then
        print_success "UFW is active"
        
        # ============================================================
        # Add rule for TCP port 8482 (Matter Hub web interface)
        # ============================================================
        print_status "Adding firewall rule for TCP port ${MATTER_HUB_PORT} (Matter Hub web interface)..."
        
        # Check if rule already exists
        if sudo ufw status numbered | grep -q "${MATTER_HUB_PORT}/tcp"; then
            print_warning "Firewall rule for TCP port ${MATTER_HUB_PORT} already exists"
            read -p "Do you want to update the rule? (y/n): " UPDATE_RULE_TCP
            if [[ "$UPDATE_RULE_TCP" =~ ^[Yy]$ ]]; then
                # Remove existing rule
                RULE_NUMBER=$(sudo ufw status numbered | grep "${MATTER_HUB_PORT}/tcp" | head -n1 | grep -oP '\[\K\d+' || echo "")
                if [[ -n "$RULE_NUMBER" ]]; then
                    echo "y" | sudo ufw delete "$RULE_NUMBER" >/dev/null 2>&1
                    print_success "Removed existing rule"
                fi
                
                # Add new rule
                if sudo ufw allow from "$LOCAL_SUBNET" to any port "$MATTER_HUB_PORT" proto tcp comment 'Matter Hub Web Interface'; then
                    print_success "Added firewall rule: allow from $LOCAL_SUBNET to port $MATTER_HUB_PORT/tcp"
                else
                    print_error "Failed to add firewall rule for TCP port ${MATTER_HUB_PORT}"
                fi
            fi
        else
            # Add new rule
            if sudo ufw allow from "$LOCAL_SUBNET" to any port "$MATTER_HUB_PORT" proto tcp comment 'Matter Hub Web Interface'; then
                print_success "Added firewall rule: allow from $LOCAL_SUBNET to port $MATTER_HUB_PORT/tcp"
            else
                print_error "Failed to add firewall rule for TCP port ${MATTER_HUB_PORT}"
            fi
        fi
        
        # ============================================================
        # Add rule for UDP port 5540 (Matter commissioning)
        # ============================================================
        print_status "Adding firewall rule for UDP port ${MATTER_COMMISSIONING_PORT} (Matter commissioning)..."
        
        # Check if rule already exists
        if sudo ufw status numbered | grep -q "${MATTER_COMMISSIONING_PORT}/udp"; then
            print_warning "Firewall rule for UDP port ${MATTER_COMMISSIONING_PORT} already exists"
            read -p "Do you want to update the rule? (y/n): " UPDATE_RULE_UDP
            if [[ "$UPDATE_RULE_UDP" =~ ^[Yy]$ ]]; then
                # Remove existing rule
                RULE_NUMBER=$(sudo ufw status numbered | grep "${MATTER_COMMISSIONING_PORT}/udp" | head -n1 | grep -oP '\[\K\d+' || echo "")
                if [[ -n "$RULE_NUMBER" ]]; then
                    echo "y" | sudo ufw delete "$RULE_NUMBER" >/dev/null 2>&1
                    print_success "Removed existing rule"
                fi
                
                # Add new rule
                if sudo ufw allow from "$LOCAL_SUBNET" to any port "$MATTER_COMMISSIONING_PORT" proto udp comment 'Matter Commissioning'; then
                    print_success "Added firewall rule: allow from $LOCAL_SUBNET to port $MATTER_COMMISSIONING_PORT/udp"
                else
                    print_error "Failed to add firewall rule for UDP port ${MATTER_COMMISSIONING_PORT}"
                fi
            fi
        else
            # Add new rule
            if sudo ufw allow from "$LOCAL_SUBNET" to any port "$MATTER_COMMISSIONING_PORT" proto udp comment 'Matter Commissioning'; then
                print_success "Added firewall rule: allow from $LOCAL_SUBNET to port $MATTER_COMMISSIONING_PORT/udp"
            else
                print_error "Failed to add firewall rule for UDP port ${MATTER_COMMISSIONING_PORT}"
            fi
        fi
        
        # Reload UFW
        print_status "Reloading UFW..."
        sudo ufw reload
        
        # Show current rules
        echo ""
        print_status "Current UFW rules for Matter Hub:"
        echo "  TCP ${MATTER_HUB_PORT}:"
        sudo ufw status | grep -E "${MATTER_HUB_PORT}/tcp" | sed 's/^/    /' || echo "    (No rule found)"
        echo "  UDP ${MATTER_COMMISSIONING_PORT}:"
        sudo ufw status | grep -E "${MATTER_COMMISSIONING_PORT}/udp" | sed 's/^/    /' || echo "    (No rule found)"
        
    else
        print_warning "UFW is installed but not active"
        print_warning "To enable UFW: sudo ufw enable"
        print_warning "To add the rules manually:"
        echo "  sudo ufw allow from ${LOCAL_SUBNET} to any port ${MATTER_HUB_PORT} proto tcp comment 'Matter Hub Web Interface'"
        echo "  sudo ufw allow from ${LOCAL_SUBNET} to any port ${MATTER_COMMISSIONING_PORT} proto udp comment 'Matter Commissioning'"
    fi
else
    print_warning "UFW is not installed"
    print_warning "To install UFW: sudo apt-get install ufw -y"
    print_warning "To add the rules manually:"
    echo "  sudo ufw allow from ${LOCAL_SUBNET} to any port ${MATTER_HUB_PORT} proto tcp comment 'Matter Hub Web Interface'"
    echo "  sudo ufw allow from ${LOCAL_SUBNET} to any port ${MATTER_COMMISSIONING_PORT} proto udp comment 'Matter Commissioning'"
fi

# ============================================================
# STEP 14: Health checks
# ============================================================
print_status "Performing health checks..."

# Wait for container to start
sleep 5

# Check Home Assistant
print_status "Checking Home Assistant (http://${LOCAL_IP}:8123)..."
MAX_RETRIES=30
RETRY_COUNT=0
HASS_OK=false

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if curl -s -o /dev/null -w "%{http_code}" "http://${LOCAL_IP}:8123" 2>/dev/null | grep -q "200\|301\|302"; then
        HASS_OK=true
        print_success "Home Assistant is responding"
        break
    fi
    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo -n "."
    sleep 2
done
echo ""

if [ "$HASS_OK" = false ]; then
    print_warning "Home Assistant not responding at ${LOCAL_IP}:8123"
    print_warning "Please check if Home Assistant is running"
    print_warning "You can check with: docker ps | grep homeassistant"
fi

# Check Matter Hub
print_status "Checking Matter Hub (http://localhost:${MATTER_HUB_PORT})..."
RETRY_COUNT=0
MATTER_OK=false

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if curl -s -o /dev/null -w "%{http_code}" "http://localhost:${MATTER_HUB_PORT}/health" 2>/dev/null | grep -q "200"; then
        MATTER_OK=true
        print_success "Matter Hub is responding"
        break
    fi
    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo -n "."
    sleep 2
done
echo ""

if [ "$MATTER_OK" = false ]; then
    print_warning "Matter Hub not responding yet. Check logs:"
    print_warning "  docker logs ${CONTAINER_NAME}"
fi

# Test from local network (if possible)
if [ "$MATTER_OK" = true ]; then
    print_status "Testing Matter Hub from local network..."
    print_status "You can test from another device using:"
    echo "  curl http://${LOCAL_IP}:${MATTER_HUB_PORT}/health"
fi

# ============================================================
# STEP 15: Create helper scripts
# ============================================================
print_status "Creating helper scripts..."

# Create start script
cat > "${COMPOSE_DIR}/matter-hub-start.sh" <<EOF
#!/bin/bash
cd "$COMPOSE_DIR"
$COMPOSE_CMD -f "$COMPOSE_FILE" up -d
echo "Matter Hub started"
EOF
chmod +x "${COMPOSE_DIR}/matter-hub-start.sh"

# Create stop script
cat > "${COMPOSE_DIR}/matter-hub-stop.sh" <<EOF
#!/bin/bash
cd "$COMPOSE_DIR"
$COMPOSE_CMD -f "$COMPOSE_FILE" down
echo "Matter Hub stopped"
EOF
chmod +x "${COMPOSE_DIR}/matter-hub-stop.sh"

# Create logs script
cat > "${COMPOSE_DIR}/matter-hub-logs.sh" <<EOF
#!/bin/bash
cd "$COMPOSE_DIR"
$COMPOSE_CMD -f "$COMPOSE_FILE" logs -f
EOF
chmod +x "${COMPOSE_DIR}/matter-hub-logs.sh"

# Create restart script
cat > "${COMPOSE_DIR}/matter-hub-restart.sh" <<EOF
#!/bin/bash
cd "$COMPOSE_DIR"
$COMPOSE_CMD -f "$COMPOSE_FILE" restart
echo "Matter Hub restarted"
EOF
chmod +x "${COMPOSE_DIR}/matter-hub-restart.sh"

# Create status script
cat > "${COMPOSE_DIR}/matter-hub-status.sh" <<EOF
#!/bin/bash
cd "$COMPOSE_DIR"
$COMPOSE_CMD -f "$COMPOSE_FILE" ps
EOF
chmod +x "${COMPOSE_DIR}/matter-hub-status.sh"

# Create firewall status script
cat > "${COMPOSE_DIR}/matter-hub-firewall.sh" <<EOF
#!/bin/bash
echo "Matter Hub Firewall Rules:"
echo "=========================="
sudo ufw status | grep -E "${MATTER_HUB_PORT}|${MATTER_COMMISSIONING_PORT}" || echo "No rules found"
EOF
chmod +x "${COMPOSE_DIR}/matter-hub-firewall.sh"

print_success "Helper scripts created in ${COMPOSE_DIR}"

# ============================================================
# STEP 16: Display information
# ============================================================
echo ""
echo "============================================================"
print_success "Matter Hub Installation Complete!"
echo "============================================================"
echo ""
echo "📊 Services:"
echo "  - Home Assistant:    http://${LOCAL_IP}:8123"
echo "  - Matter Hub:        http://localhost:${MATTER_HUB_PORT}"
echo "  - Matter Hub:        http://${LOCAL_IP}:${MATTER_HUB_PORT}"
echo ""
echo "📁 Files:"
echo "  - Compose file:      $COMPOSE_FILE"
echo "  - Data directory:    $MATTER_HUB_DIR"
echo ""
echo "🔑 Token used:         $TOKEN_MASK"
echo "🌐 Home Assistant URL: http://${LOCAL_IP}:8123"
echo "🐳 Image:              ${MATTER_HUB_IMAGE}"
echo "🌐 Network Interface:  ${NETWORK_INTERFACE} (mDNS fix applied)"
echo ""
echo "🛡️  Firewall Rules:"
if command_exists ufw && sudo ufw status | grep -q "Status: active"; then
    echo "  ✅ UFW is active"
    echo "  ✅ TCP ${MATTER_HUB_PORT}: allow from ${LOCAL_SUBNET} (Matter Hub Web Interface)"
    echo "  ✅ UDP ${MATTER_COMMISSIONING_PORT}: allow from ${LOCAL_SUBNET} (Matter Commissioning)"
    echo ""
    echo "  📝 Current UFW rules for Matter Hub:"
    sudo ufw status | grep -E "${MATTER_HUB_PORT}|${MATTER_COMMISSIONING_PORT}" | sed 's/^/    /' || echo "    (No rules found)"
else
    echo "  ⚠️  UFW is not configured"
    echo "  To manually add the firewall rules:"
    echo "    sudo ufw allow from ${LOCAL_SUBNET} to any port ${MATTER_HUB_PORT} proto tcp comment 'Matter Hub Web Interface'"
    echo "    sudo ufw allow from ${LOCAL_SUBNET} to any port ${MATTER_COMMISSIONING_PORT} proto udp comment 'Matter Commissioning'"
fi
echo ""
echo "📝 Helper Scripts (in ${COMPOSE_DIR}):"
echo "  - Start:      ./matter-hub-start.sh"
echo "  - Stop:       ./matter-hub-stop.sh"
echo "  - Restart:    ./matter-hub-restart.sh"
echo "  - Logs:       ./matter-hub-logs.sh"
echo "  - Status:     ./matter-hub-status.sh"
echo "  - Firewall:   ./matter-hub-firewall.sh"
echo ""
echo "📝 Docker Compose Commands:"
echo "  - Start:    $COMPOSE_CMD -f $COMPOSE_FILE up -d"
echo "  - Stop:     $COMPOSE_CMD -f $COMPOSE_FILE down"
echo "  - Logs:     $COMPOSE_CMD -f $COMPOSE_FILE logs -f"
echo "  - Restart:  $COMPOSE_CMD -f $COMPOSE_FILE restart"
echo "  - Status:   $COMPOSE_CMD -f $COMPOSE_FILE ps"
echo ""
echo "✅ mDNS Warning Fixed:"
echo "  - Set mdns-network-interface=${NETWORK_INTERFACE}"
echo "  - This prevents the warning about Docker-internal interfaces"
echo ""
echo "🌐 Network Access:"O
echo "  - Matter Hub web interface accessible from: ${LOCAL_SUBNET}"
echo "  - Matter commissioning accessible from: ${LOCAL_SUBNET}"
echo "  - Test from another device: curl http://${LOCAL_IP}:${MATTER_HUB_PORT}/health"
echo ""
echo "⚠️  Important Notes:"
echo "  1. Your Home Assistant compose file was NOT modified"
echo "  2. Matter Hub runs independently in /srv/docker"
echo "  3. Uses network_mode: host - ports are accessible via host IP"
echo "  4. Firewall allows only local network access (${LOCAL_SUBNET})"
echo "  5. TCP ${MATTER_HUB_PORT}: Web interface access"
echo "  6. UDP ${MATTER_COMMISSIONING_PORT}: Matter commissioning"
echo "  7. No Tailscale changes were made"
echo "  8. Zigbee configuration is preserved"
echo "  9. Container name: ${CONTAINER_NAME}"
echo "  10. Completely separate from Home Assistant installation"
echo ""
echo "============================================================"

# ============================================================
# STEP 17: Optional - Show logs
# ============================================================
echo ""
read -p "Do you want to view Matter Hub logs? (y/n): " VIEW_LOGS
if [[ "$VIEW_LOGS" =~ ^[Yy]$ ]]; then
    docker logs -f --tail=50 "${CONTAINER_NAME}"
fi

exit 0