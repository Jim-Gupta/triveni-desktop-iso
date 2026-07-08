#!/bin/bash
readonly LOG_FILE="/var/log/triveni-install.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# This script runs in early-commands to back up critical files before the drive is wiped.
echo "Starting SSMT backup process..."

mkdir -p /tmp/old_root
mkdir -p /tmp/backup

# Flag to track if we successfully found and backed up the files
BACKUP_SUCCESS=false

# Scan possible partitions to handle USB drive-letter shifting
for part in /dev/sda2 /dev/sdb2 /dev/nvme0n1p2; do
    if mount "$part" /tmp/old_root 2>/dev/null; then
        if [ -f /tmp/old_root/opt/ssmt/.license ]; then
            echo "Target files found on $part. Attempting to create backup archive..."
            
            # tar might throw a warning/error if 'config' is empty or missing files. 
            # We append '|| true' so a tar error doesn't crash the script execution loop.
            if tar -czf /tmp/backup/ssmt_backup.tar.gz -C /tmp/old_root/opt/ssmt .license config 2>&1; then
                echo "Backup archive created successfully."
                BACKUP_SUCCESS=true
            else
                echo "WARNING: Tar command encountered an error, but continuing installation anyway."
            fi
            
            # Lazy unmount just in case the device is busy, ensuring we don't lock the drive
            umount -l /tmp/old_root || true
            break
        fi
        umount -l /tmp/old_root || true
    fi
done

if [ "$BACKUP_SUCCESS" = false ]; then
    echo "WARNING: Could not locate or backup SSMT configuration files. Proceeding with clean install."
fi

# CRITICAL: Force an explicit exit 0 so the Ubuntu installer always continues
exit 0