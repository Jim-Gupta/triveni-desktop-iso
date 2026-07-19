#!/bin/bash

set -euo pipefail

# Install these component directories first, in the order listed.
readonly PRIORITY_DIRS=("triveni-drivers" "ssxm")

readonly LOG_FILE="/var/log/triveni-install.log"
readonly FIRST_BOOT_ROOT="/var/triveni/install/first-boot"
readonly STAMP_DIR="/var/lib/triveni"
readonly STAMP_FILE="$STAMP_DIR/.first-boot-complete"
readonly SERVICE_NAME="first-boot.service"

notify_status() {
    if command -v systemd-notify >/dev/null 2>&1 && systemd-notify --booted >/dev/null 2>&1; then
        systemd-notify --status="$*" >/dev/null 2>&1 || true
    fi
}

mkdir -p "$STAMP_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "**********************************************************************"
echo "Running first-boot.sh"
echo "[first-boot] Preparing first-boot tasks"
notify_status "Starting first-boot setup"

if [ -f "$STAMP_FILE" ]; then
    echo "[first-boot] First-boot tasks already completed, exiting"
    notify_status "First-boot already complete"
    systemctl disable "$SERVICE_NAME" >/dev/null 2>&1 || true
    exit 0
fi

echo "[first-boot] Scanning for component installers under $FIRST_BOOT_ROOT"
notify_status "Scanning first-boot components"

install_scripts=()
declare -A seen_dirs=()

for dir_name in "${PRIORITY_DIRS[@]}"; do
    priority_script="$FIRST_BOOT_ROOT/$dir_name/install.sh"
    if [ -f "$priority_script" ]; then
        install_scripts+=("$priority_script")
        seen_dirs["$dir_name"]=1
    fi
done

shopt -s nullglob
remaining_candidates=("$FIRST_BOOT_ROOT"/*/install.sh)
shopt -u nullglob

if [ "${#remaining_candidates[@]}" -gt 0 ]; then
    mapfile -t remaining_sorted < <(printf '%s\n' "${remaining_candidates[@]}" | sort)
    for install_script in "${remaining_sorted[@]}"; do
        dir_name="$(basename "$(dirname "$install_script")")"
        if [ -n "${seen_dirs[$dir_name]+x}" ]; then
            continue
        fi
        install_scripts+=("$install_script")
    done
fi

echo "[first-boot] Found ${#install_scripts[@]} component installer(s)"

if [ "${#install_scripts[@]}" -eq 0 ]; then
    echo "[first-boot][warn] No component install.sh files found under $FIRST_BOOT_ROOT"
    notify_status "No component installers found"
else
    total_scripts="${#install_scripts[@]}"
    current_script=0
    for install_script in "${install_scripts[@]}"; do
        current_script=$((current_script + 1))
        component_name="$(basename "$(dirname "$install_script")")"
        echo "[first-boot] Step ${current_script}/${total_scripts}: running $install_script"
        notify_status "Step ${current_script}/${total_scripts}: installing ${component_name}"
        if ! "$install_script" -y; then
            echo "[first-boot][warn] Component install failed: $install_script"
            notify_status "Step ${current_script}/${total_scripts}: ${component_name} failed"
        else
            echo "[first-boot] Step ${current_script}/${total_scripts}: completed $install_script"
            notify_status "Step ${current_script}/${total_scripts}: ${component_name} complete"
        fi
    done
fi

echo "[first-boot] Writing completion stamp"
notify_status "Finalizing first-boot setup"
touch "$STAMP_FILE"
systemctl disable "$SERVICE_NAME" >/dev/null 2>&1 || true

echo "[first-boot] First-boot tasks completed"
notify_status "First-boot complete, rebooting"
echo "[first-boot] Rebooting to finish setup"

if command -v systemd-notify >/dev/null 2>&1 && systemd-notify --booted >/dev/null 2>&1; then
    systemd-notify --ready --status="First-boot complete" >/dev/null 2>&1 || true
fi

reboot

exit 0
