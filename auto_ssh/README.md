# SSH Auto Reconnect for RDP

Automatically monitors and reconnects SSH connections via Cloudflare Access

## Features

- Automatic SSH connection monitoring (every 30 seconds)
- Auto-reconnect on disconnect (up to 3 retries)
- Port forwarding monitoring (localhost:3956 → RDP 3389)
- Cloudflare authentication auto-handling
- Detailed logging
- Does not interfere with other SSH connections (VS Code, etc.)

## Setup

### 1. Create Configuration File

First time only, create the configuration file:

```powershell
# Create configuration file from template
Copy-Item "C:\Users\masahiro.sakamoto\automation_on_windows\auto_ssh\config.example.ps1" "C:\Users\masahiro.sakamoto\automation_on_windows\auto_ssh\config.ps1"

# Edit config.ps1 as needed
notepad "C:\Users\masahiro.sakamoto\automation_on_windows\auto_ssh\config.ps1"
```

### 2. Cloudflare Auto-Approval (Optional)

If you want to automatically approve Cloudflare authentication, set up the Python environment:

```powershell
# Setup Python environment (first time only)
powershell -ExecutionPolicy Bypass -File "C:\Users\masahiro.sakamoto\automation_on_windows\auto_ssh\setup_python_env.ps1"
```

**How to find the selector**:
1. When the Cloudflare authentication page appears, press F12 to open Developer Tools
2. Click the element selector tool (Ctrl+Shift+C)
3. Click on the Approve button to select it
4. Right-click the button element in Developer Tools → Copy → Copy selector
5. Add it to the `approve_selectors` list in `cloudflare_approve.py`

Example:
```python
approve_selectors = [
    'button.your-actual-button-class',  # Replace with actual selector
    'button:has-text("Approve")',
    # ... other selectors
]
```

## Usage

### 1. Manual Execution

```powershell
# Normal execution (stops when terminal is closed)
powershell -File "C:\Users\masahiro.sakamoto\automation_on_windows\auto_ssh\ssh_reconnect.ps1"
```

### 2. Register with Task Scheduler (Recommended)

Automatically runs on system startup:

```powershell
# Run with administrator privileges
powershell -ExecutionPolicy Bypass -File "C:\Users\masahiro.sakamoto\automation_on_windows\auto_ssh\setup_task_scheduler.ps1"
```

#### Task Management

```powershell
# Start task immediately
Start-ScheduledTask -TaskName "SSH_Auto_Reconnect_RDP"

# Stop task
Stop-ScheduledTask -TaskName "SSH_Auto_Reconnect_RDP"

# Check task status
Get-ScheduledTask -TaskName "SSH_Auto_Reconnect_RDP" | Select-Object TaskName, State, LastRunTime, NextRunTime

# Delete task
Unregister-ScheduledTask -TaskName "SSH_Auto_Reconnect_RDP" -Confirm:$false
```

## Checking Logs

```powershell
# View today's log
Get-Content "C:\Users\masahiro.sakamoto\automation_on_windows\auto_ssh\logs\ssh_reconnect_$(Get-Date -Format 'yyyyMMdd').log"

# Monitor log in real-time
Get-Content "C:\Users\masahiro.sakamoto\automation_on_windows\auto_ssh\logs\ssh_reconnect_$(Get-Date -Format 'yyyyMMdd').log" -Wait -Tail 20
```

Logs are retained for 7 days and old logs are automatically deleted.

### Debug Logs

If you need detailed logs, set `$DEBUG_MODE = $true` in `config.ps1`:

```powershell
# Set in config.ps1
$DEBUG_MODE = $true  # Enable detailed logs
```

In debug mode, detailed information is recorded to the log file (not displayed in console):
- Port connection check details
- Process status check details
- Sleep progress
- Step-by-step internal processing status

By default, it's disabled (`$DEBUG_MODE = $false`) and only important events are logged.

## Customizing Configuration

You can change settings in the `config.ps1` file:

```powershell
# SSH connection settings
$SSH_HOST = "dpc2302001_rdp"  # SSH host (defined in ~/.ssh/config)
$CHECK_INTERVAL = 30           # Connection check interval (seconds)
$RECONNECT_DELAY = 5           # Wait time before reconnect (seconds)
$MAX_RETRIES = 3               # Maximum consecutive retry count

# Logging settings
$LOG_DIR = "$env:USERPROFILE\automation_on_windows\auto_ssh\logs"
$LOG_RETENTION_DAYS = 7        # Number of days to keep logs
$DEBUG_MODE = $false           # Enable detailed debug logs (true/false)

# Python environment settings (for Cloudflare auto-approval)
$PYTHON_VENV_PATH = "$env:USERPROFILE\venv\venv_script\Scripts\python.exe"
```

## Troubleshooting

### No error message when SSH connection is disconnected

- The check interval (`$CHECK_INTERVAL`) is 30 seconds, so you may need to wait up to 30 seconds
- You can check detailed operation status in the log file

### Script is not running

```powershell
# Check monitoring script process
Get-Process -Name powershell | Where-Object {
    (Get-CimInstance Win32_Process -Filter "ProcessId = $($_.Id)").CommandLine -like "*ssh_reconnect*"
}

# Restart with Task Scheduler
Start-ScheduledTask -TaskName "SSH_Auto_Reconnect_RDP"
```

### Cloudflare authentication required

The script automatically opens the Cloudflare authentication URL in a browser and attempts to click the button.
If it fails, please approve manually.

## File Structure

```
auto_ssh/
├── ssh_reconnect.ps1              # Main script
├── config.ps1                     # Configuration file
├── setup_task_scheduler.ps1       # Task Scheduler setup script
├── cloudflare_approve.py          # Cloudflare auto-approval script (Python)
├── setup_python_env.ps1           # Python environment setup script
├── requirements.txt               # Python dependencies
├── test_cloudflare_approve.ps1    # Test script
├── README.md                      # This file
├── venv/                          # Python virtual environment (created after setup)
└── logs/
    └── ssh_reconnect_YYYYMMDD.log # Daily log files
```

## System Requirements

- Windows 10/11
- PowerShell 5.1 or higher
- SSH client (built-in since Windows 10 1809)
- Connection settings must be configured in ~/.ssh/config

## SSH Configuration Example

The following configuration is required in `~/.ssh/config`:

```
Host dpc2302001_rdp
    HostName your-server.example.com
    User your-username
    LocalForward 3956 localhost:3389
    ProxyCommand cloudflared access ssh --hostname %h
```
