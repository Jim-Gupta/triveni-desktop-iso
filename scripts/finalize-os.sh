#!/bin/bash

set -euo pipefail

readonly LOG_FILE="/var/log/triveni-install.log"
exec > >(tee -a "$LOG_FILE") 2>&1

readonly AUTO_UPGRADES_FILE="/etc/apt/apt.conf.d/20auto-upgrades"
readonly WAIT_ONLINE_FILE="/etc/systemd/system/network-online.target.wants/systemd-networkd-wait-online.service"

echo "**********************************************************************"
echo "Running finalize-os.sh (executing finalize-os commands in target environment)"

log() {
  echo "[finalize-os] $*"
}

warn() {
  echo "[finalize-os][warn] $*"
}

require_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "This script must run as root." >&2
    exit 1
  fi
}

require_commands() {
  local missing=0
  for cmd in dpkg apt-get sed update-grub dmidecode; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      log "Missing required command: $cmd" >&2
      missing=1
    fi
  done
  if [ "$missing" -ne 0 ]; then
    exit 1
  fi
}

configure_grub() {
  local grub_params
  if dmidecode | grep -qE "Product Name: X9SCL/X9SCM|Product Name: X11SSH-F"; then
    grub_params="bootdegraded=true nomodeset"
  else
    grub_params="bootdegraded=true"
  fi

  if [ ! -f /etc/default/grub ]; then
    warn "/etc/default/grub not found; skipping GRUB tuning"
    return
  fi

  sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*$/GRUB_CMDLINE_LINUX_DEFAULT="'"$grub_params"'"/' /etc/default/grub
  sed -i 's/^GRUB_TIMEOUT=.*$/GRUB_TIMEOUT=3/' /etc/default/grub
  if grep -q "GRUB_RECORDFAIL_TIMEOUT=" /etc/default/grub; then
    sed -i 's/^GRUB_RECORDFAIL_TIMEOUT=.*$/GRUB_RECORDFAIL_TIMEOUT=3/' /etc/default/grub
  else
    sed -i '/^GRUB_TIMEOUT=.*$/a GRUB_RECORDFAIL_TIMEOUT=3' /etc/default/grub
  fi
  update-grub
}

configure_update_policy() {
  if [ -f "$AUTO_UPGRADES_FILE" ]; then
    sed -i 's/^APT::Periodic::Update-Package-Lists "1";/APT::Periodic::Update-Package-Lists "0";/' "$AUTO_UPGRADES_FILE"
    sed -i 's/^APT::Periodic::Unattended-Upgrade "1";/APT::Periodic::Unattended-Upgrade "0";/' "$AUTO_UPGRADES_FILE"
  else
    warn "$AUTO_UPGRADES_FILE not found; skipping unattended-upgrades tuning"
  fi
}

configure_network_timeouts() {
  if [ -f /etc/dhcp/dhclient.conf ]; then
    sed -i 's/^timeout 300;/timeout 15;/' /etc/dhcp/dhclient.conf
  else
    warn "/etc/dhcp/dhclient.conf not found"
  fi

  if [ -f "$WAIT_ONLINE_FILE" ]; then
    sed -i 's/^TimeoutStartSec=5min/TimeoutStartSec=15/' "$WAIT_ONLINE_FILE"
  else
    warn "$WAIT_ONLINE_FILE not found"
  fi
}

apply_os_extras() {
  if [ -d /cdrom/pool/os-extras ]; then
    ls -la /cdrom/pool/os-extras >/var/log/tmp-os-extras.txt || true
    cp -Ra /cdrom/pool/os-extras/* /

    # Directories must be accessible (755)
    chmod 755 /usr/share/backgrounds/triveni
    chmod 755 /usr/share/gnome-background-properties

    # Files must be globally readable (644)
    chmod 644 /usr/share/gnome-background-properties/triveni-wallpapers.xml
    chmod 644 /usr/share/backgrounds/triveni/*

  else
    warn "/cdrom/pool/os-extras not found; skipping copy"
  fi
}

seed_triveni_home() {
  if [ -d /home/triveni ] && [ -d /etc/skel ]; then
    cp -a /etc/skel/. /home/triveni/
    chown -R 1000:1000 /home/triveni
    chmod -R u+rwX /home/triveni
    chmod 750 /home/triveni
  else
    warn "Skipping /home/triveni seed (home or /etc/skel missing)"
  fi
}

fix_permissions() {
  [ -d /usr/share ] && chmod a+r /usr/share || true
  [ -d /usr/share/applications ] && chmod -R a+r /usr/share/applications || true
}

cleanup_smartcard_overrides() {
  rm -f /etc/pam.d/*smartcard* || true
  rm -f /etc/alternatives/gdm-smartcard || true
  dconf update || true
}

disable_onetime_service() {
  systemctl disable onetime-reboot.service 2>/dev/null || true
}

configure_timezone() {
  local time_zone
  if [ -r /etc/timezone ]; then
    time_zone=$(tr -d '\r ' </etc/timezone)
    [ -n "$time_zone" ] || time_zone="America/New_York"
  else
    time_zone="America/New_York"
    echo "$time_zone" >/etc/timezone
  fi

  log "Enforcing system time zone: $time_zone"
  /usr/bin/ln -sf "/usr/share/zoneinfo/$time_zone" /etc/localtime
  DEBIAN_FRONTEND=noninteractive dpkg-reconfigure -f noninteractive tzdata
}

recompile_icons_and_wallpapers() {
    # recompile gsettings schemas so that the new wallpaper is available in the GNOME settings
    if [ -d /home/triveni ]; then
        chown -R 1000:1000 /home/triveni
        chmod -R u+rwX /home/triveni
        chmod 750 /home/triveni
    fi
    
    glib-compile-schemas /usr/share/glib-2.0/schemas/
}

main() {
  log "Running finalize-os.sh"
  require_root
  require_commands

  configure_grub
  configure_update_policy
  configure_network_timeouts
  apply_os_extras
  seed_triveni_home
  fix_permissions
  cleanup_smartcard_overrides
  disable_onetime_service
  configure_timezone
  recompile_icons_and_wallpapers
}

main "$@"
