#!/bin/bash

set -u

LOG_FILE="/var/log/triveni-install.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "Starting product backup scan..."

shopt -s nullglob
backup_scripts=(/cdrom/scripts/*/backup.sh /cdrom/scripts/first-boot/*/backup.sh)
shopt -u nullglob

if [ "${#backup_scripts[@]}" -eq 0 ]; then
	echo "No backup.sh scripts found under /cdrom/scripts/."
	exit 0
fi

for backup_script in "${backup_scripts[@]}"; do
	echo "Running backup script: $backup_script"
	if "$backup_script"; then
		echo "Backup script succeeded: $backup_script"
	else
		echo "WARNING: Backup script failed: $backup_script"
	fi
done

echo "Completed product backup scan."
exit 0
