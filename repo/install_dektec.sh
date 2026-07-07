#!/bin/bash

set -e

echo "[+] Starting DekTec environment activation..."

# Define core paths
readonly DTA_DIR="/opt/ssxm/DTA"
readonly DTA_SRC="$DTA_DIR/Drivers/Dta/Source/Linux"
readonly DTPCIE_SRC="$DTA_DIR/Drivers/DtPcie/Source/Linux"
readonly DTA_SERVICE="$DTA_DIR/DtapiService/DtapiService.bin"

function verifyRoot() {
  if [ "$EUID" -ne 0 ]; then
    echo "[-] ERROR: This script must be run as root. Use: sudo ./setup_dektec.sh"
    exit 1
  fi
}

function verifyInstallation() {
  echo "[+] Verifying core installation files, tools, and directories..."
  
  # 1. Check Build Tool Dependencies
  for cmd in make gcc depmod modprobe; do
    if ! command -v "$cmd" &> /dev/null; then
      echo "[-] ERROR: Required build tool '$cmd' is not installed."
      exit 1
    fi
  done

  # 2. Check Active Kernel Headers
  local kernel_headers="/usr/src/linux-headers-$(uname -r)"
  if [ ! -d "$kernel_headers" ]; then
    echo "[-] ERROR: Kernel headers missing at $kernel_headers"
    echo "    Run: sudo apt install linux-headers-\$(uname -r)"
    exit 1
  fi

  # 3. Check StreamScope root directory
  if [ ! -d "/opt/ssxm" ]; then
    echo "[-] ERROR: Core installation directory '/opt/ssxm' does not exist."
    echo "    Please ensure your StreamScope base installation is present."
    exit 1
  fi

  # 4. Check DekTec root directory
  if [ ! -d "$DTA_DIR" ]; then
    echo "[-] ERROR: DekTec base directory '$DTA_DIR' does not exist."
    echo "    Please verify your repository configuration files."
    exit 1
  fi

  # 5. Check DTAPI service binary file
  if [ ! -f "$DTA_SERVICE" ]; then
    echo "[-] ERROR: DekTec background service binary was not found at path:"
    echo "    $DTA_SERVICE"
    echo "    Please verify that the DtapiService sub-package is installed."
    exit 1
  fi

  echo "[+] Core directories, system headers, and tools verified successfully."
}

function checkHardwarePresence() {
  echo "[+] Scanning PCIe bus for DekTec hardware..."
  
  local card_count
  # Count the matching lines from lspci directly
  card_count=$(lspci -d 1a0e: 2>/dev/null | wc -l || echo 0)
  
  if [ "$card_count" -eq 0 ]; then
    echo "[-] Hardware Check: No physical DekTec cards detected on this machine."
    echo "[+] Exiting script safely."
    exit 0
  fi

  echo "[+] Hardware Check: Found $card_count physical DekTec card(s) connected."
}

function installLegacyDrivers() {
  if [ -d "$DTA_SRC" ]; then
      echo "[+] Compiling and installing legacy Dta driver..."
      cd "$DTA_SRC" || exit 1
      
      # Using || short-circuit keeps set -e happy while outputting explicit errors
      make clean all || { echo "[-] ERROR: Failed to compile Dta driver."; exit 1; }
      make install || { echo "[-] ERROR: Failed to install Dta driver module."; exit 1; }
      echo "[+] Dta driver compiled and installed successfully."
  else
      echo "[-] WARNING: Dta source directory not found at $DTA_SRC"
  fi
}

function installModernDrivers() {
  if [ -d "$DTPCIE_SRC" ]; then
      echo "[+] Compiling and installing modern DtPcie driver..."
      cd "$DTPCIE_SRC" || exit 1
      
      # Using || short-circuit keeps set -e happy while outputting explicit errors
      make clean all || { echo "[-] ERROR: Failed to compile DtPcie driver."; exit 1; }
      make install || { echo "[-] ERROR: Failed to install DtPcie driver module."; exit 1; }
      echo "[+] DtPcie driver compiled and installed successfully."
  else
      echo "[-] WARNING: DtPcie source directory not found at $DTPCIE_SRC"
  fi
}

function mapModuleDependencies() {
  echo "[+] Updating kernel module dependency map (depmod)..."
  depmod -a
  
  echo "[+] Loading kernel modules into active memory..."
  modprobe Dta || true
  modprobe DtPcie || true
  
  # Check driver operational status independently
  local dta_active=0
  local dtpcie_active=0

  if lsmod | grep -q "Dta"; then dta_active=1; fi
  if lsmod | grep -q "DtPcie"; then dtpcie_active=1; fi

  # Validation logic passes as long as AT LEAST one driver variant is successfully loaded
  if [ $dta_active -eq 1 ] || [ $dtpcie_active -eq 1 ]; then
      echo "[+] Driver loading verification complete:"
      [ $dta_active -eq 1 ] && echo "    - Legacy Dta Module: ACTIVE"
      [ $dtpcie_active -eq 1 ] && echo "    - Modern DtPcie Module: ACTIVE"
  else
      echo "[-] ERROR: Critical Failure. Neither Dta nor DtPcie modules are loaded."
      exit 1
  fi
}

function runService() {
  local -r SERVICE_BIN=$(basename "$DTA_SERVICE")
  local -r SERVICE_DIR=$(dirname "$DTA_SERVICE")

  # If service is already running, stop it first to prevent stuck/ghost processes
  if pgrep -f "$SERVICE_BIN" > /dev/null; then
      echo "[+] Existing $SERVICE_BIN process detected. Stopping it for refresh..."
      pkill -f "$SERVICE_BIN" || true
      sleep 1
  fi

  echo "[+] Setting execution permissions on background environment daemon..."
  chmod +x "$DTA_SERVICE"
  
  echo "[+] Changing working directory to $SERVICE_DIR..."
  cd "$SERVICE_DIR"

  echo "[+] Executing background daemon service natively from its directory..."
  ./"$SERVICE_BIN"

  # Return to the previous directory to keep the shell state clean
  cd - > /dev/null
}

function displaySummary() {
  echo "------------------------------------------------------------------------"
  echo "[+] DEKTEC ACTIVATION COMPLETION SUMMARY:"
  echo "------------------------------------------------------------------------"
  echo "-> Active Device Files:"
  ls -l /dev/Dt* 2>/dev/null || echo "   No device nodes found."
  echo ""
  echo "-> Active Kernel Modules:"
  lsmod | grep -i -E "dta|dtpcie"
  echo ""
  echo "-> Background Service Status:"
  if pgrep -f "$(basename "$DTA_SERVICE")" > /dev/null; then
      echo "   Active Status: Running in background process space."
  else
      echo "   Active Status: Not running."
  fi
  echo "------------------------------------------------------------------------"
  echo "[+] Process Complete. Your StreamScope application is ready for usage."
}

function requestReboot() {
  echo ""
  read -p "[?] Configuration complete. Do you want to reboot the system now? (y/N): " choice
  case "$choice" in
    [yY][eE][sS]|[yY])
      echo "[+] Initializing immediate system reboot..."
      reboot
      ;;
    *)
      echo "[+] Skipping system reboot. Driver runtime adjustments applied."
      ;;
  esac
}

# --- Script Execution Sequence ---
verifyRoot
verifyInstallation
checkHardwarePresence
installLegacyDrivers
installModernDrivers
mapModuleDependencies
runService
displaySummary
# requestReboot
