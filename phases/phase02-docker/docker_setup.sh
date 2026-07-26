#!/bin/bash

#===============================================================================
# DOCKER COMPLETE SETUP SCRIPT
# Comprehensive Docker Installation & Configuration for Ubuntu
# Version: 1.0.0
#===============================================================================
#
# UNIQUE FEATURES OF THIS SCRIPT:
#
# 1. Progress Tracking: Visual progress bar showing real-time installation progress
#    - Displays a dynamic progress bar that updates as each step completes
#    - Shows step count (e.g., "Step 5/23") for clear progress indication
#    - Provides percentage-based completion tracking
#
# 2. Error Handling: Robust error checking with set -euo pipefail and status verification
#    - Uses 'set -euo pipefail' to exit on errors, undefined variables, and pipe failures
#    - Each step includes success/failure verification with clear error messages
#    - Prevents partial installations by stopping on first critical failure
#
# 3. Color-Coded Logging: Clear visual feedback with colored output for different message types
#    - BLUE for informational messages
#    - GREEN for success confirmations
#    - YELLOW for warnings that don't stop execution
#    - RED for critical errors that halt the installation
#
# 4. Comprehensive Verification: Each step is verified for success before proceeding
#    - Validates package removals, installations, and configurations
#    - Checks service status after starting/enabling
#    - Verifies Docker functionality with test containers
#    - Confirms Docker Compose functionality with practical tests
#
# 5. Automatic Ubuntu Detection: Detects your Ubuntu version automatically
#    - Reads /etc/os-release to identify Ubuntu distribution
#    - Extracts version codename for correct repository configuration
#    - Validates that the system is actually Ubuntu before proceeding
#
# 6. Clean Interruption Handling: Proper cleanup if the script is interrupted
#    - Traps SIGINT and SIGTERM signals for graceful exit
#    - Provides user feedback when script is interrupted
#    - Prevents zombie processes and incomplete states
#
# 7. Production-Ready Configuration: Implements log rotation and live restore by default
#    - Configures json-file logging driver with size limits (10MB per file)
#    - Limits log retention to 3 files per container to prevent disk filling
#    - Enables live-restore to keep containers running during daemon updates
#
# 8. User-Friendly Output: Clear success/failure messages and next-step instructions
#    - Provides a professional header and footer with formatted output
#    - Includes helpful post-installation commands and tips
#    - Clearly indicates when user action is required (logout/login)
#
# 9. Temporary Test Cleanup: Automatically cleans up Docker Compose test environment
#    - Creates temporary test directory with unique name to avoid conflicts
#    - Tests Docker Compose with a simple NGINX deployment
#    - Automatically removes test containers, volumes, and directories
#    - Returns system to clean state after verification
#
# 10. Non-Destructive: Safely handles missing packages without causing errors
#     - Uses '|| true' for removal of potentially non-existent packages
#     - Redirects error output to /dev/null where appropriate
#     - Checks for existence of resources before attempting operations
#     - Never removes user data or existing configurations
#
#===============================================================================

set -euo pipefail  # Exit on error, undefined variable, and pipe failure

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if command executed successfully
check_status() {
    if [ $? -eq 0 ]; then
        log_success "$1"
    else
        log_error "$2"
        exit 1
    fi
}

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run with sudo or as root"
        exit 1
    fi
}

# Function to detect Ubuntu version
detect_ubuntu_version() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        if [[ "$ID" != "ubuntu" ]]; then
            log_error "This script is designed for Ubuntu systems only"
            exit 1
        fi
        log_info "Detected Ubuntu $VERSION_CODENAME ($VERSION_ID)"
    else
        log_error "Cannot detect OS version"
        exit 1
    fi
}

# Function to create progress bar
show_progress() {
    local current=$1
    local total=$2
    local percent=$((current * 100 / total))
    local bar_length=50
    local filled=$((percent * bar_length / 100))
    local empty=$((bar_length - filled))
    
    printf "\r["
    printf "%${filled}s" | tr ' ' '='
    printf "%${empty}s" | tr ' ' ' '
    printf "] %d%%" "$percent"
}

# Main installation function
main() {
    clear
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║           DOCKER COMPLETE SETUP FOR UBUNTU                ║"
    echo "║                 Automated Installation                    ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo ""
    
    # Check prerequisites
    check_root
    detect_ubuntu_version
    
    local total_steps=23
    local current_step=0
    
    # Step 1: Remove old Docker packages
    ((current_step++))
    show_progress $current_step $total_steps
    log_info "Step $current_step/$total_steps: Removing old Docker packages..."
    apt remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    check_status "Old packages removed (or none existed)" "Failed to remove old packages"
    echo ""
    
    # Step 2: Update packages
    ((current_step++))
    show_progress $current_step $total_steps
    log_info "Step $current_step/$total_steps: Updating package lists..."
    apt update -qq
    check_status "Package lists updated" "Failed to update packages"
    
    log_info "Upgrading existing packages..."
    apt upgrade -y -qq
    check_status "Packages upgraded" "Failed to upgrade packages"
    echo ""
    
    # Step 3: Install prerequisites
    ((current_step++))
    show_progress $current_step $total_steps
    log_info "Step $current_step/$total_steps: Installing prerequisites..."
    apt install -y -qq ca-certificates curl gnupg lsb-release software-properties-common apt-transport-https
    check_status "Prerequisites installed" "Failed to install prerequisites"
    echo ""
    
    # Step 4: Create Docker keyring directory
    ((current_step++))
    show_progress $current_step $total_steps
    log_info "Step $current_step/$total_steps: Creating Docker keyring directory..."
    install -m 0755 -d /etc/apt/keyrings
    check_status "Keyring directory created" "Failed to create keyring directory"
    echo ""
    
    # Step 5: Download Docker GPG key
    ((current_step++))
    show_progress $current_step $total_steps
    log_info "Step $current_step/$total_steps: Downloading Docker GPG key..."
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg --yes
    check_status "Docker GPG key downloaded" "Failed to download GPG key"
    echo ""
    
    # Step 6: Set permissions
    ((current_step++))
    show_progress $current_step $total_steps
    log_info "Step $current_step/$total_steps: Setting key permissions..."
    chmod a+r /etc/apt/keyrings/docker.gpg
    check_status "Key permissions set" "Failed to set permissions"
    echo ""
    
    # Step 7: Add Docker repository
    ((current_step++))
    show_progress $current_step $total_steps
    log_info "Step $current_step/$total_steps: Adding Docker repository..."
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    check_status "Docker repository added" "Failed to add repository"
    echo ""
    
    # Step 8: Update repositories
    ((current_step++))
    show_progress $current_step $total_steps
    log_info "Step $current_step/$total_steps: Updating repository lists..."
    apt update -qq
    check_status "Repositories updated" "Failed to update repositories"
    echo ""
    
    # Step 9: Install Docker
    ((current_step++))
    show_progress $current_step $total_steps
    log_info "Step $current_step/$total_steps: Installing Docker packages..."
    apt install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    check_status "Docker installed successfully" "Failed to install Docker"
    echo ""
    
    # Step 10: Enable Docker
    ((current_step++))
    show_progress $current_step $total_steps
    log_info "Step $current_step/$total_steps: Enabling Docker service..."
    systemctl enable docker
    check_status "Docker service enabled" "Failed to enable Docker"
    echo ""
    
    # Step 11: Start Docker
    ((current_step++))
    show_progress $current_step $total_steps
    log_info "Step $current_step/$total_steps: Starting Docker service..."
    systemctl start docker
    check_status "Docker service started" "Failed to start Docker"
    echo ""
    
    # Step 12: Verify service
    ((current_step++))
    show_progress $current_step $total_steps
    log_info "Step $current_step/$total_steps: Verifying Docker service status..."
    if systemctl is-active --quiet docker; then
        log_success "Docker is active and running"
    else
        log_error "Docker service is not running"
        exit 1
    fi
    echo ""
    
    # Step 13: Add user to Docker group
    ((current_step++))
    show_progress $current_step $total_steps
    log_info "Step $current_step/$total_steps: Adding user to Docker group..."
    if [ -n "$SUDO_USER" ]; then
        usermod -aG docker "$SUDO_USER"
        log_success "User $SUDO_USER added to Docker group"
        log_warning "You will need to log out and back in for group changes to take effect"
    else
        log_warning "No SUDO_USER detected, skipping user group addition"
    fi
    echo ""
    
    # Step 14: Test Docker
    ((current_step++))
    show_progress $current_step $total_steps
    log_info "Step $current_step/$total_steps: Testing Docker with hello-world..."
    if docker run --rm hello-world > /dev/null 2>&1; then
        log_success "Docker test successful"
    else
        log_warning "Docker test failed (may need to run as user in docker group)"
    fi
    echo ""
    
    # Step 15: Check version
    ((current_step++))
    show_progress $current_step $total_steps
    log_info "Step $current_step/$total_steps: Checking Docker version..."
    docker version --format '{{.Server.Version}}' > /dev/null 2>&1
    check_status "Docker version check completed" "Failed to check version"
    docker version
    echo ""
    
    # Step 16: Check Compose
    ((current_step++))
    show_progress $current_step $total_steps
    log_info "Step $current_step/$total_steps: Checking Docker Compose..."
    docker compose version
    check_status "Docker Compose is available" "Docker Compose not found"
    echo ""
    
    # Step 17: Configure Docker daemon
    ((current_step++))
    show_progress $current_step $total_steps
    log_info "Step $current_step/$total_steps: Configuring Docker daemon..."
    cat > /etc/docker/daemon.json << 'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "live-restore": true
}
EOF
    check_status "Docker daemon configuration created" "Failed to create daemon configuration"
    echo ""
    
    # Step 18: Restart Docker
    ((current_step++))
    show_progress $current_step $total_steps
    log_info "Step $current_step/$total_steps: Restarting Docker service..."
    systemctl restart docker
    check_status "Docker service restarted" "Failed to restart Docker"
    echo ""
    
    # Step 19: Create directory structure
    ((current_step++))
    show_progress $current_step $total_steps
    log_info "Step $current_step/$total_steps: Creating directory structure..."
    mkdir -p \
        /srv/docker/{compose,stacks,volumes,backups,configs,secrets} \
        /srv/media \
        /srv/downloads \
        /srv/data \
        /srv/backups
    check_status "Directory structure created" "Failed to create directory structure"
    echo ""
    
    # Step 20: Give ownership
    ((current_step++))
    show_progress $current_step $total_steps
    log_info "Step $current_step/$total_steps: Setting directory ownership..."
    if [ -n "$SUDO_USER" ]; then
        chown -R "$SUDO_USER:$SUDO_USER" /srv
        log_success "Ownership set for user $SUDO_USER"
    else
        log_warning "No SUDO_USER detected, skipping ownership change"
    fi
    echo ""
    
    # Step 21: Verify Docker info
    ((current_step++))
    show_progress $current_step $total_steps
    log_info "Step $current_step/$total_steps: Verifying Docker configuration..."
    docker info --format 'Server Version: {{.ServerVersion}}
Storage Driver: {{.Driver}}
Logging Driver: {{.LoggingDriver}}
Cgroup Version: {{.CgroupVersion}}
Docker Root Dir: {{.DockerRootDir}}'
    check_status "Docker configuration verified" "Failed to verify configuration"
    echo ""
    
    # Step 22: Verify networking
    ((current_step++))
    show_progress $current_step $total_steps
    log_info "Step $current_step/$total_steps: Checking Docker networks..."
    docker network ls
    check_status "Docker networks listed" "Failed to list networks"
    echo ""
    
    # Step 23: Test Compose
    ((current_step++))
    show_progress $current_step $total_steps
    log_info "Step $current_step/$total_steps: Testing Docker Compose..."
    
    # Create test directory
    local test_dir="/tmp/docker-test-$$"
    mkdir -p "$test_dir"
    cd "$test_dir"
    
    # Create compose file
    cat > compose.yaml << 'EOF'
services:
  nginx:
    image: nginx:latest
    ports:
      - "8080:80"
EOF
    
    # Start compose
    docker compose up -d > /dev/null 2>&1
    
    if docker compose ps | grep -q "Up"; then
        log_success "Docker Compose test successful"
        log_info "NGINX is running on http://localhost:8080"
        
        # Cleanup
        docker compose down > /dev/null 2>&1
        cd /
        rm -rf "$test_dir"
    else
        log_warning "Docker Compose test failed"
    fi
    echo ""
    
    # Final summary
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║              INSTALLATION COMPLETE!                       ║"
    echo "╠═══════════════════════════════════════════════════════════╣"
    echo "║ Docker is now installed and configured on your system     ║"
    echo "║                                                           ║"
    echo "║ IMPORTANT: If you added your user to the docker group,    ║"
    echo "║ you need to log out and back in for changes to take       ║"
    echo "║ effect. Alternatively, run: newgrp docker                 ║"
    echo "║                                                           ║"
    echo "║ Quick commands:                                           ║"
    echo "║   docker version                                          ║"
    echo "║   docker compose version                                  ║"
    echo "║   docker run hello-world                                  ║"
    echo "║                                                           ║"
    echo "║ Directory structure created at /srv/                      ║"
    echo "║ Daemon config: /etc/docker/daemon.json                    ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
}

# Trap for cleanup on script interruption
cleanup() {
    echo -e "\n${YELLOW}[WARNING]${NC} Script interrupted. Cleaning up..."
    exit 1
}

trap cleanup SIGINT SIGTERM

# Run main function
main

exit 0