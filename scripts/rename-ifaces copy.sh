#!/bin/bash
# shellcheck disable=SC2164
#
# This script is executed through the ubiquity/success_command preseed option
# near the end of the installation process.
#

LOG_FILE=/var/log/rename-ifaces.log
exec > >(tee -a "$LOG_FILE") 2>&1

# Configures NetworkManager to establish a DHCP address.
# Args: interfaceName macAddress uniqueId
function configDhcp() {
	id="$3"
    #file="/target/etc/NetworkManager/system-connections/$id"
    file="/etc/NetworkManager/system-connections/$id"
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
	id="$3"
#    file="/target/etc/NetworkManager/system-connections/$id"
    file="/etc/NetworkManager/system-connections/$id"
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
    chmod 600 ${file}
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
	ORG_NAME=$1
	NEW_NAME=$2
	MAC_ADDRESS=$3

	# Don't overwrite an existing link
#	if [[ ! -f /target/etc/systemd/network/10-persistent-net-$ORG_NAME.link ]]; then
		echo "mapping $ORG_NAME to $NEW_NAME $MAC_ADDRESS"
		echo -e "[Match]\nMACAddress=$MAC_ADDRESS\n\n[Link]\nName=$NEW_NAME" > "/etc/systemd/network/10-persistent-net-$ORG_NAME.link"
#	else
#		echo ".link file exists"
#	fi
}

# configure NICs
mkdir -p /etc/NetworkManager/system-connections
rm -f /etc/NetworkManager/system-connections/Wired*
#mkdir -p /target/etc/NetworkManager/system-connections
#rm -f /target/etc/NetworkManager/system-connections/Wired*

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
#            if [ ${NIC_COUNT} -ge 4 ]; then
#echo "TJP: 4 nics"
#                 TMP0=${SORTED_NICS[0]}
#                 TMP1=${SORTED_NICS[1]}
#                 SORTED_NICS[0]=${SORTED_NICS[3]}
#                 SORTED_NICS[1]=${SORTED_NICS[2]}
#                 SORTED_NICS[2]=$TMP0
#                 SORTED_NICS[3]=$TMP1
#            else
echo "TJP: 2 NICS: ${NIC_COUNT}"
	        TMP=${SORTED_NICS[0]}
        	SORTED_NICS[0]=${SORTED_NICS[1]}
        	SORTED_NICS[1]=$TMP
#            fi
	fi
    fi
fi

# map and configure the nics
NIC_COUNT=0
CONN_COUNT=1
rm -f /etc/systemd/network/10-*.link
for NIC in "${SORTED_NICS[@]}"; do
	echo -n "Found $NIC - "
	map "$NIC" "eth0$NIC_COUNT" "${NICS[$NIC]}"
    configInterface "eth0$NIC_COUNT" "${NICS[$NIC]}" "Wired_connection_$CONN_COUNT"

	(( ++NIC_COUNT ))
	(( ++CONN_COUNT ))
done

# update NetworkManager config to allow disconnected ifaces
{
    echo "[main]"
    echo "no-auto-default=*"
    echo "ignore-carrier=*"
} >/etc/NetworkManager/conf.d/triveni-digital.conf
chmod 644 /etc/NetworkManager/conf.d/triveni-digital.conf
# target

{
    echo "net.core.wmem_max = 16777216"
    echo "net.core.rmem_max = 16777216"
    echo "net.ipv4.conf.default.rp_filter = 0"
    echo "net.ipv4.conf.all.rp_filter = 0"

    echo "net.ipv4.conf.eth00.rp_filter = 0"
    echo "net.ipv4.conf.eth01.rp_filter = 0"
    echo "net.ipv4.conf.eth02.rp_filter = 0"
    echo "net.ipv4.conf.eth03.rp_filter = 0"
    echo "net.ipv4.conf.eth04.rp_filter = 0"
    echo "net.ipv4.conf.eth05.rp_filter = 0"
} >>/etc/sysctl.conf

sysctl -p

exit 0

