#!/bin/bash

########################################################################################################################
# Script: create_repo.sh
# Description: Creates an offline APT repository by downloading all currently installed packages and their dependencies.
#              The resulting repository is then zipped for easy transfer.
# Usage: Install SSXM or SSMT or COMBO ISO on a machine, then run this script and it will create tar.gz file with all
#              the packages in the repository. Dowload the tar.gz file to your local machine and use it in the ISO 
#              creation process.
#              It is advisable to run the script in /var/triveni/tmp directory to avoid filling up the disk.
########################################################################################################################

set -e

readonly BASE_DIR="$(pwd)"
readonly OUTPUT_DIR="$BASE_DIR/repo"
readonly CACHE_DIR="$BASE_DIR/cache"
readonly CURRENT_DATE=$(date +%Y-%m-%d)

# ==============================================================================
# INDIVIDUAL DEPENDENCY GROUPS
# ==============================================================================
readonly APPLICATION_DEPENDENCIES="openjdk-8-jre update-notifier libva-drm2 libva-x11-2 pcscd libengine-pkcs11-openssl opensc opensc-pkcs11 libva2 libvdpau1 libatomic1"
readonly TOOLS_DEPENDENCIES="vlc ffmpeg tcpdump net-tools"
readonly BUILD_DEPENDENCIES="dpkg-repack fakeroot"
readonly X11VNC_DEPENDENCIES="x11vnc"
readonly REMOTE_DESKTOP_DEPENDENCIES="$X11VNC_DEPENDENCIES"

# Optional other remote desktops
# readonly DESKTOP_DEPENDENCIES="ubuntu-desktop-minimal gdm3"
# readonly XRDP_DEPENDENCIES="xrdp xorgxrdp"
# readonly TIGERVNC_DEPENDENCIES="tigervnc-standalone-server tigervnc-tools tigervnc-common tigervnc-scraping-server"

# *** AMD Dependencies... never tested ***
# readonly AMD_DEPENDENCIES="linux-firmware mesa-va-drivers mesa-vulkan-drivers libva-amdgpu-helper"

# **** Including the nvidia dependencies stop the GDM from working.  Not sure why. ****
# readonly NVIDIA_COREer-470 nvidia-driver-470-server"
# readonly NVIDIA_535="nvidia-driver-535 nvidia-driver-535-server nvidia-driver-535-open"
# readonly NVIDIA_550="nvidia-driver-550"
# readonly NVIDIA_570="nvidia-driver-570 nvidia-driver-570-open"
# readonly NVIDIA_580="nvidia-driver-580 nvidia-driver-580-open"
# readonly NVIDIA_590="nvidia-driver-590 nvidia-driver-590-open"
readonly NVIDI_DEPENDENCIES="$NVIDIA_CORE $NVIDIA_470 $NVIDIA_535 $NVIDIA_550 $NVIDIA_570 $NVIDIA_580 $NVIDIA_590"

# ==============================================================================
# MASTER COMBINED PACKAGE MATRIX
# ==============================================================================
readonly OFFLINE_PACKAGES="
    $DESKTOP_DEPENDENCIES
    $APPLICATION_DEPENDENCIES
    $TOOLS_DEPENDENCIES
    $BUILD_DEPENDENCIES
    $REMOTE_DESKTOP_DEPENDENCIES
    $NVIDIA_DEPENDENCIES
    $AMD_DEPENDENCIES
"

function init() {
    echo "Step 1: Preparing directories and caching mechanism..."
    
    # Ensure the cache directory exists
    mkdir -p "$CACHE_DIR"

    # If a previous repo exists, move all its deb packages into the cache, then destroy the old repo
    if [ -d "$OUTPUT_DIR" ]; then
        echo " -> Moving previous repository files to cache to prevent stale package bloat..."
        mv -n "$OUTPUT_DIR"/*.deb "$CACHE_DIR/" 2>/dev/null || true
        rm -rf "$OUTPUT_DIR"
    fi

    # Create a fresh, empty repository structure
    mkdir -p "$OUTPUT_DIR/partial"

    echo " -> Cleaning local APT cache to ensure a fresh pull..."
    sudo mv /etc/apt/sources.list.d/triveni*.list /tmp/ 2>/dev/null || true

    if [ -f /etc/apt/sources.list.d/ubuntu.sources.curtin.orig ]; then
        sudo cp /etc/apt/sources.list.d/ubuntu.sources.curtin.orig /etc/apt/sources.list.d/ubuntu.sources
    else
        echo "Warning: /etc/apt/sources.list.d/ubuntu.sources.curtin.orig not found — skipping copy."
    fi

    rm -f "$BASE_DIR/download_errors.log"
    touch "$BASE_DIR/download_errors.log"
}

function fixGdm3Pam() {
    # --- GDM3 PAM WORKAROUND ---
    echo "Applying gdm3 PAM configuration workaround..."
    sudo rm -f /etc/pam.d/gdm-smartcard /etc/pam.d/gdm-fingerprint /etc/pam.d/gdm-password /etc/pam.d/gdm-autologin
    sudo touch /etc/pam.d/gdm-smartcard-sssd-exclusive
    sudo touch /etc/pam.d/gdm-smartcard-sssd-or-password
    sudo touch /etc/pam.d/gdm-smartcard-pkcs11-exclusive
}

function updateSystem() {
    sudo apt-get clean
    sudo apt-get update
    sudo apt-get --fix-broken install -y
    sudo apt-get dist-upgrade -y
    sudo apt-get --fix-broken install -y

    dpkg -l | grep '^rc' | awk '{print $2}' | xargs -r sudo dpkg --purge
}


function downloadInstalledPackages() {
    sudo chown _apt:root "$OUTPUT_DIR"
    sudo chmod 777 "$OUTPUT_DIR"

    cd "$OUTPUT_DIR" || exit

    echo "Step 2: Scanning installed system packages..."
    dpkg-query -W -f='${binary:Package}\n' | while read -r pkg; do
        
        # 1. OPTIMIZATION: Check if it was already processed into the new repo directory
        if ls "$OUTPUT_DIR"/${pkg}_*.deb >/dev/null 2>&1; then
            # Silent skip to prevent terminal spam for installed overlapping packages
            continue
        fi

        # 2. Check cache: Grab the newest cached file
        CACHED_FILE=$(ls -1v "$CACHE_DIR"/${pkg}_*.deb 2>/dev/null | tail -n 1 || true)
        
        if [ -n "$CACHED_FILE" ]; then
            echo " -> $pkg found in cache. Copying to repo..."
            ln "$CACHED_FILE" "$OUTPUT_DIR/" 2>/dev/null || cp -n "$CACHED_FILE" "$OUTPUT_DIR/" || sudo cp -n "$CACHED_FILE" "$OUTPUT_DIR/"
            continue
        fi

        echo "Processing: $pkg"
        if ! sudo apt-get download -o dir::cache::archives="$OUTPUT_DIR" "$pkg" 2>> "$BASE_DIR/download_errors.log"; then
            echo " -> Download failed. Re-packing custom package directly from system..."
            sudo fakeroot dpkg-repack "$pkg" 2>> "$BASE_DIR/download_errors.log"
        fi
    done
}

function downloadUninstalledPackages() {
    local pkgs="$1"
    if [ -z "$pkgs" ]; then return 0; fi
    
    cd "$OUTPUT_DIR" || exit
    echo " -> Resolving dependencies for uninstalled targets..."
    
    local all_pkgs
    all_pkgs=$( { echo "$pkgs" | tr ' ' '\n'; \
                  apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts --no-breaks --no-replaces --no-enhances $pkgs | \
                  grep "^\s*Depends:" | awk '{print $2}' | grep -v "<"; } | sort -u )

    for pkg in $all_pkgs; do
        if [ -z "$pkg" ]; then continue; fi
        
        # 1. Is it already in the repo from Step 2? (This prevents the Permission Denied crash)
        if ls "$OUTPUT_DIR"/${pkg}_*.deb >/dev/null 2>&1; then
            echo " -> Dependency $pkg is already in the repo, skipping."
            continue
        fi
        
        # 2. Check cache: Grab the newest cached file
        CACHED_FILE=$(ls -1v "$CACHE_DIR"/${pkg}_*.deb 2>/dev/null | tail -n 1 || true)
        
        if [ -n "$CACHED_FILE" ]; then
            echo " -> Dependency $pkg found in cache. Copying to repo..."
            ln "$CACHED_FILE" "$OUTPUT_DIR/" 2>/dev/null || cp -n "$CACHED_FILE" "$OUTPUT_DIR/" || sudo cp -n "$CACHED_FILE" "$OUTPUT_DIR/"
        else
            echo " -> Downloading dependency: $pkg"
            sudo apt-get download -o dir::cache::archives="$OUTPUT_DIR" "$pkg" 2>> "$BASE_DIR/download_errors.log" || true
        fi
    done
}

function finalizeRepository() {
    sudo chown -R $USER:$USER "$OUTPUT_DIR"

    mv "$BASE_DIR/download_errors.log" "$OUTPUT_DIR/download_errors.log"

    cd "$OUTPUT_DIR" || exit
    rm -rf partial/
    rm -rf lock

    sudo apt-get install dpkg-dev -y
    echo "Creating scanpackages... this will take a couple mins"
    dpkg-scanpackages . /dev/null | gzip -9c > Packages.gz

    ls -lh > "manifest_$(uname -r).txt"

    echo "Step 4: Creating an archive of your offline repository..."
    cd "$BASE_DIR" || exit
}

function createArchive() {
    tar -czf "repo.tgz" -C "$BASE_DIR" "$(basename "$OUTPUT_DIR")"

    echo "Done! You have $(ls -1 "$OUTPUT_DIR"/*.deb 2>/dev/null | wc -l) packages ready for the ISO."
    echo "Your archive is saved as: repo.tgz"
}

# ==============================================================================
# PIPELINE EXECUTION FLOW
# ==============================================================================
init
fixGdm3Pam
updateSystem

echo "Installing local system repackaging prerequisites..."
sudo apt-get install -y $BUILD_DEPENDENCIES

downloadInstalledPackages
downloadUninstalledPackages "$OFFLINE_PACKAGES"

finalizeRepository
createArchive

echo "Repository creation process completed successfully!"
