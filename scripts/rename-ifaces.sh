#!/bin/bash
# shellcheck disable=SC2164
#
# This script is executed near the end of the installation process.
# It handles persistent renaming, live runtime renaming, and network configuration.
#

set -e

LOG_FILE=/var/log/triveni-install.log
exec > >(tee -a "$LOG_FILE") 2>&1

echo "**********************************************************************"
echo "Running rename-ifaces.sh (renaming network interfaces)"

cleanup_installer_network_state() {
    local profile

    mkdir -p /etc/NetworkManager/system-connections

    for profile in /etc/NetworkManager/system-connections/*; do
        [ -e "$profile" ] || continue

        case "$(basename "$profile")" in
            Wired*|netplan-*|installer-*|"System "*)
                echo "Removing installer-generated NetworkManager profile: $profile"
                rm -f "$profile"
                ;;
        esac
    done

    for profile in /etc/netplan/*.yaml; do
        [ -e "$profile" ] || continue
        if grep -Eq 'installer-nic|subiquity|autoinstall' "$profile"; then
            echo "Removing installer-generated netplan file: $profile"
            rm -f "$profile"
        fi
    done
}


# Configures NetworkManager to establish a DHCP address.
# Args: interfaceName macAddress uniqueId
function configDhcp() {
    local id="$3"
    local file="/etc/NetworkManager/system-connections/$id"
    local uuid
    uuid=$(uuidgen)

    echo "
[802-3-ethernet]
duplex=full
mac-address=${2}

[connection]
id=${id}
uuid=${uuid}
type=802-3-ethernet
interface-name=${1}

[ipv6]
method=auto

[ipv4]
method=auto
    " > "$file"
    chmod 600 "$file"
}

STATIC_INDEX=1

# Configures NetworkManager to establish a static IP address.
# Args: interfaceName macAddress uniqueId
function configStaticIp() {
    local id="$3"
    local file="/etc/NetworkManager/system-connections/$id"
    local uuid
    uuid=$(uuidgen)

    echo "
[802-3-ethernet]
duplex=full
mac-address=${2}

[connection]
id=${id}
uuid=${uuid}
type=802-3-ethernet
interface-name=${1}

[ipv6]
method=ignore

[ipv4]
method=manual
address1=192.168.$STATIC_INDEX.10/24,0.0.0.0
    " > "$file"
    chmod 600 "${file}"
    (( ++STATIC_INDEX ))
}

DHCP_ASSIGNED=0

# Args: interfaceName macAddress uniqueId
function configInterface() {
    if [ $DHCP_ASSIGNED -eq 0 ]; then
        configDhcp "$1" "$2" "$3"
        DHCP_ASSIGNED=1
    else
        configStaticIp "$1" "$2" "$3"
    fi
}

function map() {
    local ORG_NAME=$1
    local NEW_NAME=$2
    local MAC_ADDRESS=$3

    echo "mapping $ORG_NAME to $NEW_NAME $MAC_ADDRESS"
    echo -e "[Match]\nMACAddress=$MAC_ADDRESS\n\n[Link]\nName=$NEW_NAME" > "/etc/systemd/network/10-persistent-net-$ORG_NAME.link"
}

# configure NICs
cleanup_installer_network_state

# find all ethernet (e*) nics
declare -A NICS
NIC_COUNT=0
for NIC in $(ls /sys/class/net/); do
    if [[ $NIC == e* ]]; then
        ADDRESS=$(</sys/class/net/$NIC/address)
        NICS[$NIC]=$ADDRESS
        NIC_COUNT=$((NIC_COUNT+1))
    else
        echo "Ignoring $NIC"
    fi
done

# sort the nics by length and name
readarray -t SORTED_NICS < <(
for str in "${!NICS[@]}"; do
    printf '%d\t%s\n' "${#str}" "$str"
done | sort -k 1,1n -k 2 | cut -f 2- )

# swap motherboard nics for certain motherboards so that port 0 is on the left when looking at the back
if ! dmidecode -t 2 | grep -q "Product Name: X10SRA"; then
    if ! dmidecode -t 2 | grep -q "Product Name: X10DRW-i"; then
        if ! dmidecode -t 2 | grep -q "Product Name: X11DDW"; then
            # Only attempt a physical index swap if there are at least 2 NICs available
            if [ "${NIC_COUNT}" -ge 2 ]; then
                echo "Swapping default 2 NICS out of total: ${NIC_COUNT}"
                TMP=${SORTED_NICS[0]}
                SORTED_NICS[0]=${SORTED_NICS[1]}
                SORTED_NICS[1]=$TMP
            else
                echo "Single NIC detected (${NIC_COUNT}). Skipping layout swap."
            fi
        fi
    fi
fi

# map and configure the nics
NIC_COUNT=0
CONN_COUNT=1
rm -f /etc/systemd/network/10-*.link
for NIC in "${SORTED_NICS[@]}"; do
    NEW_IFACE_NAME="eth0$NIC_COUNT"
    echo "Processing $NIC -> $NEW_IFACE_NAME"
    
    # 1. Write persistent systemd link file for target machine reboots
    map "$NIC" "$NEW_IFACE_NAME" "${NICS[$NIC]}"
    
    # 2. Generate NetworkManager profiles
    configInterface "$NEW_IFACE_NAME" "${NICS[$NIC]}" "Wired_connection_$CONN_COUNT"

    # 3. Force immediate live runtime rename so subsequent scripts can find them right now
    echo "Flipping $NIC to $NEW_IFACE_NAME live in memory..."
    ip link set dev "$NIC" down || true
    ip link set dev "$NIC" name "$NEW_IFACE_NAME" || true
    ip link set dev "$NEW_IFACE_NAME" up || true

    # 4. FIX: Dynamically write the sysctl filter ONLY for this active, valid interface
    echo "net.ipv4.conf.$NEW_IFACE_NAME.rp_filter = 0" >> /etc/sysctl.conf

    (( ++NIC_COUNT ))
    (( ++CONN_COUNT ))
done

# update NetworkManager config to allow disconnected ifaces
mkdir -p /etc/NetworkManager/conf.d
{
    echo "[main]"
    echo "no-auto-default=*"
    echo "ignore-carrier=*"
} >/etc/NetworkManager/conf.d/triveni-digital.conf
chmod 644 /etc/NetworkManager/conf.d/triveni-digital.conf

# Stage global system-wide sysctl optimizations to the configuration file
{
    echo "net.core.wmem_max = 16777216"
    echo "net.core.rmem_max = 16777216"
    echo "net.ipv4.conf.default.rp_filter = 0"
    echo "net.ipv4.conf.all.rp_filter = 0"
} >>/etc/sysctl.conf

# 5. FIX: Running sysctl -p is now 100% safe because no ghost interfaces are evaluated!
sysctl -p

exit 0