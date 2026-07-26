#!/usr/bin/env bash

set -euo pipefail

echo "Creating project structure..."

# Create all directories
mkdir -p ./{bootstrap,docker,services/{pihole,plex,immich,paperless,nextcloud},storage,backup,monitoring/{uptime-kuma,grafana,prometheus},scripts}

#########################################
# Helper function
#########################################

create_script() {
    local file="$1"
    
    # Create directory if it doesn't exist
    mkdir -p "$(dirname "$file")"

    cat > "$file" <<EOF
#!/usr/bin/env bash

set -euo pipefail

echo "=================================================="
echo "Executing: \$(basename "\$0")"
echo
echo "TODO: Implement this script."
echo "=================================================="
EOF

    chmod +x "$file"
}

#########################################
# Bootstrap
#########################################

create_script "./bootstrap/01-system-update.sh"
create_script "./bootstrap/02-packages.sh"
create_script "./bootstrap/03-users.sh"
create_script "./bootstrap/04-ssh.sh"

#########################################
# Docker
#########################################

create_script "./docker/install.sh"

cat > "./docker/daemon.json" <<EOF
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    }
}
EOF

#########################################
# Services
#########################################

services=(
    "pihole"
    "plex"
    "immich"
    "paperless"
    "nextcloud"
)

for service in "${services[@]}"; do
    mkdir -p "./services/$service"
    
    create_script "./services/$service/install.sh"

    cat > "./services/$service/docker-compose.yml" <<EOF
services:
  ${service}:
    image: REPLACE_ME
    container_name: ${service}

    ports:
      - "REPLACE_ME"

    volumes:
      - ./data:/data

    restart: unless-stopped
EOF

done

#########################################
# Storage
#########################################

create_script "./storage/mount-drives.sh"
create_script "./storage/mergerfs.sh"
create_script "./storage/snapraid.sh"

#########################################
# Backup
#########################################

create_script "./backup/backup.sh"
create_script "./backup/restore.sh"

#########################################
# Monitoring
#########################################

for service in "uptime-kuma" "grafana" "prometheus"
do
    mkdir -p "./monitoring/$service"
    
    create_script "./monitoring/$service/install.sh"

    cat > "./monitoring/$service/docker-compose.yml" <<EOF
services:
  ${service}:
    image: REPLACE_ME

    restart: unless-stopped
EOF

done

#########################################
# Helpers
#########################################

create_script "./scripts/helpers.sh"

#########################################
# .env
#########################################

cat > "./.env" <<EOF
# ===================================================
# Global environment variables
# ===================================================

TIMEZONE=Europe/Madrid

PUID=1000
PGID=1000

DOMAIN=example.local

DOCKER_NETWORK=home-network
EOF

#########################################
# install.sh
#########################################

cat > "./install.sh" <<'EOF'
#!/usr/bin/env bash

set -euo pipefail

echo
echo "==============================================="
echo " Home Server Installation"
echo "==============================================="
echo

run() {

    local script="$1"

    if [[ -x "$script" ]]; then
        "$script"
    else
        echo "Skipping $script"
    fi
}

echo "Running bootstrap..."

run ./bootstrap/01-system-update.sh
run ./bootstrap/02-packages.sh
run ./bootstrap/03-users.sh
run ./bootstrap/04-ssh.sh

echo
echo "Installing Docker..."

run ./docker/install.sh

echo
echo "Storage..."

run ./storage/mount-drives.sh
run ./storage/mergerfs.sh
run ./storage/snapraid.sh

echo
echo "Backup..."

run ./backup/backup.sh

echo
echo "Installation finished."
EOF

chmod +x "./install.sh"

#########################################
# README
#########################################

cat > "./README.md" <<EOF
# Home Server

This repository contains everything required to deploy my home server.

## Project Structure

\`\`\`
bootstrap/
docker/
services/
storage/
backup/
monitoring/
scripts/
\`\`\`

## Installation

\`\`\`bash
chmod +x install.sh
./install.sh
\`\`\`

## Current Status

- [ ] Bootstrap
- [ ] Docker
- [ ] Storage
- [ ] Services
- [ ] Monitoring
- [ ] Backup
EOF

echo
echo "==============================================="
echo "Project successfully created!"
echo
echo "Location:"
echo "    $(pwd)"
echo
echo "Next step:"
echo "    ./install.sh"
echo "==============================================="