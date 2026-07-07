#!/bin/bash

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

readonly LOG_FILE="/var/log/triveni-install.log"
readonly APT_OPTS=(-o Dpkg::Use-Pty=0 -o APT::Color=0)
readonly INSTALL_TIMEOUT_SECS=1800

mkdir -p /var/log
exec > >(tee -a "$LOG_FILE") 2>&1

on_exit() {
  local rc=$?
  echo "[install-extras] Exit code: $rc at $(date -Is 2>/dev/null || date)"
}
trap on_exit EXIT

echo "**********************************************************************"
echo "Running install-extras-debs.sh (installing extra Debian packages)"
echo "[install-extras] Start time: $(date -Is 2>/dev/null || date)"
echo "[install-extras] Root filesystem source: $(findmnt -n -o SOURCE / 2>/dev/null || echo unknown)"

readonly EXTRA_DEBS=(
  # MT required packages
  "openjdk-8-jre"
  "update-notifier"
  "libva-drm|libva-drm2"
  "libva-x11|libva-x11-2"
  "gir1.2-appindicator3-0.1"

  # XM required packages
  "pcscd"
  "libengine-pkcs11-openssl"
  "opensc"
  "opensc-pkcs11"
  "default-jre-headless|openjdk-21-jre-headless|openjdk-17-jre-headless|openjdk-11-jre-headless|java8-runtime-headless|openjdk-8-jdk-headless|openjdk-8-jre|openjdk-8-jre-headless"
  "libva1|libva2"
  "libva-x11-1|libva-x11-2"
  "libva-drm1|libva-drm2"
  "libvdpau1"
  "libatomic1"

  # Other packages
  "openssh-server"
  "net-tools"
  "netcat-openbsd|netcat-traditional|netcat"
  "iputils-ping"
  "traceroute"
  "curl"
  "wget"
  "unzip"
  "zip"
  "p7zip-full"
  "ffmpeg"
  "libavcodec-dev"
  "libavformat-dev"
  "libavutil-dev"
  "libswscale-dev"
  "vlc"
  "libvlc-dev"
  "vlc-plugin-base"
  "vlc-plugin-video-output"
)


require_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "This script must run as root" >&2
    exit 1
  fi
}

require_commands() {
  local cmd
  for cmd in apt-get apt-cache; do
    command -v "$cmd" >/dev/null 2>&1 || {
      echo "Missing required command: $cmd" >&2
      exit 1
    }
  done
}

resolve_alternative() {
  local group="$1"
  local candidate
  local apt_candidate

  IFS='|' read -r -a candidates <<< "$group"
  for candidate in "${candidates[@]}"; do
    candidate="$(echo "$candidate" | xargs)"
    [ -n "$candidate" ] || continue

    apt_candidate="$(apt-cache policy "$candidate" 2>/dev/null | awk '/Candidate:/ {print $2; exit}')"
    if [ -n "$apt_candidate" ] && [ "$apt_candidate" != "(none)" ]; then
      echo "$candidate"
      return 0
    fi
  done

  return 1
}

filter_available_packages() {
  local dep_group
  local resolved
  local pkg
  local -A seen_pkgs=()
  local deduped_pkgs=()
  local before_count
  AVAILABLE_PKGS=()
  MISSING_PKGS=()

  for dep_group in "${EXTRA_DEBS[@]}"; do
    if resolved=$(resolve_alternative "$dep_group"); then
      AVAILABLE_PKGS+=("$resolved")
    else
      MISSING_PKGS+=("$dep_group")
    fi
  done

  before_count=${#AVAILABLE_PKGS[@]}
  for pkg in "${AVAILABLE_PKGS[@]}"; do
    [ -n "$pkg" ] || continue
    if [ -z "${seen_pkgs[$pkg]+x}" ]; then
      seen_pkgs[$pkg]=1
      deduped_pkgs+=("$pkg")
    fi
  done
  AVAILABLE_PKGS=("${deduped_pkgs[@]}")

  echo "[install-extras] Available packages: ${#AVAILABLE_PKGS[@]}"
  if [ "$before_count" -ne "${#AVAILABLE_PKGS[@]}" ]; then
    echo "[install-extras] Pruned duplicate package entries: $((before_count - ${#AVAILABLE_PKGS[@]}))"
  fi
  if [ "${#MISSING_PKGS[@]}" -gt 0 ]; then
    echo "[install-extras] Skipping missing packages (${#MISSING_PKGS[@]}): ${MISSING_PKGS[*]}"
  fi
}

install_packages_one_by_one() {
  local total=${#AVAILABLE_PKGS[@]}
  local pkg
  local apt_candidate
  local i=0

  [ "$total" -gt 0 ] || {
    echo "[install-extras] No installable packages found in current repositories"
    return
  }

  echo "[install-extras] Installing $total online packages from EXTRA_DEBS (one at a time)"
  for pkg in "${AVAILABLE_PKGS[@]}"; do
    i=$((i + 1))
    apt_candidate="$(apt-cache policy "$pkg" 2>/dev/null | awk '/Candidate:/ {print $2; exit}')"
    if [ -z "$apt_candidate" ] || [ "$apt_candidate" = "(none)" ]; then
      echo "[install-extras] Skipping $pkg (no installation candidate)"
      continue
    fi

    echo "[install-extras] [$i/$total] Installing $pkg"
    if command -v timeout >/dev/null 2>&1; then
      if ! timeout "$INSTALL_TIMEOUT_SECS" apt-get "${APT_OPTS[@]}" install -y --no-install-recommends "$pkg"; then
        echo "[install-extras] Skipping $pkg (install failed or timed out, continuing)"
      fi
      continue
    fi

    if ! apt-get "${APT_OPTS[@]}" install -y --no-install-recommends "$pkg"; then
      echo "[install-extras] Skipping $pkg (install failed, continuing)"
    fi
  done
}

finalize_package_state() {
  local audit_out=""

  audit_out="$(dpkg --audit 2>/dev/null || true)"
  if [ -z "$audit_out" ]; then
    echo "[install-extras] No broken package state detected; skipping fix-broken step"
    return 0
  fi

  echo "[install-extras] Broken package state detected; running fix-broken install"
  if command -v timeout >/dev/null 2>&1; then
    if ! timeout 600 apt-get "${APT_OPTS[@]}" -y -f install; then
      echo "[install-extras] fix-broken install failed or timed out; continuing"
    fi
    return 0
  fi

  if ! apt-get "${APT_OPTS[@]}" -y -f install; then
    echo "[install-extras] fix-broken install failed; continuing"
  fi
}

install_chrome_browser() {
  wget -P /tmp https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
  apt-get install -y /tmp/google-chrome-stable_current_amd64.deb
  rm /tmp/google-chrome-stable_current_amd64.deb
}

main() {
  require_root
  require_commands

  echo "[install-extras] uname -r: $(uname -r 2>/dev/null || echo unknown)"

  if ! apt-get "${APT_OPTS[@]}" update; then
    echo "[install-extras] Repository update failed (network/DNS unavailable). Skipping extra package installation."
    return 0
  fi
  filter_available_packages
  install_packages_one_by_one
  finalize_package_state
  install_chrome_browser
  echo "[install-extras] Completed at: $(date -Is 2>/dev/null || date)"
  exit 0
}

main "$@"
