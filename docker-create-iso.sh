#!/bin/bash

# This script builds a Docker image and runs a container to create a Triveni Digital System ISO.
# This is used to debug and test the ISO creation process in a controlled environment.
# Best to run this script inside wsl2.  Otherwise it takes like 10 minutes to run because of the 
# slow file system access on Windows.

set -e

# ==========================================
# Define Variables (Native Linux Paths)
# ==========================================
IMAGE_NAME="triveni-desktop-iso:latest"

# Everything lives locally inside the native Linux VHDX now
HOST_MOUNT_DIR="/home/triveni/docker-mount"
HOST_WORKSPACE_DIR="$(pwd)"

CONTAINER_USER_CONTENT="/mnt/userContent"
CONT_BASE_ISO="${CONTAINER_USER_CONTENT}/ubuntu-24.04-desktop-amd64.iso"
CONT_DRIVERS_DIR="${CONTAINER_USER_CONTENT}/triveni-drivers"
CONT_SSMT_DIR="${CONTAINER_USER_CONTENT}/mt"
CONT_SSXM_DIR="${CONTAINER_USER_CONTENT}/xm"
# ==========================================

echo "🐳 Building Docker image..."
docker build -f Dockerfile -t "$IMAGE_NAME" .

echo "🚀 Running ISO generator container..."
docker run --rm \
  -v "${HOST_MOUNT_DIR}:${CONTAINER_USER_CONTENT}" \
  -v "${HOST_WORKSPACE_DIR}:/workspace" \
  -e BASE_ISO_FILE="$CONT_BASE_ISO" \
  -e SSMT_DEB_DIR="$CONT_SSMT_DIR" \
  -e SSXM_DEB_DIR="$CONT_SSXM_DIR" \
  -e DRIVERS_DIR="$CONT_DRIVERS_DIR" \
  "$IMAGE_NAME" \
  sh -c "ant -DBASE_ISO_FILE=\$BASE_ISO_FILE -DDRIVERS_DIR=\$DRIVERS_DIR -DSSMT_DEB_DIR=\$SSMT_DEB_DIR -DSSXM_DEB_DIR=\$SSXM_DEB_DIR"

./docker-run-iso.sh -d
