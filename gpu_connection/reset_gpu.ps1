param(
    [Parameter(Mandatory=$true)]
    [string]$DeviceInstanceId
)

# eGPU: reset (remove, rescan, re-enumerate)
Write-Host "Device ID: $DeviceInstanceId"

# Check current PnP state
$currentDevice = Get-PnpDevice -InstanceId $DeviceInstanceId -ErrorAction SilentlyContinue
if ($null -eq $currentDevice) {
    Write-Host "Error: Device not found"
    exit 1
}

Write-Host "Device Name: $($currentDevice.FriendlyName)"
Write-Host "Current Status: $($currentDevice.Status)"

Write-Host "`nRemoving device..."
# Remove the device
& pnputil.exe /remove-device $DeviceInstanceId

# Brief wait for removal
Start-Sleep -Seconds 2

Write-Host "Rescanning PCI bus..."
# Re-scan the PCI / device tree
& pnputil.exe /scan-devices

# Wait for re-detection and driver init
Start-Sleep -Seconds 3

Write-Host "`nDevice reset completed"
