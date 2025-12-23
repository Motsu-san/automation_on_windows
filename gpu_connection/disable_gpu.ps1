param(
    [Parameter(Mandatory=$true)]
    [string]$DeviceInstanceId
)

# eGPU取り外し
Write-Host "Device ID: $DeviceInstanceId"

# デバイスの現在の状態を確認
$currentDevice = Get-PnpDevice -InstanceId $DeviceInstanceId -ErrorAction SilentlyContinue
if ($null -eq $currentDevice) {
    Write-Host "Error: Device not found"
    exit 1
}

Write-Host "Device Name: $($currentDevice.FriendlyName)"
Write-Host "Current Status: $($currentDevice.Status)"

Write-Host "`nRemoving device..."
# デバイスを削除
& pnputil.exe /remove-device $DeviceInstanceId

# 削除完了を待機
Start-Sleep -Seconds 2

Write-Host "`nDevice removed successfully"
