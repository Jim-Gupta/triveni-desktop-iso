#!/bin/bash

trap 'exit 0' EXIT
set -e

readonly ROOT_DIR="/var/triveni/install"

export DEBIAN_FRONTEND=noninteractive
readonly LOG_FILE="/var/log/triveni-install.log"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "**********************************************************************"
echo "Running install-ssmt.sh (installing SSMT from /var/triveni/install/ssmt_*.deb if present)"

# Check if the script is running as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: Please run this script as root."
    exit 1
fi

# Install only the last matching local SSMT package in ROOT_DIR, if /opt/ssmt exists.
shopt -s nullglob
ssmt_debs=("$ROOT_DIR"/ssmt_*.deb)
if [ "${#ssmt_debs[@]}" -gt 0 ]; then

    # Install ssmt dev and all associated dependencies, including Java 8 runtime
    apt install -y openjdk-8-jre
    update-alternatives --set java /usr/lib/jvm/java-8-openjdk-amd64/jre/bin/java
    
    latest_ssmt="${ssmt_debs[$(( ${#ssmt_debs[@]} - 1 ))]}"
    echo "Found SSMT debs in ${ROOT_DIR}: ${ssmt_debs[*]}. Installing latest: ${latest_ssmt}"
    dpkg -i "$latest_ssmt"
    chown 1000:1000 /opt/ssmt

    # Configure MT web UI on port 8080 if /opt/ssxm exists
    if [ -d "/opt/ssxm" ]; then
        echo "configuring MT web UI on port 8080"
        echo "com.triveni.jnlp.port=8080" > /opt/ssmt/server/server.properties
        chmod a+r /opt/ssmt/server/server.properties
    fi

    # Restore SSMT configuration and license from backup if present
    if [ -f /tmp/ssmt_backup.tar.gz ]; then
        echo "Restoring ssmt configuration and license to target system..."
        mkdir -p /opt/ssmt
        
        # Extract archive directly into /opt/ssmt (removed the /target prefix)
        tar -xzf /tmp/ssmt_backup.tar.gz -C /opt/ssmt/
        chown -R 1000:1000 /opt/ssmt
        
        # Clean up the temporary backup archive inside the target
        rm -f /tmp/ssmt_backup.tar.gz
    else
        echo "WARNING: Backup archive was not found in /tmp! Proceeding with clean install setup."
    fi
else
    echo "Skipping SSMT install: no matching SSMT deb in ${ROOT_DIR}."
fi

exit 0
