# Make sure your powershell can run .ps1 scripts
# Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
#

# --- Configuration ---
$DistPath = "$PWD\dist"
$VmName = "UbuntuCustomIsoTest"
$VdiPath = "$PWD\$VmName.vdi" # Defines where the virtual hard drive file will live
$VBoxManage = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"

# --- 1. Dynamically Find the ISO ---
Write-Host "Searching for the ISO in ./dist..." -ForegroundColor Cyan

$IsoFile = Get-ChildItem -Path $DistPath -Filter "*.iso" | Sort-Object LastWriteTime -Descending | Select-Object -First 1

if ($null -eq $IsoFile) {
    Write-Error "No .iso file was found in $DistPath."
    exit 1
}

$IsoPath = $IsoFile.FullName
Write-Host "Found ISO: $($IsoFile.Name)" -ForegroundColor Green

# --- 2. Clean Up Existing VM and Disk ---
Write-Host "Checking for existing VM..." -ForegroundColor Cyan

$vmList = & $VBoxManage list vms
if ($vmList -match "`"$VmName`"") {
    Write-Host "VM '$VmName' found. Powering off and deleting all files..." -ForegroundColor Yellow
    # Power off the VM (suppress errors if it is already off)
    & $VBoxManage controlvm $VmName poweroff 2>$null 
    Start-Sleep -Seconds 2 
    
    # Unregister and delete all files associated with the VM
    & $VBoxManage unregistervm $VmName --delete
}

# Ensure the leftover hard drive file is actually deleted from the host machine
if (Test-Path $VdiPath) {
    Write-Host "Deleting old virtual hard drive..." -ForegroundColor Yellow
    Remove-Item $VdiPath -Force
}

# --- 3. Setup New VirtualBox VM ---
Write-Host "Creating and configuring new VM '$VmName'..." -ForegroundColor Cyan

# Create VM and register it
& $VBoxManage createvm --name $VmName --ostype "Ubuntu_64" --register

# Add IDE Controller (for the ISO/CD-ROM)
& $VBoxManage storagectl $VmName --name "IDE Controller" --add ide

# Add SATA Controller (for the Hard Drive)
& $VBoxManage storagectl $VmName --name "SATA Controller" --add sata --controller IntelAhci

# Create a 250GB (256,000 MB) Virtual Hard Drive
Write-Host "Creating 250GB Virtual Hard Drive..." -ForegroundColor Cyan
& $VBoxManage createmedium disk --filename $VdiPath --size 256000 --format VDI

# Apply Hardware Specs
& $VBoxManage modifyvm $VmName `
    --memory 16384 `
    --cpus 4 `
    --cpuexecutioncap 100 `
    --nic1 none `
    --nic2 none `
    --vram 128 `
    --graphicscontroller vmsvga

# --- 4. Attach Storage and Boot ---
Write-Host "Attaching Storage and booting..." -ForegroundColor Cyan

# Attach the new 250GB Hard Drive to the SATA Controller
& $VBoxManage storageattach $VmName --storagectl "SATA Controller" --port 0 --device 0 --type hdd --medium $VdiPath

# Attach the dynamically found ISO to the IDE Controller
& $VBoxManage storageattach $VmName --storagectl "IDE Controller" --port 0 --device 0 --type dvddrive --medium $IsoPath

# Start the VM
& $VBoxManage startvm $VmName

Write-Host "Done! VirtualBox should be launching a fresh VM with a 250GB drive." -ForegroundColor Green