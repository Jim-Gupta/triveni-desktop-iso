#!/bin/bash

set -euo pipefail

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root. Please use sudo."
    exit 1
fi


export DEBIAN_FRONTEND=noninteractive

readonly LOG_FILE="/var/log/triveni-install.log"
readonly LOCAL_CHROME_DIR="/var/triveni/install"
readonly CHROME_DEB_URL="https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb"
readonly CHROME_DEB_PATH="/tmp/google-chrome-stable_current_amd64.deb"
readonly MAX_ATTEMPTS=3
readonly RETRY_DELAY_SECS=20

mkdir -p /var/log
exec > >(tee -a "$LOG_FILE") 2>&1

echo "**********************************************************************"
echo "Running install-chrome.sh"

require_commands() {
	local cmd
	for cmd in apt-get dpkg; do
		command -v "$cmd" >/dev/null 2>&1 || {
			echo "Missing required command: $cmd" >&2
			exit 1
		}
	done
}

find_local_chrome_deb() {
	local -a local_debs=()

	shopt -s nullglob
	local_debs=("$LOCAL_CHROME_DIR"/google-chrome*.deb)
	shopt -u nullglob

	if [ "${#local_debs[@]}" -gt 0 ]; then
		echo "${local_debs[0]}"
		return 0
	fi

	return 1
}

download_chrome_deb() {
	local attempt
	if ! command -v wget >/dev/null 2>&1; then
		echo "[install-chrome] wget not found, cannot download Chrome package"
		return 1
	fi

	for attempt in $(seq 1 "$MAX_ATTEMPTS"); do
		echo "[install-chrome] Download attempt $attempt/$MAX_ATTEMPTS"
		if wget --inet4-only --no-check-certificate --tries=3 --timeout=30 -O "$CHROME_DEB_PATH" "$CHROME_DEB_URL"; then
			return 0
		fi
		echo "[install-chrome] Download failed"
		rm -f "$CHROME_DEB_PATH"
		if [ "$attempt" -lt "$MAX_ATTEMPTS" ]; then
			sleep "$RETRY_DELAY_SECS"
		fi
	done
	return 1
}

disable_chrome_repo_sources() {
	# google-chrome postinst may add a dl.google.com apt source; disable it
	# so subsequent installer apt updates do not depend on that host.
	rm -f /etc/apt/sources.list.d/google-chrome.list
	rm -f /etc/apt/sources.list.d/google-chrome.sources
}

main() {
	require_commands

	if dpkg -s google-chrome-stable >/dev/null 2>&1; then
		echo "[install-chrome] Google Chrome already installed"
		exit 0
	fi

	if local_deb=$(find_local_chrome_deb); then
		echo "[install-chrome] Installing Chrome from local package: $local_deb"
		if apt-get -o Dpkg::Use-Pty=0 -o APT::Color=0 install -y "$local_deb"; then
			disable_chrome_repo_sources
			echo "[install-chrome] Google Chrome installed successfully from local package"
			exit 0
		fi
		echo "[install-chrome] Local Chrome package install failed"
		exit 1
	fi

	echo "[install-chrome] Local Chrome package not found in $LOCAL_CHROME_DIR, falling back to download"
	if ! download_chrome_deb; then
		echo "[install-chrome] Could not download Chrome"
		exit 1
	fi

	if apt-get -o Dpkg::Use-Pty=0 -o APT::Color=0 install -y "$CHROME_DEB_PATH"; then
		rm -f "$CHROME_DEB_PATH"
		disable_chrome_repo_sources
		echo "[install-chrome] Google Chrome installed successfully"
		exit 0
	fi

	rm -f "$CHROME_DEB_PATH"
	echo "[install-chrome] Chrome install failed"
	exit 1
}

main "$@"