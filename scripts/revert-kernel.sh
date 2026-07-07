#!/bin/bash

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

readonly KERNEL_DIR="/tmp/resources/kernel-6.8"
readonly KERNEL_PIN_FILE="/etc/apt/preferences.d/99-kernel-6.8-only.pref"
readonly LOG_FILE="/var/log/triveni-install.log"
readonly APT_OPTS=(-o Dpkg::Use-Pty=0 -o APT::Color=0)

mkdir -p /var/log
exec > >(tee -a "$LOG_FILE") 2>&1

echo "**********************************************************************"
echo "Running revert-kernel.sh (enforce 6.8.x kernel)"

log() {
	echo "[revert-kernel] $*"
}

capture_network_diagnostics() {
	log "--- Network diagnostics start ---"
	log "Timestamp: $(date -Is 2>/dev/null || date)"

	log "Interface link state"
	ip -br link || true

	log "Interface addresses"
	ip -br addr || true

	log "Routing table"
	ip route show || true

	log "DNS resolver config (/etc/resolv.conf)"
	cat /etc/resolv.conf || true

	if command -v nmcli >/dev/null 2>&1; then
		log "NetworkManager overall status"
		nmcli general status || true
		log "NetworkManager device status"
		nmcli device status || true
	fi

	log "systemd-resolved service status"
	systemctl --no-pager --full status systemd-resolved 2>/dev/null | sed -n '1,20p' || true

	log "Reachability tests"
	ping -c 1 -W 2 8.8.8.8 || true
	ping -c 1 -W 2 archive.ubuntu.com || true
	getent hosts archive.ubuntu.com || true

	log "--- Network diagnostics end ---"
}

install_68_from_repo() {
	log "Ensuring latest explicit 6.8.0-x kernel packages from repository"
	capture_network_diagnostics
	if ! apt-get "${APT_OPTS[@]}" update; then
		log "Repository update failed (likely no network/DNS). Skipping online 6.8 refresh."
		return 0
	fi

	local image_pkg
	image_pkg=$(apt-cache pkgnames linux-image-6.8.0- | grep -E -- '-generic$' | sort -V | tail -n 1 || true)
	if [ -z "$image_pkg" ]; then
		log "No linux-image-6.8.0-*-generic package found in repositories. Skipping online refresh."
		return 0
	fi

	local suffix
	suffix="${image_pkg#linux-image-}"

	local pkgs=("$image_pkg")
	local candidate
	for candidate in \
		"linux-modules-${suffix}" \
		"linux-modules-extra-${suffix}" \
		"linux-headers-${suffix}"; do
		if apt-cache show "$candidate" >/dev/null 2>&1; then
			pkgs+=("$candidate")
		fi
	done

	log "Installing: ${pkgs[*]}"
	if ! apt-get "${APT_OPTS[@]}" -y install "${pkgs[@]}"; then
		log "Online 6.8 install failed. Continuing with currently installed/local kernel packages."
	fi
}

purge_kernels_above_68() {
	local purge_list=()
	local pkg
	local ver

	while IFS= read -r pkg; do
		[ -n "$pkg" ] || continue
		ver=$(echo "$pkg" | sed -E 's/^linux-(image|headers|modules|modules-extra)-([0-9]+\.[0-9]+\.[0-9]+)-.*/\2/')
		if [ -n "$ver" ] && dpkg --compare-versions "$ver" gt "6.8.999"; then
			purge_list+=("$pkg")
		fi
	done < <(dpkg-query -W -f='${Package}\n' \
		'linux-image-[0-9]*' \
		'linux-headers-[0-9]*' \
		'linux-modules-[0-9]*' \
		'linux-modules-extra-[0-9]*' 2>/dev/null || true)

	if [ "${#purge_list[@]}" -gt 0 ]; then
		log "Purging kernels/modules above 6.8: ${purge_list[*]}"
		apt-get "${APT_OPTS[@]}" -y purge "${purge_list[@]}" || true
	else
		log "No kernel packages above 6.8 detected"
	fi
}

unhold_installed_68_packages() {
	local held_68
	held_68=$(apt-mark showhold 2>/dev/null | grep -E '^linux-(image|headers|modules|modules-extra)-6\.8\.' || true)
	if [ -n "$held_68" ]; then
		log "Removing hold from 6.8 packages so apt upgrade can move to newer 6.8.x"
		# shellcheck disable=SC2086
		apt-mark unhold $held_68 || true
	fi
}

ensure_ga_meta_packages() {
	log "Ensuring GA kernel meta packages are installed for 6.8.x patch updates"
	if ! apt-get "${APT_OPTS[@]}" -y install linux-generic linux-headers-generic; then
		log "Could not install GA kernel meta packages (likely offline). Skipping; re-run when network is available."
	fi
}

configure_68_only_pin() {
	log "Writing apt pin policy to allow only 6.8 kernel versions"
	cat > "$KERNEL_PIN_FILE" <<'EOF'
Package: linux-image-[0-9]* linux-headers-[0-9]* linux-modules-[0-9]* linux-modules-extra-[0-9]*
Pin: version 6.8.*
Pin-Priority: 1001

Package: linux-image-[0-9]* linux-headers-[0-9]* linux-modules-[0-9]* linux-modules-extra-[0-9]*
Pin: version *
Pin-Priority: -1
EOF
}

log "Disabling unattended upgrades"
systemctl disable --now unattended-upgrades || true

if ! compgen -G "$KERNEL_DIR/*.deb" > /dev/null; then
	log "No local 6.8 payload found"
	install_68_from_repo
else
	log "Installing kernel 6.8 packages from local payload"
	dpkg -i "$KERNEL_DIR"/*.deb || apt-get "${APT_OPTS[@]}" -y -f install

	# Local payload may be older (for example 6.8.0-31). If online,
	# move to latest available 6.8.0-x before purging/holding.
	install_68_from_repo
fi
apt-get "${APT_OPTS[@]}" -y -f install

log "Removing HWE meta packages that can pull newer non-GA kernels"
apt-get "${APT_OPTS[@]}" -y purge \
	linux-generic-hwe-24.04 \
	linux-image-generic-hwe-24.04 \
	linux-headers-generic-hwe-24.04 \
	linux-image-generic-hwe* || true

purge_kernels_above_68
ensure_ga_meta_packages
unhold_installed_68_packages
configure_68_only_pin

log "Regenerating GRUB config"
update-grub

log "Kernel policy enforcement complete"
exit 0
