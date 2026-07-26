#!/bin/bash
# Phase 01 - Step 10

sudo mkdir -p /srv/docker/{compose,volumes,backups,scripts}
sudo mkdir -p /srv/media/{music,photos,videos,downloads}
sudo mkdir -p /srv/backups
sudo mkdir -p /srv/logs
sudo mkdir -p /srv/data

sudo chown -R $USER:$USER /srv
