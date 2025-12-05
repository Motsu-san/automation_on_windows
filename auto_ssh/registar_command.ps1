
# Get the current user and script directory dynamically
$currentUser = $env:USERNAME
$scriptDir = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $scriptDir "auto_ssh\ssh_reconnect.ps1"

# Verify the script exists
if (-not (Test-Path $scriptPath)) {
    Write-Error "Script not found at: $scriptPath"
    exit 1
}

# Create the scheduled task
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`""

$trigger = New-ScheduledTaskTrigger -AtLogon -User $currentUser

$principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Limited

$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

Register-ScheduledTask -TaskName "SSH-RDP_auto-connect" -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Automatically maintain SSH connection via Cloudflare Access."

# task scheduler commands
# Get the task
Get-ScheduledTask -TaskName "SSH-RDP_auto-connect"

# Start the task
Start-ScheduledTask -TaskName "SSH-RDP_auto-connect"

# Get task info
Get-ScheduledTask -TaskName "SSH-RDP_auto-connect" | Get-ScheduledTaskInfo

# Stop the task
Stop-ScheduledTask -TaskName "SSH-RDP_auto-connect"

# Disable the task
Disable-ScheduledTask -TaskName "SSH-RDP_auto-connect"

# Unregister (delete) the task
Unregister-ScheduledTask -TaskName "SSH-RDP_auto-connect" -Confirm:$false
