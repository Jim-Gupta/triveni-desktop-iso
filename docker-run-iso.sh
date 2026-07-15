#!/bin/bash

# This script runs the Triveni Digital System ISO in a QEMU virtual machine with hardware acceleration.
# The docker-create-iso.sh script calls this script right after running with the -d option, which forces 
# the deletion of any existing virtual hard drive and creates a new one.

set -e

# ==========================================
# Configuration Variables
# ==========================================
VHD_IMAGE="triveni-test-vm.qcow2"
VHD_DISKSIZE="200G"
VHD_CPUS=4
VHD_MEMORY=16384
FORCE_DELETE=false
DISABLE_NETWORK=false

# ==========================================
# Argument Parsing (Catches the -d and -n flags)
# ==========================================
while getopts "dn" opt; do
    case ${opt} in
        d )
            FORCE_DELETE=true
            ;;
        n )
            DISABLE_NETWORK=true
            ;;
        \? )
            echo "Usage: $0 [-d] [-n]"
            exit 1
            ;;
    esac
done

# ==========================================
# 1. Locate the Compiled ISO
# ==========================================
echo "🔍 Searching for the compiled installation ISO..."

shopt -s nullglob
ISOS=("dist"/*.iso)
shopt -u nullglob

if [ ${#ISOS[@]} -eq 0 ]; then
    echo "❌ Error: No ISO file found inside the dist/ folder!"
    exit 1
fi

# Pick the single most recently generated ISO file by modification time
TARGET_ISO=$(ls -t dist/*.iso | head -n 1)
echo "🎯 Target ISO identified: $TARGET_ISO"

# ==========================================
# 2. Virtual Hard Drive Lifecycle Management
# ==========================================
create_fresh_vhd() {
    echo "🗑️ Clearing old disk states..."
    rm -f "$VHD_IMAGE"
    echo "💽 Allocating a fresh $VHD_DISKSIZE virtual hard drive ($VHD_IMAGE)..."
    qemu-img create -f qcow2 "$VHD_IMAGE" "$VHD_DISKSIZE"
}

if [ -f "$VHD_IMAGE" ]; then
    if [ "$FORCE_DELETE" = true ]; then
        echo "⚡ '-d' flag detected. Bypassing prompt..."
        create_fresh_vhd
    fi
else
    echo "💽 Virtual drive not found."
    create_fresh_vhd
fi

# ==========================================
# 3. Boot the Hardware-Accelerated Instance
# ==========================================
echo "🖥️ Booting QEMU Instance on your Ryzen 7950X..."
echo "💡 Note: To release mouse focus back to Windows, press Ctrl+Alt"

if [ "$DISABLE_NETWORK" = true ]; then
        echo "🌐 Network devices disabled for this run (-n)"
fi

echo "💡💡💡 Enable clipboard integration via the SPICE agent for better copy-paste support."
echo "sudo apt install -y spice-vdagent"
echo "sudo systemctl enable --now spice-vdagentd"

qemu_cmd=(
    qemu-system-x86_64
    -enable-kvm
    -cpu host
    -smp "$VHD_CPUS"
    -m "$VHD_MEMORY"
    -drive file="$VHD_IMAGE",if=virtio,cache=writeback
    -cdrom "$TARGET_ISO"
    -device virtio-vga,xres=1024,yres=768
    -display gtk,zoom-to-fit=on
    -chardev qemu-vdagent,id=ch1,name=vdagent,clipboard=on
    -device virtio-serial-pci
    -device virtserialport,chardev=ch1,id=ch1,name=com.redhat.spice.0
)

if [ "$DISABLE_NETWORK" = false ]; then
        qemu_cmd+=(
            -netdev user,id=net0,net=10.0.2.0/24
            -device virtio-net-pci,netdev=net0,mac=52:54:00:12:34:56
            -netdev user,id=net1,net=192.168.2.10/24
            -device virtio-net-pci,netdev=net1,mac=52:54:00:12:34:57
            -netdev user,id=net2,net=192.168.2.20/24
            -device virtio-net-pci,netdev=net2,mac=52:54:00:12:34:58
            -netdev user,id=net3,net=192.168.2.30/24
            -device virtio-net-pci,netdev=net3,mac=52:54:00:12:34:59
        )
fi

"${qemu_cmd[@]}"
