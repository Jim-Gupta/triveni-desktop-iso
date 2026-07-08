#!/bin/bash

trap 'exit 0' EXIT
set -e

readonly ROOT_DIR="/var/triveni/install"

export DEBIAN_FRONTEND=noninteractive
readonly LOG_FILE="/var/log/triveni-install.log"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "**********************************************************************"
echo "Running install-ssxm.sh (installing SSXM from /var/triveni/install/ssxm_*.deb if present)"

# Check if the script is running as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: Please run this script as root."
    exit 1
fi

# Install only the last matching local SSXM package in ROOT_DIR, if /opt/ssxm exists.
shopt -s nullglob
ssxm_debs=("$ROOT_DIR"/ssxm_*.deb)
if [ "${#ssxm_debs[@]}" -gt 0 ]; then
    latest_ssxm="${ssxm_debs[$(( ${#ssxm_debs[@]} - 1 ))]}"
    echo "Found SSXM debs in ${ROOT_DIR}: ${ssxm_debs[*]}. Installing latest: ${latest_ssxm}"
    dpkg -i "$latest_ssxm"
else
    echo "Skipping SSXM install: no matching SSXM deb in ${ROOT_DIR}."
fi

exit 0
