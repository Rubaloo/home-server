#!/bin/bash

# Script to create home-server folder structure
# Usage: ./create-server-structure.sh

set -e  # Exit on error

# Define colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}Creating home-server folder structure...${NC}"

# Base directory
BASE_DIR="."

# Create base directory and subdirectories
mkdir -p "$BASE_DIR"

# Create main directories
mkdir -p "$BASE_DIR/config"
mkdir -p "$BASE_DIR/docs"
mkdir -p "$BASE_DIR/scripts"
mkdir -p "$BASE_DIR/assets"
mkdir -p "$BASE_DIR/generated"

# Create phase directories
for phase in phase01-ubuntu phase02-docker phase03-storage phase04-network \
              phase05-monitoring phase06-backups phase07-services phase08-maintenance; do
    mkdir -p "$BASE_DIR/phases/$phase"
done

# Create phase01-ubuntu subdirectories with all required paths
mkdir -p "$BASE_DIR/phases/phase01-ubuntu/install"
mkdir -p "$BASE_DIR/phases/phase01-ubuntu/validate"
mkdir -p "$BASE_DIR/phases/phase01-ubuntu/backup"
mkdir -p "$BASE_DIR/phases/phase01-ubuntu/rollback"
mkdir -p "$BASE_DIR/phases/phase01-ubuntu/templates"
mkdir -p "$BASE_DIR/phases/phase01-ubuntu/logs"
mkdir -p "$BASE_DIR/phases/phase01-ubuntu/reports"

# Create README.md files
echo "# Home Server Project" > "$BASE_DIR/README.md"
echo "# Phase 01 - Ubuntu Setup" > "$BASE_DIR/phases/phase01-ubuntu/README.md"

# Create bootstrap script
cat > "$BASE_DIR/bootstrap.sh" << 'EOF'
#!/bin/bash
# Main bootstrap script for home server setup
echo "Starting home server bootstrap process..."
# Add your main setup logic here
EOF
chmod +x "$BASE_DIR/bootstrap.sh"

# Create config files with sample content
echo "# Server Configuration" > "$BASE_DIR/config/server.conf"
echo "# Network Configuration" > "$BASE_DIR/config/network.conf"
echo "# Users Configuration" > "$BASE_DIR/config/users.conf"
echo "# Docker Configuration" > "$BASE_DIR/config/docker.conf"

# Create documentation files
echo "# Architecture Documentation" > "$BASE_DIR/docs/architecture.md"
echo "# Implementation Phases" > "$BASE_DIR/docs/phases.md"
echo "# Recovery Procedures" > "$BASE_DIR/docs/recovery.md"

# Create all phase01 install scripts
for i in {01..16}; do
    script_name="$BASE_DIR/phases/phase01-ubuntu/install/$i-"
    case $i in
        01) script_name+="system-update.sh" ;;
        02) script_name+="install-packages.sh" ;;
        03) script_name+="configure-network.sh" ;;
        04) script_name+="configure-hostname.sh" ;;
        05) script_name+="configure-timezone.sh" ;;
        06) script_name+="enable-firewall.sh" ;;
        07) script_name+="enable-updates.sh" ;;
        08) script_name+="configure-ssh.sh" ;;
        09) script_name+="install-fail2ban.sh" ;;
        10) script_name+="create-directories.sh" ;;
        11) script_name+="create-aliases.sh" ;;
        12) script_name+="install-lm-sensors.sh" ;;
        13) script_name+="configure-logrotate.sh" ;;
        14) script_name+="enable-timesync.sh" ;;
        15) script_name+="create-documentation.sh" ;;
        16) script_name+="create-docker-user.sh" ;;
    esac
    echo "#!/bin/bash" > "$script_name"
    echo "# Phase 01 - Step $i" >> "$script_name"
    chmod +x "$script_name"
done

# Create phase01 master script
cat > "$BASE_DIR/phases/phase01-ubuntu/install/phase01.sh" << 'EOF'
#!/bin/bash
# Master script to run all phase01 installation steps
echo "Running Phase 01 - Ubuntu Setup..."
for script in [0-9][0-9]-*.sh; do
    echo "Executing: $script"
    ./"$script"
done
echo "Phase 01 completed!"
EOF
chmod +x "$BASE_DIR/phases/phase01-ubuntu/install/phase01.sh"

# Create validation scripts
for script in check-network.sh check-firewall.sh check-services.sh \
              check-security.sh check-health.sh; do
    cat > "$BASE_DIR/phases/phase01-ubuntu/validate/$script" << 'EOF'
#!/bin/bash
echo "Running validation check..."
# Add validation logic here
EOF
    chmod +x "$BASE_DIR/phases/phase01-ubuntu/validate/$script"
done

# Create validation master script
cat > "$BASE_DIR/phases/phase01-ubuntu/validate/phase01-validation.sh" << 'EOF'
#!/bin/bash
# Master validation script
echo "Running Phase 01 validation..."
for script in check-*.sh; do
    echo "Validating: $script"
    ./"$script"
done
echo "Validation completed!"
EOF
chmod +x "$BASE_DIR/phases/phase01-ubuntu/validate/phase01-validation.sh"

# Create backup scripts
for script in backup-config.sh restore-config.sh backup-netplan.sh; do
    cat > "$BASE_DIR/phases/phase01-ubuntu/backup/$script" << 'EOF'
#!/bin/bash
echo "Running backup/restore operation..."
# Add backup/restore logic here
EOF
    chmod +x "$BASE_DIR/phases/phase01-ubuntu/backup/$script"
done

# Create rollback scripts
for script in disable-firewall.sh restore-ssh.sh restore-network.sh; do
    cat > "$BASE_DIR/phases/phase01-ubuntu/rollback/$script" << 'EOF'
#!/bin/bash
echo "Running rollback operation..."
# Add rollback logic here
EOF
    chmod +x "$BASE_DIR/phases/phase01-ubuntu/rollback/$script"
done

# Create template files with sample content
echo "# SSHD Configuration Template" > "$BASE_DIR/phases/phase01-ubuntu/templates/sshd_config"
echo "# Fail2ban Configuration Template" > "$BASE_DIR/phases/phase01-ubuntu/templates/jail.local"
echo "# Netplan Configuration Template" > "$BASE_DIR/phases/phase01-ubuntu/templates/netplan.yaml"
echo "# Bash Aliases Template" > "$BASE_DIR/phases/phase01-ubuntu/templates/bash_aliases"
echo "# Logrotate Configuration Template" > "$BASE_DIR/phases/phase01-ubuntu/templates/logrotate.conf"

# Create main scripts
for script in healthcheck.sh server-report.sh update-all.sh backup-all.sh restore-all.sh; do
    cat > "$BASE_DIR/scripts/$script" << 'EOF'
#!/bin/bash
echo "Running script..."
# Add script logic here
EOF
    chmod +x "$BASE_DIR/scripts/$script"
done

# Create .gitkeep files for empty directories
touch "$BASE_DIR/phases/phase01-ubuntu/logs/.gitkeep"
touch "$BASE_DIR/phases/phase01-ubuntu/reports/.gitkeep"
touch "$BASE_DIR/assets/.gitkeep"
touch "$BASE_DIR/generated/.gitkeep"

# Create README files for other phases
for phase in phase02-docker phase03-storage phase04-network phase05-monitoring \
             phase06-backups phase07-services phase08-maintenance; do
    echo "# Phase ${phase#phase}" > "$BASE_DIR/phases/$phase/README.md"
done

echo -e "${GREEN}✓ Folder structure created successfully!${NC}"
echo -e "${BLUE}Structure created in: ${NC}$BASE_DIR/"
echo -e "${BLUE}Total directories created: ${NC}$(find "$BASE_DIR" -type d | wc -l)"
echo -e "${BLUE}Total files created: ${NC}$(find "$BASE_DIR" -type f | wc -l)"

# Display tree structure if tree command is available
if command -v tree &> /dev/null; then
    echo -e "\n${BLUE}Directory tree:${NC}"
    tree "$BASE_DIR" -L 3
else
    echo -e "\n${BLUE}To view the directory tree, install 'tree' command:${NC}"
    echo "  sudo apt-get install tree  # Debian/Ubuntu"
    echo "  sudo yum install tree      # RHEL/CentOS"
fi

echo -e "${GREEN}Done!${NC}"