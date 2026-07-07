#!/bin/bash
set -e

sudo systemctl stop gnome-remote-desktop || true
sudo systemctl disable gnome-remote-desktop || true

sudo apt-get install -y xrdp xorgxrdp

readonly STARTWM_PATH="/etc/xrdp/startwm.sh"
if [ -f "$STARTWM_PATH" ]; then
    echo "Configuring environment hooks inside $STARTWM_PATH..."
    # Inject variables right underneath the shell declaration line so Xorg logs into native Ubuntu GNOME
    sudo sed -i '/#!\/bin\/sh/a export GNOME_SHELL_SESSION_MODE=ubuntu\nexport XDG_CURRENT_DESKTOP=ubuntu:GNOME' "$STARTWM_PATH"
else
    echo "Warning: $STARTWM_PATH layout not found. Skipping session variable injection."
fi

# Apply system security certificate permissions to the new daemon
if getent group ssl-cert > /dev/null; then
    sudo adduser xrdp ssl-cert
fi

# Mitigate virtual machine vsock socket initialization failures if running inside a hypervisor
if grep -q "use_vsock=true" /etc/xrdp/xrdp.ini 2>/dev/null; then
    echo "Tuning xrdp.ini parameters for basic network socket stability..."
    sudo sed -i 's/use_vsock=true/use_vsock=false/' /etc/xrdp/xrdp.ini
fi

sudo systemctl enable xrdp
sudo systemctl restart xrdp
