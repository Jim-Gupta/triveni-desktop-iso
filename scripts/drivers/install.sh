#!/bin/bash

trap 'exit 0' EXIT
set -e

readonly ROOT_DIR="/var/triveni/install/drivers"

export DEBIAN_FRONTEND=noninteractive
readonly LOG_FILE="/var/log/triveni-install.log"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "**********************************************************************"
echo "Running drivers/install.sh (installing Triveni drivers from /var/triveni/install/drivers/ if present)"


# Check if the script is running as root
if [ "$EUID" -ne 0 ]; then
  echo "Error: Please run this script as root."
  exit 1
fi

readonly INSTALL_SCRIPT="install-drivers.sh"
shopt -s nullglob
if [ -x "$ROOT_DIR/$INSTALL_SCRIPT" ]; then
  "$ROOT_DIR/$INSTALL_SCRIPT" -y || true
else
  echo "$INSTALL_SCRIPT not found or not executable"
fi
exit 0
