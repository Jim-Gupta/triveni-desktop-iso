# --- Configuration ---
$DistPath = "$PWD\dist"
$VmName = "UbuntuCustomIsoTest"
$VBoxManage = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"

# # --- 1. Run Docker Build ---
# Write-Host "Building custom ISO via Docker..." -ForegroundColor Cyan
# # Replace with your actual docker run command
# docker run --rm -v "$DistPath:/output" your-ubuntu-builder-image

# --- 2. Dynamically Find the ISO ---
Write-Host "Searching for the ISO in ./dist..." -ForegroundColor Cyan

$IsoFile = Get-ChildItem -Path $DistPath -Filter "*.iso" | Sort-Object LastWriteTime -Descending | Select-Object -First 1

if ($null -eq $IsoFile) {
    Write-Error "No .iso file was found in $DistPath. Docker build may have failed."
    exit 1
}

$IsoPath = $IsoFile.FullName
Write-Host "Found ISO: $($IsoFile.Name)" -ForegroundColor Green

# --- 3. Setup VirtualBox VM ---
Write-Host "Configuring VirtualBox VM Specs..." -ForegroundColor Cyan

$vmList = & $VBoxManage list vms
if ($vmList -match "`"$VmName`"") {
    Write-Host "VM '$VmName' already exists. Powering off..."
    & $VBoxManage controlvm $VmName poweroff 2>$null 
    Start-Sleep -Seconds 2
} else {
    Write-Host "Creating new VM '$VmName'..."
    & $VBoxManage createvm --name $VmName --ostype "Ubuntu_64" --register
    & $VBoxManage storagectl $VmName --name "IDE Controller" --add ide
}

# Apply Hardware Specs (Runs on both new and existing VMs to enforce your settings)
& $VBoxManage modifyvm $VmName `
    --memory 16384 `
    --cpus 4 `
    --cpuexecutioncap 100 `
    --nic1 none `
    --nic2 none `
    --vram 128 `
    --graphicscontroller vmsvga

# --- 4. Attach ISO and Boot ---
Write-Host "Attaching ISO and booting..." -ForegroundColor Cyan

# Eject any existing disk
& $VBoxManage storageattach $VmName --storagectl "IDE Controller" --port 0 --device 0 --type dvddrive --medium emptydrive 2>$null

# Attach the dynamically found ISO
& $VBoxManage storageattach $VmName --storagectl "IDE Controller" --port 0 --device 0 --type dvddrive --medium $IsoPath

# Start the VM
& $VBoxManage startvm $VmName

Write-Host "Done! VirtualBox should be launching with 16GB RAM and 4 Cores." -ForegroundColor Green