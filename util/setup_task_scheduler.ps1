### Note: This script is for reference only. Please review before executing.
### Setup Task Scheduler for SSH Auto Reconnect
# This script creates a scheduled task to run ssh_reconnect.ps1 at system startup

$ScriptPath = "$env:USERPROFILE\automation_on_windows\auto_ssh\ssh_reconnect.ps1"
$TaskName = "SSH_Auto_Reconnect_RDP"
$TaskDescription = "Automatically reconnects SSH tunnel for RDP port forwarding"

# Check if script exists
if (!(Test-Path $ScriptPath)) {
    Write-Host "ERROR: Script not found at $ScriptPath" -ForegroundColor Red
    exit 1
}

# Check if task already exists
$existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Write-Host "Task '$TaskName' already exists. Removing..." -ForegroundColor Yellow
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

# Create task action with working directory
$Action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$ScriptPath`"" `
    -WorkingDirectory "$env:USERPROFILE\automation_on_windows\auto_ssh"

# Create task trigger (at startup)
$Trigger = New-ScheduledTaskTrigger -AtStartup

# Create task settings
$Settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RunOnlyIfNetworkAvailable `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit (New-TimeSpan -Days 0) `
    -Priority 4

# Create task principal (run as current user)
$Principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -RunLevel Highest

# Register the task
try {
    Register-ScheduledTask `
        -TaskName $TaskName `
        -Description $TaskDescription `
        -Action $Action `
        -Trigger $Trigger `
        -Settings $Settings `
        -Principal $Principal `
        -Force

    Write-Host "SUCCESS: Task '$TaskName' created successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "The SSH auto reconnect script will now run automatically at system startup." -ForegroundColor Cyan
    Write-Host ""
    Write-Host "To start the task now, run:" -ForegroundColor Yellow
    Write-Host "  Start-ScheduledTask -TaskName '$TaskName'" -ForegroundColor White
    Write-Host ""
    Write-Host "To stop the task, run:" -ForegroundColor Yellow
    Write-Host "  Stop-ScheduledTask -TaskName '$TaskName'" -ForegroundColor White
    Write-Host ""
    Write-Host "To remove the task, run:" -ForegroundColor Yellow
    Write-Host "  Unregister-ScheduledTask -TaskName '$TaskName' -Confirm:`$false" -ForegroundColor White

} catch {
    Write-Host "ERROR: Failed to create task: $_" -ForegroundColor Red
    exit 1
}
