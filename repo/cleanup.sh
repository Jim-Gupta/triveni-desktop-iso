#!/bin/bash

# Calculate total size in bytes
repo_bytes=$(sudo du -sb /var/triveni/iso/repo.tgz 2>/dev/null | cut -f1)
repository_bytes=$(sudo du -sb /var/triveni/repository 2>/dev/null | cut -f1)
total_bytes=$((repo_bytes + repository_bytes))
total_mgb=$((total_bytes / 1024 / 1024 / 1024))

# Ask user for confirmation
echo "This script will cleanup the repository and iso image and free up approximately ${total_mgb} GB of space."
echo "This action cannot be undone."
echo "Commands to execute:"
echo "    sudo rm -f /var/triveni/iso/repo.tgz"
echo "    sudo rm -rf /var/triveni/repository"
read -p "Do you want to cleanup? (y/n): " response

# Check user response
if [[ "$response" != "y" && "$response" != "Y" ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

sudo rm -f /var/triveni/iso/repo.tgz
sudo rm -rf /var/triveni/repository

echo "Cleanup completed successfully."
