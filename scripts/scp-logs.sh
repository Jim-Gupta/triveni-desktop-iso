#!/bin/bash

# 1. Gather User Inputs with Defaults
read -p "Enter username [triveni]: " USERNAME
USERNAME=${USERNAME:-triveni}

read -p "Enter IP address [10.0.0.25]: " IP_ADDR
IP_ADDR=${IP_ADDR:-10.0.0.25}

read -p "Enter destination directory [/tmp]: " DEST_DIR
DEST_DIR=${DEST_DIR:-/tmp}

# 2. Generate a unique timestamp (Format: YearMonthDay_HourMinuteSecond)
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
ARCHIVE="/tmp/triveni_logs_${TIMESTAMP}.tar.gz"

echo "----------------------------------------"
echo "📦 Bundling /var/log and /var/crash..."
echo "📄 Target: $ARCHIVE"
echo "----------------------------------------"

# Create the compressed tarball (ignoring minor "file changed as we read it" warnings)
sudo tar -czf "$ARCHIVE" /var/log /var/crash 2>/dev/null

if [ ! -f "$ARCHIVE" ] || [ ! -s "$ARCHIVE" ]; then
    echo "❌ Error: Failed to create the log archive."
    exit 1
fi

echo "🚀 Sending archive to ${USERNAME}@${IP_ADDR}:${DEST_DIR} ..."
scp "$ARCHIVE" "${USERNAME}@${IP_ADDR}:${DEST_DIR}"

if [ $? -eq 0 ] ; then
    echo "✅ Transfer completed successfully!"
    # Clean up the local temporary archive from the RAM-disk
    rm -f "$ARCHIVE"
else
    echo "❌ Transfer failed. Check network or credentials."
fi
