#!/bin/bash

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

readonly APT_OPTS=(-o Dpkg::Use-Pty=0 -o APT::Color=0)
readonly INSTALL_TIMEOUT_SECS=1800

readonly REQUIRED_DEBS=(
  # Other packages
  "dkms"
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
  local before_count
  local -A seen_pkgs=()
  local deduped_pkgs=()

  AVAILABLE_PKGS=()
  MISSING_PKGS=()

  for dep_group in "${REQUIRED_DEBS[@]}"; do
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

  echo "[os-in-target] Available packages: ${#AVAILABLE_PKGS[@]}"
  if [ "$before_count" -ne "${#AVAILABLE_PKGS[@]}" ]; then
    echo "[os-in-target] Pruned duplicate package entries: $((before_count - ${#AVAILABLE_PKGS[@]}))"
  fi
  if [ "${#MISSING_PKGS[@]}" -gt 0 ]; then
    echo "[os-in-target] Skipping missing packages (${#MISSING_PKGS[@]}): ${MISSING_PKGS[*]}"
  fi
}

install_packages_one_by_one() {
  local total=${#AVAILABLE_PKGS[@]}
  local pkg
  local apt_candidate
  local i=0

  [ "$total" -gt 0 ] || {
    echo "[os-in-target] No installable packages found in current repositories"
    return 0
  }

  echo "[os-in-target] Installing $total packages from REQUIRED_DEBS (one at a time)"
  for pkg in "${AVAILABLE_PKGS[@]}"; do
    i=$((i + 1))
    apt_candidate="$(apt-cache policy "$pkg" 2>/dev/null | awk '/Candidate:/ {print $2; exit}')"
    if [ -z "$apt_candidate" ] || [ "$apt_candidate" = "(none)" ]; then
      echo "[os-in-target] Skipping $pkg (no installation candidate)"
      continue
    fi

    echo "[os-in-target] [$i/$total] Installing $pkg"
    if command -v timeout >/dev/null 2>&1; then
      if ! timeout "$INSTALL_TIMEOUT_SECS" apt-get "${APT_OPTS[@]}" install -y --no-install-recommends "$pkg"; then
        echo "[os-in-target] Skipping $pkg (install failed or timed out, continuing)"
      fi
      continue
    fi

    if ! apt-get "${APT_OPTS[@]}" install -y --no-install-recommends "$pkg"; then
      echo "[os-in-target] Skipping $pkg (install failed, continuing)"
    fi
  done
}

finalize_package_state() {
  local audit_out=""

  audit_out="$(dpkg --audit 2>/dev/null || true)"
  if [ -z "$audit_out" ]; then
    echo "[os-in-target] No broken package state detected; skipping fix-broken step"
    return 0
  fi

  echo "[os-in-target] Broken package state detected; running fix-broken install"
  if command -v timeout >/dev/null 2>&1; then
    if ! timeout 600 apt-get "${APT_OPTS[@]}" -y -f install; then
      echo "[os-in-target] fix-broken install failed or timed out; continuing"
    fi
    return 0
  fi

  if ! apt-get "${APT_OPTS[@]}" -y -f install; then
    echo "[os-in-target] fix-broken install failed; continuing"
  fi
}

main() {
  require_root
  require_commands

  echo "**********************************************************************"
  echo "Running os/50-in-target-late-commands.sh"

  if ! apt-get "${APT_OPTS[@]}" update; then
    echo "[os-in-target] Repository update failed. Skipping required package installation."
    return 0
  fi

  filter_available_packages
  install_packages_one_by_one
  finalize_package_state
}

main "$@"