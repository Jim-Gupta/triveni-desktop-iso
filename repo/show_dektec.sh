#!/bin/bash

# ==============================================================================
# DekTec Hardware & Driver Topology Diagnostic Tool
# ==============================================================================

echo "========================================================================"
echo "[+] DEKTEC HARDWARE & DRIVER INVENTORY REPORT"
echo "========================================================================"

# 1. Hardware Presence & Count Stage
echo "[+] Step 1: Scanning physical PCIe infrastructure..."

# Filter the PCIe bus for DekTec's Vendor ID (1a0e)
PCI_LINES=$(lspci -d 1a0e: -nn 2>/dev/null || true)

if [ -z "$PCI_LINES" ]; then
    echo "[-] HARDWARE ERROR: No physical DekTec cards detected on the PCIe bus."
    echo "    Ensure the cards are firmly seated and drawing power."
    exit 0
fi

declare -A SEEN_SLOTS
UNIQUE_PCI_LINES=()

while read -r line; do
    [ -z "$line" ] && continue
    slot=$(echo "$line" | awk '{print $1}')
    slot_base=${slot%.*}

    if [ -n "${SEEN_SLOTS[$slot_base]}" ]; then
        continue
    fi

    SEEN_SLOTS[$slot_base]=1
    UNIQUE_PCI_LINES+=("$line")
done <<< "$PCI_LINES"

CARD_COUNT=${#UNIQUE_PCI_LINES[@]}
echo "[+] Physical Status: Found $CARD_COUNT DekTec device(s) connected to the motherboard."
echo ""

# 2. Loop Through and Parse Card Types
echo "------------------------------------------------------------------------"
echo "ID   SLOT      HEX ID   IDENTIFIED CARD TYPE          EXPECTED DRIVER"
echo "------------------------------------------------------------------------"

INDEX=1
for line in "${UNIQUE_PCI_LINES[@]}"; do
    # Extract slot address (e.g., 19:00.0)
    slot=$(echo "$line" | awk '{print $1}')
    
    # Extract the device hex identifier (e.g., c85b or b853)
    dev_hex=$(echo "$line" | grep -oE '1a0e:[a-fA-F0-9]{4}' | cut -d':' -f2 || true)
    
    # Determine card model type by cross-referencing known DekTec design registers
    card_name="Unknown Model"
    expected_driver="Unknown"
    
    case "$dev_hex" in
        "c85b")
            card_name="DTA-2139 (QAM/VHF/UHF Modulator)"
            expected_driver="DtPcie"
            ;;
        "b853")
            card_name="DTA-2131 (Cable/Terrestrial Receiver)"
            expected_driver="DtPcie"
            ;;
        *)
            # If lspci already natively knows the name (like your DTA-2144 box)
            if echo "$line" | grep -q -i "2144"; then
                card_name="DTA-2144 (Quad ASI/SDI Input/Output)"
                expected_driver="Dta"
            elif [ -n "$dev_hex" ]; then
                card_name="Generic DekTec Device ($dev_hex)"
                expected_driver="Dta or DtPcie"
            fi
            ;;
    esac

    printf "%-4s %-9s [%-6s] %-29s %-15s\n" "$INDEX" "$slot" "$dev_hex" "$card_name" "($expected_driver)"
    INDEX=$((INDEX + 1))
done

echo "------------------------------------------------------------------------"
echo ""

# 3. Driver & Software Runtime Summary
echo "[+] Step 2: Evaluating software driver layer status..."

# Evaluate Kernel Driver Modules
DTA_MODULE=$(lsmod | grep -q "^Dta " && echo "LOADED" || echo "NOT LOADED")
DTPCIE_MODULE=$(lsmod | grep -q "^DtPcie " && echo "LOADED" || echo "NOT LOADED")

# Evaluate Linux File Subsystem Nodes
DTA_NODES=$(ls /dev/Dta* 2>/dev/null | tr '\n' ' ' || echo "None")
DTPCIE_NODES=$(ls /dev/DtPcie* 2>/dev/null | tr '\n' ' ' || echo "None")

# Evaluate User-Space Background Daemon
DAEMON_STATUS="OFFLINE"
if pgrep -f "DtapiServiced" > /dev/null; then
    DAEMON_STATUS="ONLINE (Active background process)"
fi

# Print Final Runtime Dashboard
echo "------------------------------------------------------------------------"
echo " RUNTIME COMPONENT          CURRENT OPERATIONAL STATUS"
echo "------------------------------------------------------------------------"
printf "%-26s %-45s\n" "Legacy Driver (Dta.ko):" "$DTA_MODULE"
printf "%-26s %-45s\n" "Modern Driver (DtPcie.ko):" "$DTPCIE_MODULE"
echo "------------------------------------------------------------------------"
printf "%-26s %-45s\n" "Legacy OS Nodes:" "$DTA_NODES"
printf "%-26s %-45s\n" "Modern OS Nodes:" "$DTPCIE_NODES"
echo "------------------------------------------------------------------------"
printf "%-26s %-45s\n" "DTAPI Service Daemon:" "$DAEMON_STATUS"
echo "========================================================================"

# Basic sanity check advice output
if [ "$DAEMON_STATUS" = "OFFLINE" ]; then
    echo "[!] ALERT: Your hardware is visible, but StreamScope will be blind"
    echo "    because the DTAPI Service Daemon is not running."
fi
