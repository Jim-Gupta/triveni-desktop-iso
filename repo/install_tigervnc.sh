#!/bin/bash

########################################################################################################################
# Script: install_tigervnc.sh
# Description: Installs TigerVNC from the active local repository, configures a standalone virtual X11 display session
#              for a designated user, and provisions a systemd service to manage it on port 5901 (:1).
# Usage: sudo ./install_tigervnc.sh [username]
########################################################################################################################

set -e

# Target user defaults to the user who invoked sudo, or root if run directly
TARGET_USER="${1:-$SUDO_USER}"
VNC_DISPLAY_NUMBER="1" # Maps to network port 5901

if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root. Please use sudo."
    exit 1
fi

if [ -z "$TARGET_USER" ] || [ "$TARGET_USER" = "root" ]; then
    echo "Error: Could not automatically detect a standard user account."
    echo "Usage: sudo $0 [target_username]"
    exit 1
fi

echo "========================================================================"
echo "Step 1: Installing TigerVNC from local repository..."
echo "========================================================================"
sudo apt-get update
sudo apt-get install -y tigervnc-standalone-server tigervnc-tools tigervnc-common

echo "========================================================================"
echo "Step 2: Provisioning system-wide user mappings..."
echo "========================================================================"
# Map display :1 to our target user in the global configuration file
sudo mkdir -p /etc/tigervnc
echo ":$VNC_DISPLAY_NUMBER=$TARGET_USER" | sudo tee /etc/tigervnc/vncserver.users > /dev/null
echo "Mapped display :$VNC_DISPLAY_NUMBER to user '$TARGET_USER'."

echo "========================================================================"
echo "Step 3: Building user-space VNC configuration environment..."
echo "========================================================================"
USER_HOME=$(eval echo "~$TARGET_USER")
USER_VNC_DIR="$USER_HOME/.vnc"

sudo mkdir -p "$USER_VNC_DIR"

# Define the user's specific session properties. 
# "session=ubuntu" explicitly forces TigerVNC to execute an X11 Ubuntu GNOME shell.
sudo tee "$USER_VNC_DIR/config" > /dev/null <<EOF
session=ubuntu-xorg
geometry=1920x1080
localhost=no
alwaysshared
EOF

echo "========================================================================"
echo "Step 4: Creating security credentials for '$TARGET_USER'..."
echo "========================================================================"

sudo chown -R "$TARGET_USER:$TARGET_USER" "$USER_VNC_DIR"

# Prompt for the VNC access password natively as the target user
echo "Please enter a security password for your remote VNC connections:"
sudo -u "$TARGET_USER" vncpasswd

# Fix directory ownership permissions
sudo chown -R "$TARGET_USER:$TARGET_USER" "$USER_VNC_DIR"

echo "========================================================================"
echo "Step 5: Initialization and starting systemd service..."
echo "========================================================================"
# Reload systemd configuration to register TigerVNC's native service template
sudo systemctl daemon-reload

# Clean up stale lock files
sudo rm -f /tmp/.X1-lock
sudo rm -rf /tmp/.X11-unix/X1

# Enable and start the specific display instance service
sudo systemctl enable "tigervncserver@:$VNC_DISPLAY_NUMBER.service"
sudo systemctl restart "tigervncserver@:$VNC_DISPLAY_NUMBER.service"

echo "========================================================================"
echo "SUCCESS: TigerVNC installation complete!"
echo "========================================================================"
