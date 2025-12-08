# Event Source Registration - Setup Guide

## Overview
This guide explains how to manually register the `NetworkMonitor` event source in Windows Event Log. This is required before using `NetworkCheck.ps1` for network monitoring and SSH auto-connect functionality.

## Prerequisites
- Administrator privileges on Windows
- PowerShell 5.1 or later

## Registration Steps

### Step 1: Open PowerShell as Administrator
1. Press `Win + X` and select **Windows PowerShell (Admin)** or **Terminal (Admin)**
2. Click **Yes** on the UAC prompt

### Step 2: Register the Event Source
Run the following command in the administrator PowerShell window:

```powershell
New-EventLog -LogName Application -Source NetworkMonitor
```

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
1. Run `register_network_tasks.ps1` to set up Task Scheduler automation
2. The network monitoring and SSH auto-connect will work automatically on system logon and network connection events
