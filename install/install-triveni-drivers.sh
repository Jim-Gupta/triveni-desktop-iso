#!/bin/bash

trap 'exit 0' EXIT
set -e

readonly ROOT_DIR="/var/triveni/install"

export DEBIAN_FRONTEND=noninteractive
readonly LOG_FILE="/var/log/triveni-install.log"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "**********************************************************************"
echo "Running install-triveni-drivers.sh (installing Triveni drivers from /var/triveni/install/drivers_*_amd64.zip if present)"


# Check if the script is running as root
if [ "$EUID" -ne 0 ]; then
  echo "Error: Please run this script as root."
  exit 1
fi

# Install only the last matching local SSXM package in ROOT_DIR, if /opt/ssxm exists.
shopt -s nullglob
drivers_zip=("$ROOT_DIR"/drivers_*_amd64.zip)
if [ "${#drivers_zip[@]}" -gt 0 ]; then
  latest_driver="${drivers_zip[$(( ${#drivers_zip[@]} - 1 ))]}"
  echo "Found triveni drivers in ${ROOT_DIR}: ${drivers_zip[*]}. Installing latest: ${latest_driver}"
  unzip "$latest_driver" -d "$ROOT_DIR"
  chmod +x "$ROOT_DIR"/drivers/*.sh
  if [ -x "$ROOT_DIR"/drivers/install-drivers.sh ]; then
    "$ROOT_DIR"/drivers/auto-install.sh -y || true
  else
    echo "install-drivers.sh not found or not executable"
  fi
else
  echo "Skipping triveni drivers install: no matching triveni drivers in ${ROOT_DIR}."
fi

exit 0
