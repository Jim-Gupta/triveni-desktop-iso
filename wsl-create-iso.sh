#!/bin/bash

set -e

HOST_MOUNT_DIR="/home/triveni/docker-mount"
BASE_ISO="${HOST_MOUNT_DIR}/ubuntu-24.04-desktop-amd64.iso"
DRIVERS_DIR="${HOST_MOUNT_DIR}/triveni-drivers"
SSMT_DIR="${HOST_MOUNT_DIR}/mt"
SSXM_DIR="${HOST_MOUNT_DIR}/xm"

./create-install-iso.sh -i "$BASE_ISO" \
  -d "$DRIVERS_DIR" \
  -m "$SSMT_DIR" \
  -x "$SSXM_DIR"

./qemu-run-iso.sh -d
