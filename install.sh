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
