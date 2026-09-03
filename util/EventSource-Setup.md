# Event Source Registration - Setup Guide

## Overview
This guide explains how to register the `NetworkMonitor` event source in Windows Event Log. This is required before using `util\NetworkCheck.ps1` for network monitoring.

## Prerequisites
- Administrator privileges on Windows
- PowerShell 5.1 or later

## Registration Steps

### Step 1: Open PowerShell as Administrator
1. Press `Win + X` and select **Windows PowerShell (Admin)** or **Terminal (Admin)**
2. Click **Yes** on the UAC prompt

### Step 2: Register the Event Source
From the workspace root, run the existing registration script in the administrator PowerShell window:

```powershell
Set-Location "$env:USERPROFILE\automation_on_windows"
powershell -ExecutionPolicy Bypass -File ".\util\Register-EventSource.ps1"
```

The script is safe to run more than once. If the source is already registered, it exits without changing it.

### Step 3: Verify Registration
Check if the event source was registered successfully:

```powershell
[System.Diagnostics.EventLog]::SourceExists("NetworkMonitor")
```

Expected output: `True`

## Event IDs Used

Once registered, `NetworkCheck.ps1` will log the following events to the Application log:

| Event ID | Description | Purpose |
|----------|-------------|---------|
| **1001** | Network connection success | Indicates internet connectivity is available (ping to 1.1.1.1 succeeded) |
| **1002** | SSH host reachable | SSH target host is accessible - **triggers SSH auto-connect task** |
| **1003** | Connection failure | Network or SSH host is unreachable |

## Viewing Events

To view the logged events:

1. Open **Event Viewer** (`eventvwr.msc`)
2. Navigate to: **Windows Logs** → **Application**
3. Filter by **Source**: `NetworkMonitor`

Or use PowerShell:

```powershell
Get-EventLog -LogName Application -Source NetworkMonitor -Newest 10
```

## Troubleshooting

### Error: "Source already exists"
The event source is already registered. No action needed.

### Error: "Access denied"
Make sure you're running PowerShell as Administrator.

### Error: "Source does not exist" when running NetworkCheck.ps1
Complete the registration steps above first.

## Unregistration (Optional)

If you need to remove the event source:

```powershell
Remove-EventLog -Source NetworkMonitor
```

**Note**: This will also delete all logged events for this source.

## Next Steps

After registering the event source:
1. Configure a Task Scheduler task to run `util\NetworkCheck.ps1` using the trigger documented at the top of that script (Security log, Event ID 4801 for workstation unlock).
2. If you use the Python SSH auto-reconnect task, register it separately with `auto_ssh\register_task_python.ps1`.

`register_network_tasks.ps1` does not exist in this workspace. The older `util\setup_task_scheduler.ps1` also targets the removed PowerShell SSH script, so do not use it for the current Python setup.
