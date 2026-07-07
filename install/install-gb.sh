#!/bin/bash

trap 'exit 0' EXIT
set -e

readonly ROOT_DIR="/var/triveni/install"

export DEBIAN_FRONTEND=noninteractive
readonly LOG_FILE="/var/log/triveni-install.log"

exec > >(tee -a "$LOG_FILE") 2>&1
echo "**********************************************************************"
echo "Running install-gb.sh (installing GB from /var/triveni/install/gb_*.deb if present)"

# Check if the script is running as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: Please run this script as root."
    exit 1
fi

# Install only the last matching local GB package in ROOT_DIR, if /opt/gb exists.
shopt -s nullglob
gb_debs=("$ROOT_DIR"/gb_*.deb)
if [ "${#gb_debs[@]}" -gt 0 ]; then
    latest_gb="${gb_debs[$(( ${#gb_debs[@]} - 1 ))]}"
    echo "Found GB debs in ${ROOT_DIR}: ${gb_debs[*]}. Installing latest: ${latest_gb}"
    dpkg -i "$latest_gb"
else
    echo "Skipping GB install: no matching GB deb in ${ROOT_DIR}."
fi

exit 0
