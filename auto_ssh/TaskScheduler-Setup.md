# Task Scheduler Setup - Manual Configuration Guide

## Overview
This guide explains how to manually set up two scheduled tasks for automated network monitoring and SSH auto-reconnect functionality.

## Prerequisites
- Event source `NetworkMonitor` must be registered (see `EventSource-Setup.md`)
- PowerShell scripts must be in the correct location:
  - `C:\Users\masahiro.sakamoto\automation_on_windows\util\NetworkCheck.ps1`
  - `C:\Users\masahiro.sakamoto\automation_on_windows\auto_ssh\ssh_reconnect.ps1`

## Task 1: Network Connection Check

### Purpose
Monitors network connectivity and logs custom events when the network and SSH host are reachable.

### Steps

1. **Open Task Scheduler**
   - Press `Win + R`, type `taskschd.msc`, and press Enter

2. **Create New Task**
   - Click **Create Task** (not "Create Basic Task")
   - Name: `NetworkConnectionCheck`
   - Description: `Checks network connectivity and logs custom event (EventID 1002) when SSH host is reachable.`
   - User account: `masahiro.sakamoto`
   - Select: **Run only when user is logged on**

3. **Configure Triggers**

   **Trigger 1: At log on**
   - Click **Triggers** tab → **New**
   - Begin the task: **At log on**
   - Specific user: `masahiro.sakamoto`
   - Click **OK**

   **Trigger 2: On network connection**
   - Click **New**
   - Begin the task: **On an event**
   - Log: `Microsoft-Windows-NetworkProfile/Operational`
   - Source: `Microsoft-Windows-NetworkProfile`
   - Event ID: `10000`
   - Click **OK**

4. **Configure Action**
   - Click **Actions** tab → **New**
   - Action: **Start a program**
   - Program/script: `powershell.exe`
   - Add arguments: `-ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Users\masahiro.sakamoto\automation_on_windows\util\NetworkCheck.ps1"`
   - Click **OK**

5. **Configure Settings**
   - Click **Settings** tab
   - Check: ✅ **Allow task to be run on demand**
   - Check: ✅ **Run task as soon as possible after a scheduled start is missed**
   - Check: ✅ **If the task fails, restart every:** 1 minute (optional)
   - Stop the task if it runs longer than: `5 minutes`
   - Click **OK**

6. **Configure Conditions**
   - Click **Conditions** tab
   - Uncheck: ❌ **Start the task only if the computer is on AC power**
   - Uncheck: ❌ **Stop if the computer switches to battery power**
   - Click **OK**

7. **Save the task**

## Task 2: SSH Auto-Reconnect

### Purpose
Automatically starts and maintains SSH connection when EventID 1002 is logged (network and SSH host are reachable).

### Steps

1. **Create New Task**
   - Click **Create Task**
   - Name: `SSH-RDP_auto-connect`
   - Description: `Automatically maintain SSH connection via Cloudflare Access. Triggered by network connectivity event.`
   - User account: `masahiro.sakamoto`
   - Select: **Run only when user is logged on**

2. **Configure Trigger**
   - Click **Triggers** tab → **New**
   - Begin the task: **On an event**
   - **Custom event filter:**
     - Click **Custom** radio button
     - Click **New Event Filter** button
     - Switch to **XML** tab
     - Check: ✅ **Edit query manually**
     - Paste the following XML:

     ```xml
     <QueryList>
       <Query Id="0">
         <Select Path="Application">
           *[System[Provider[@Name='NetworkMonitor'] and EventID=1002]]
         </Select>
       </Query>
     </QueryList>
     ```
   - Click **OK**

3. **Configure Action**
   - Click **Actions** tab → **New**
   - Action: **Start a program**
   - Program/script: `powershell.exe`
   - Add arguments: `-ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Users\masahiro.sakamoto\automation_on_windows\auto_ssh\ssh_reconnect.ps1"`
   - Click **OK**

4. **Configure Settings**
   - Click **Settings** tab
   - Check: ✅ **Allow task to be run on demand**
   - Check: ✅ **Run task as soon as possible after a scheduled start is missed**
   - Stop the task if it runs longer than: `1 day`
   - Click **OK**

5. **Configure Conditions**
   - Click **Conditions** tab
   - Uncheck: ❌ **Start the task only if the computer is on AC power**
   - Uncheck: ❌ **Stop if the computer switches to battery power**
   - Click **OK**

6. **Save the task**

## Verification

### Test Network Check Task
1. Right-click on `NetworkConnectionCheck` task
2. Select **Run**
3. Open Event Viewer (`eventvwr.msc`)
4. Navigate to: **Windows Logs** → **Application**
5. Look for EventID 1001 or 1002 from source `NetworkMonitor`

### Test SSH Auto-Reconnect Task
1. Ensure EventID 1001 has been logged (run network check task first)
2. The SSH task should automatically start
3. Check Task Scheduler **History** tab for execution
4. Verify SSH connection by checking port 3956:
   ```powershell
   Get-NetTCPConnection -LocalPort 3956 -State Listen
   ```

## Task Flow Diagram

```
User Logon / Network Connected
         ↓
NetworkConnectionCheck Task runs
         ↓
Tests connectivity (1.1.1.1 + SSH host)
         ↓
    ┌────┴────┐
    │         │
  Success   Failure
    │         │
EventID     EventID
  1001       1003
  1002
    │
    ↓
SSH-RDP_auto-connect Task triggered
    ↓
Establishes SSH connection with Cloudflare Access
    ↓
Maintains port forwarding (3956 → RDP 3389)
```

## Troubleshooting

### Network Check Task not triggering
- Verify triggers are correctly configured
- Check Task Scheduler History tab for errors
- Run task manually to test

### SSH Task not starting automatically
- Confirm EventID 1002 is being logged in Event Viewer
- Verify XML filter in trigger settings
- Check task history for trigger events

### SSH connection fails
- Review logs: `%USERPROFILE%\automation_on_windows\auto_ssh\logs\ssh_reconnect.log`
- Ensure Cloudflare authentication is completed within 120 seconds
- Check SSH config file: `%USERPROFILE%\.ssh\config`

### Tasks not running on battery power
- Go to task **Conditions** tab
- Uncheck power-related restrictions

## Viewing Task History

1. Open Task Scheduler
2. Select the task
3. Click **History** tab (if disabled, enable it from Actions menu)
4. Review execution results

## Disabling/Enabling Tasks

- Right-click task → **Disable** (temporary stop)
- Right-click task → **Enable** (re-enable)
- Right-click task → **Delete** (permanent removal)

## Next Steps

After completing setup:
1. Log off and log back in to test automatic execution
2. Monitor Event Viewer for EventID 1001/1002/1003
3. Check `ssh_reconnect.log` for connection status
4. Verify RDP port forwarding is active on port 3956

---

## Appendix: PowerShell Commands Reference

<details>
<summary>Click to expand - Task management commands via PowerShell</summary>

### Get Task Information
```powershell
# Get the task
Get-ScheduledTask -TaskName "SSH-RDP_auto-connect"

# Get detailed task information
Get-ScheduledTask -TaskName "SSH-RDP_auto-connect" | Get-ScheduledTaskInfo
```

### Control Tasks
```powershell
# Start the task manually
Start-ScheduledTask -TaskName "SSH-RDP_auto-connect"

# Stop the running task
Stop-ScheduledTask -TaskName "SSH-RDP_auto-connect"

# Disable the task (prevent automatic execution)
Disable-ScheduledTask -TaskName "SSH-RDP_auto-connect"

# Enable the task
Enable-ScheduledTask -TaskName "SSH-RDP_auto-connect"

# Unregister (delete) the task
Unregister-ScheduledTask -TaskName "SSH-RDP_auto-connect" -Confirm:$false
```

### Create Task via PowerShell (Alternative to GUI)
```powershell
# Get the current user and script path
$currentUser = $env:USERNAME
$scriptPath = "C:\Users\$currentUser\automation_on_windows\auto_ssh\ssh_reconnect.ps1"

# Verify the script exists
if (-not (Test-Path $scriptPath)) {
    Write-Error "Script not found at: $scriptPath"
    exit 1
}

# Create the scheduled task components
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`""

$trigger = New-ScheduledTaskTrigger -AtLogon -User $currentUser

$principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Limited

$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

# Register the task
Register-ScheduledTask -TaskName "SSH-RDP_auto-connect" -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Automatically maintain SSH connection via Cloudflare Access."
```

### List All Tasks
```powershell
# Get all scheduled tasks
Get-ScheduledTask

# Get tasks with specific name pattern
Get-ScheduledTask -TaskName "*SSH*"

# Get tasks for current user
Get-ScheduledTask | Where-Object { $_.Principal.UserId -eq $env:USERDOMAIN\$env:USERNAME }
```

### Check Task History
```powershell
# Get task execution history from Event Log
Get-WinEvent -FilterHashtable @{
    LogName = 'Microsoft-Windows-TaskScheduler/Operational'
    ID = 200, 201  # 200 = Task started, 201 = Task completed
} -MaxEvents 10 | Where-Object { $_.Message -like "*SSH-RDP_auto-connect*" }
```

**Note:** These commands provide an alternative to GUI-based task management and can be useful for automation or troubleshooting.

</details>
