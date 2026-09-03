#Requires -RunAsAdministrator

# Register the Python SSH auto-reconnect script in Task Scheduler.

$ErrorActionPreference = "Stop"

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$pythonExe = Join-Path $workspaceRoot ".venv\Scripts\pythonw.exe"
$scriptPath = Join-Path $PSScriptRoot "ssh_reconnect.py"
$scriptDir = $PSScriptRoot

if (-not (Test-Path $pythonExe)) {
    Write-Error "Virtual environment Python not found: $pythonExe"
    exit 1
}

if (-not (Test-Path $scriptPath)) {
    Write-Error "Script not found: $scriptPath"
    exit 1
}

$taskName = "SSH-RDP_auto-connect-Python"
$taskPath = "\User\"
$comTaskPath = $taskPath.TrimEnd("\")
$currentUser = "$env:USERDOMAIN\$env:USERNAME"

$action = New-ScheduledTaskAction `
    -Execute $pythonExe `
    -Argument "`"$scriptPath`"" `
    -WorkingDirectory $scriptDir

$trigger = New-ScheduledTaskTrigger -AtLogOn -User $currentUser

$principal = New-ScheduledTaskPrincipal `
    -UserId $currentUser `
    -LogonType Interactive `
    -RunLevel Limited

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit (New-TimeSpan -Days 1)

$existingTask = Get-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Unregister-ScheduledTask -TaskPath $taskPath -TaskName $taskName -Confirm:$false
}

Register-ScheduledTask `
    -TaskName $taskName `
    -TaskPath $taskPath `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -Settings $settings `
    -Description "Automatically maintain SSH connection via Cloudflare Access (Python version). Browser window will be visible."

# Add an event trigger for NetworkMonitor Event ID 1002 (SSH host reachable).
# The ScheduledTasks cmdlets do not expose event triggers directly, so use the
# Task Scheduler COM API after registering the logon trigger above.
$scheduleService = New-Object -ComObject "Schedule.Service"
$scheduleService.Connect()
$taskFolder = $scheduleService.GetFolder($comTaskPath)
$taskDefinition = $taskFolder.GetTask($taskName).Definition
$eventSubscription = @"
<QueryList>
    <Query Id="0" Path="Application">
        <Select Path="Application">*[System[Provider[@Name='NetworkMonitor'] and EventID=1002]]</Select>
    </Query>
</QueryList>
"@

$eventTrigger = $taskDefinition.Triggers | Where-Object { $_.Type -eq 0 } | Select-Object -First 1
if (-not $eventTrigger) {
        $eventTrigger = $taskDefinition.Triggers.Create(0)
}
$eventTrigger.Enabled = $true
$eventTrigger.Subscription = $eventSubscription.Trim()

# TASK_CREATE_OR_UPDATE = 6, TASK_LOGON_INTERACTIVE_TOKEN = 3
$taskFolder.RegisterTaskDefinition($taskName, $taskDefinition, 6, $null, $null, 3, $null) | Out-Null

Write-Host "Task '$taskName' has been registered successfully." -ForegroundColor Green
Write-Host "Task path: $taskPath" -ForegroundColor Gray
Write-Host "Event trigger: NetworkMonitor / Event ID 1002" -ForegroundColor Gray
Write-Host "Python executable: $pythonExe" -ForegroundColor Gray
Write-Host "Script path: $scriptPath" -ForegroundColor Gray
