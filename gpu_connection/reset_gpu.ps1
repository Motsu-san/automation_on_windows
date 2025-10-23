# GPU無効化
Write-Host "Disabling GPU..."
Disable-PnpDevice -InstanceId $env:GPU_INSTANCE_ID -Confirm:$false

# 少し待機
Start-Sleep -Seconds 2

# GPU有効化
Write-Host "Enabling GPU..."
Enable-PnpDevice -InstanceId $env:GPU_INSTANCE_ID -Confirm:$false

Write-Host "GPU reset completed"
