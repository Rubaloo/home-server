#!/bin/bash

# Home Assistant Zigbee Setup Script for Sonoff Dongle
# Assumes Home Assistant is installed in /srv/docker/homeassistant

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
HA_DIR="/srv/docker/homeassistant"
DOCKER_COMPOSE_FILE="$HA_DIR/docker-compose.yml"
BACKUP_DIR="$HA_DIR/backups"

# Function to print colored output
print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[i]${NC} $1"
}

print_header() {
    echo -e "\n${BLUE}════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}\n"
}

# Function to verify Home Assistant directory exists
verify_ha_directory() {
    print_header "Step 0: Verifying Home Assistant Installation"
    
    if [ ! -d "$HA_DIR" ]; then
        print_error "Home Assistant directory not found at $HA_DIR"
        print_info "Please specify the correct path or create the directory first."
        exit 1
    fi
    
    if [ ! -f "$DOCKER_COMPOSE_FILE" ]; then
        print_error "docker-compose.yml not found at $DOCKER_COMPOSE_FILE"
        print_info "Please ensure Home Assistant is properly installed with Docker Compose."
        exit 1
    fi
    
    print_status "Home Assistant directory and docker-compose.yml found"
}

# Function to detect Sonoff dongle
detect_sonoff_dongle() {
    print_header "Step 1-2: Detecting Sonoff Zigbee Dongle"
    
    print_info "Checking USB devices..."
    
    # Check if lsusb is available
    if ! command -v lsusb &> /dev/null; then
        print_warning "lsusb not found. Installing usbutils..."
        sudo apt-get update && sudo apt-get install -y usbutils
    fi
    
    # Look for Sonoff dongle
    SONOFF_USB=$(lsusb | grep -i "sonoff\|ITead\|Zigbee\|Silicon" || true)
    
    if [ -z "$SONOFF_USB" ]; then
        print_error "Sonoff Zigbee dongle not detected via lsusb"
        print_info "Please ensure:"
        echo "  1. The dongle is properly plugged in"
        echo "  2. You're using a USB extension cable (recommended)"
        echo "  3. The dongle's LED is on"
        print_info "Detected USB devices:"
        lsusb
        exit 1
    fi
    
    print_status "Sonoff dongle detected: $SONOFF_USB"
    
    # Check for serial device directory
    if [ ! -d "/dev/serial/by-id/" ]; then
        print_error "/dev/serial/by-id/ directory not found"
        print_info "The dongle might need drivers or might not be properly recognized."
        print_info "Try reconnecting the dongle and running this script again."
        exit 1
    fi
    
    print_info "Checking serial devices..."
    ls -l /dev/serial/by-id/
    
    # Find the Sonoff device - get the full device name (not the symlink target)
    DEVICE_NAME=$(ls /dev/serial/by-id/ | grep -i "sonoff\|ITead\|Zigbee" | head -1)
    
    if [ -z "$DEVICE_NAME" ]; then
        print_error "Could not find Sonoff device in /dev/serial/by-id/"
        print_info "Available serial devices:"
        ls /dev/serial/by-id/ 2>/dev/null || echo "No serial devices found"
        exit 1
    fi
    
    FULL_DEVICE_PATH="/dev/serial/by-id/$DEVICE_NAME"
    
    print_status "Serial device found: $DEVICE_NAME"
    print_status "Full device path: $FULL_DEVICE_PATH"
    
    # Verify the device is accessible
    if [ ! -e "$FULL_DEVICE_PATH" ]; then
        print_error "Device path $FULL_DEVICE_PATH does not exist"
        exit 1
    fi
    
    # Show where the symlink points to
    REAL_DEVICE=$(readlink -f "$FULL_DEVICE_PATH")
    print_info "Device maps to: $REAL_DEVICE"
    
    print_status "Device verified and accessible"
}

# Function to backup docker-compose.yml
backup_docker_compose() {
    print_info "Creating backup of docker-compose.yml..."
    
    mkdir -p "$BACKUP_DIR"
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    cp "$DOCKER_COMPOSE_FILE" "$BACKUP_DIR/docker-compose.yml.$TIMESTAMP"
    
    print_status "Backup created: $BACKUP_DIR/docker-compose.yml.$TIMESTAMP"
}

# Function to update docker-compose.yml
update_docker_compose() {
    print_header "Step 3: Configuring Docker for USB Passthrough"
    
    backup_docker_compose
    
    print_info "Checking current docker-compose.yml configuration..."
    
    # Check if devices section already exists
    if grep -q "devices:" "$DOCKER_COMPOSE_FILE"; then
        print_warning "Devices section already exists in docker-compose.yml"
        
        # Check if our device is already added
        if grep -q "$DEVICE_NAME" "$DOCKER_COMPOSE_FILE"; then
            print_info "Zigbee device appears to already be configured"
            return
        fi
    fi
    
    print_info "Updating docker-compose.yml with Zigbee device..."
    
    # Install PyYAML if needed
    if ! python3 -c "import yaml" 2>/dev/null; then
        print_warning "PyYAML not found. Installing..."
        pip3 install PyYAML
    fi
    
    # Create Python script to update the YAML file
    python3 <<EOF
import yaml
import sys

compose_file = "$DOCKER_COMPOSE_FILE"
device_path = "$FULL_DEVICE_PATH"

try:
    with open(compose_file, 'r') as f:
        config = yaml.safe_load(f)
    
    # Find the homeassistant service
    if 'services' in config:
        for service_name, service_config in config['services'].items():
            if 'homeassistant' in service_name.lower():
                if 'devices' not in service_config:
                    service_config['devices'] = []
                
                device_entry = f"{device_path}:/dev/ttyUSB0"
                if device_entry not in service_config['devices']:
                    service_config['devices'].append(device_entry)
                    print(f"Added device mapping: {device_entry}")
                else:
                    print("Device mapping already exists")
                break
    
    # Write the updated configuration
    with open(compose_file, 'w') as f:
        yaml.dump(config, f, default_flow_style=False, allow_unicode=True, sort_keys=False)
    
    print("docker-compose.yml updated successfully")
    
except Exception as e:
    print(f"Error: {e}")
    sys.exit(1)
EOF
    
    if [ $? -eq 0 ]; then
        print_status "docker-compose.yml updated successfully"
    else
        print_error "Failed to update docker-compose.yml automatically"
        print_info "Please manually add the following to your homeassistant service:"
        echo ""
        echo "    devices:"
        echo "      - $FULL_DEVICE_PATH:/dev/ttyUSB0"
        echo ""
        exit 1
    fi
}

# Function to restart Home Assistant
restart_home_assistant() {
    print_header "Restarting Home Assistant"
    
    cd "$HA_DIR"
    
    print_info "Stopping Home Assistant..."
    docker compose down
    
    print_info "Starting Home Assistant with new configuration..."
    docker compose up -d
    
    print_status "Home Assistant restarted"
    
    print_info "Waiting for Home Assistant to start (this may take a minute)..."
    sleep 10
    
    # Check if container is running
    if docker ps | grep -q homeassistant; then
        print_status "Home Assistant container is running"
    else
        print_warning "Home Assistant container might not be running. Check with: docker ps"
    fi
}

# Function to verify device passthrough in container
verify_device_passthrough() {
    print_info "Verifying device passthrough in container..."
    
    # Wait a bit more for container to fully start
    sleep 10
    
    # Check if the device is accessible inside the container
    if docker exec homeassistant ls -l /dev/ttyUSB0 &>/dev/null; then
        print_status "Device successfully passed through to container"
        docker exec homeassistant ls -l /dev/ttyUSB0
    else
        print_warning "Device might not be accessible in container yet"
        print_info "This is normal if Home Assistant is still starting up"
        print_info "You can verify manually with: docker exec homeassistant ls -l /dev/ttyUSB0"
    fi
}

# Function to check device permissions
check_device_permissions() {
    print_info "Checking device permissions..."
    
    if [ -e "$FULL_DEVICE_PATH" ]; then
        DEVICE_PERMS=$(ls -l "$FULL_DEVICE_PATH")
        print_info "Device permissions: $DEVICE_PERMS"
        
        # Get the real device (ttyUSB0)
        REAL_DEVICE=$(readlink -f "$FULL_DEVICE_PATH")
        REAL_PERMS=$(ls -l "$REAL_DEVICE" 2>/dev/null || echo "Cannot access $REAL_DEVICE")
        print_info "Real device permissions: $REAL_PERMS"
        
        # Check if the device is readable/writable
        if [ -r "$FULL_DEVICE_PATH" ] && [ -w "$FULL_DEVICE_PATH" ]; then
            print_status "Device has proper read/write permissions"
        else
            print_warning "Device might have permission issues"
            print_info "You may need to add your user to the dialout group:"
            echo "  sudo usermod -a -G dialout \$USER"
            echo "  (Log out and back in for changes to take effect)"
        fi
    fi
}

# Function to provide ZHA setup instructions
provide_zha_instructions() {
    print_header "Step 4-7: Home Assistant ZHA Configuration"
    
    echo -e "${GREEN}Your Zigbee dongle is now configured!${NC}"
    echo ""
    echo -e "${YELLOW}Device details:${NC}"
    echo "  Device name: $DEVICE_NAME"
    echo "  Full path: $FULL_DEVICE_PATH"
    echo "  Docker mapping: $FULL_DEVICE_PATH:/dev/ttyUSB0"
    echo ""
    echo -e "${YELLOW}Follow these steps in Home Assistant:${NC}"
    echo ""
    echo "1. ${BLUE}Access Home Assistant:${NC}"
    echo "   Open http://[your-server-ip]:8123"
    echo ""
    echo "2. ${BLUE}Add ZHA Integration:${NC}"
    echo "   Settings → Devices & Services → Add Integration"
    echo "   Search for: Zigbee Home Automation (ZHA)"
    echo ""
    echo "3. ${BLUE}Configure Serial Device:${NC}"
    echo "   - Select: /dev/ttyUSB0 (if auto-detected)"
    echo "   - OR manually enter: /dev/ttyUSB0"
    echo "   - Port speed: 115200 (default)"
    echo "   - Data flow control: hardware (default)"
    echo ""
    echo "4. ${BLUE}Create Zigbee Network:${NC}"
    echo "   - Choose: 'Erase and create a new network'"
    echo "   - This creates a fresh Zigbee network for new installations"
    echo ""
    echo "5. ${BLUE}Pair Devices:${NC}"
    echo "   - Settings → Devices & Services → ZHA → Add Device"
    echo "   - Put your Zigbee devices in pairing mode"
    echo "   - Devices should be discovered automatically"
    echo ""
    echo -e "${YELLOW}Best Practices for Zigbee Network:${NC}"
    echo "  • Keep coordinator away from Wi-Fi routers (at least 2m/6ft)"
    echo "  • USB extension cable is crucial (already recommended 30-100cm)"
    echo "  • Add powered Zigbee devices first (smart plugs, bulbs, relays)"
    echo "    → These act as Zigbee routers and extend your mesh network"
    echo "  • Battery-powered sensors do NOT extend the network"
    echo "  • Build a strong mesh before adding distant sensors"
}

# Function to create a summary file
create_summary() {
    print_info "Creating setup summary..."
    
    SUMMARY_FILE="$HA_DIR/zigbee_setup_summary.txt"
    
    cat > "$SUMMARY_FILE" <<EOF
Zigbee Setup Summary
====================
Date: $(date)
Device: Sonoff Zigbee 3.0 USB Dongle Plus
Device Name: $DEVICE_NAME
Device Path: $FULL_DEVICE_PATH
Real Device: $(readlink -f "$FULL_DEVICE_PATH")
Docker Device Mapping: $FULL_DEVICE_PATH:/dev/ttyUSB0

Setup Steps Completed:
1. ✅ Dongle detected and verified
2. ✅ Docker configured for USB passthrough
3. ✅ Home Assistant restarted
4. ⏳ ZHA integration (manual step in HA UI)
5. ⏳ Network creation (manual step in HA UI)
6. ⏳ Device pairing (manual step in HA UI)

Troubleshooting Commands:
- Check if device is detected: ls -l /dev/serial/by-id/
- Check container: docker ps | grep homeassistant
- Check container logs: docker logs homeassistant
- Verify device passthrough: docker exec homeassistant ls -l /dev/ttyUSB0
- Check device permissions: ls -l $FULL_DEVICE_PATH
- Fix permissions: sudo usermod -a -G dialout \$USER
EOF
    
    print_status "Summary saved to: $SUMMARY_FILE"
}

# Main execution
main() {
    print_header "Home Assistant Zigbee Setup Script"
    print_info "This script will configure your Sonoff Zigbee dongle for Home Assistant"
    echo ""
    
    verify_ha_directory
    
    print_warning "Please ensure the Sonoff dongle is plugged in before continuing."
    print_info "Using a USB extension cable (30-100cm) is HIGHLY recommended to reduce USB 3.0 interference."
    echo ""
    
    read -p "Press Enter to continue or Ctrl+C to abort... "
    
    detect_sonoff_dongle
    check_device_permissions
    update_docker_compose
    restart_home_assistant
    verify_device_passthrough
    create_summary
    provide_zha_instructions
    
    print_header "Setup Complete!"
    echo -e "${GREEN}The Zigbee dongle has been configured for Home Assistant.${NC}"
    echo -e "${GREEN}Please follow the manual steps above to complete the ZHA setup in the Home Assistant UI.${NC}"
    echo ""
    echo -e "${BLUE}Quick troubleshooting command:${NC}"
    echo "  docker exec homeassistant ls -l /dev/ttyUSB0"
    echo ""
}

# Run main function
main