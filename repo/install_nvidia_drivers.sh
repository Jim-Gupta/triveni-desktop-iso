#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
    echo "Error: Use sudo."
    exit 1
fi

echo "Probing graphics hardware..."
VGA_HARDWARE=$(lspci -nn | grep -E -i "vga|3d" || true)

# ==============================================================================
# CASE 1: NVIDIA CARD DETECTED
# ==============================================================================
if echo "$VGA_HARDWARE" | grep -q -i "nvidia"; then
    echo "NVIDIA hardware found. Launching proprietary deployment stack..."
    
    RECOMMENDED_DRIVER=$(ubuntu-drivers devices 2>/dev/null | grep -i "recommended" | awk '{print $3}' | head -n 1 || true)
    
    if [ -n "$RECOMMENDED_DRIVER" ]; then
        apt-get update
        apt-get install -y "$RECOMMENDED_DRIVER" dkms linux-headers-generic gcc make
        echo "NVIDIA installation complete. Reboot required."
    else
        echo "Fallback: Running generic ubuntu-drivers automation..."
        ubuntu-drivers install
    fi

# ==============================================================================
# CASE 2: AMD CARD DETECTED
# ==============================================================================
elif echo "$VGA_HARDWARE" | grep -q -i "amd"; then
    echo "AMD Radeon hardware found."
    echo "Ensuring open-source video acceleration layers are active offline..."
    
    apt-get update
    # Install the video acceleration wrappers for FFmpeg/GStreamer workflows
    apt-get install -y linux-firmware mesa-va-drivers mesa-vulkan-drivers
    
    echo "AMD configuration complete. Open-source driver stack is active natively."

# ==============================================================================
# CASE 3: INTEL / OTHER BASELINE
# ==============================================================================
else
    echo "Standard Intel or virtual graphics detected. Skipping hardware driver payloads."
fi
