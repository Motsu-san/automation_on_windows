# GPU無効化
Write-Host "Disabling GPU..."
Disable-PnpDevice -InstanceId $env:GPU_INSTANCE_ID -Confirm:$false

# 少し待機
Start-Sleep -Seconds 2

Write-Host "✅ GPU safely disabled."
