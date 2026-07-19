#!/bin/bash

readonly BACKUP_FILE="/tmp/backup/ssxm_backup.tar.gz"

readonly LOG_FILE="/var/log/triveni-install.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# This script runs in early-commands to back up critical files before the drive is wiped.
echo "Starting SSXM backup process..."

mkdir -p /tmp/old_root
mkdir -p /tmp/backup
mkdir -p "$(dirname "$BACKUP_FILE")"

# Flag to track if we successfully found and backed up the files
BACKUP_SUCCESS=false

# Scan possible partitions to handle USB drive-letter shifting
for part in /dev/sda2 /dev/sdb2 /dev/nvme0n1p2; do
    if mount "$part" /tmp/old_root 2>/dev/null; then
        if [ -f /tmp/old_root/opt/ssxm/.license ]; then
            echo "Target files found on $part. Attempting to create backup archive..."

            backup_root="/tmp/old_root/var/triveni/ssxm"
            backup_items=()

            if [ -d "$backup_root" ]; then
                if [ -f "$backup_root/LicenseFile.lfx" ]; then
                    backup_items+=("LicenseFile.lfx")
                fi
                if [ -d "$backup_root/config" ]; then
                    backup_items+=("config")
                fi
            else
                echo "WARNING: Backup source directory not found: $backup_root"
            fi

            if [ "${#backup_items[@]}" -eq 0 ]; then
                echo "WARNING: No SSXM backup files found to archive on $part"
            elif tar -czf "$BACKUP_FILE" -C "$backup_root" "${backup_items[@]}" 2>&1; then
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
    echo "WARNING: Could not locate or backup SSXM configuration files. Proceeding with clean install."
fi

# CRITICAL: Force an explicit exit 0 so the Ubuntu installer always continues
exit 0