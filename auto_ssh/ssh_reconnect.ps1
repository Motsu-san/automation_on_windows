### SSH Auto Reconnect Script (Cloudflare Access + RDP Port Forwarding)

# Global variables for cleanup
$script:MonitoringJobs = @()
$script:TempFiles = @()

# Cleanup function
function Cleanup {
    Write-Host "Cleaning up..." -ForegroundColor Gray

    # Stop monitoring jobs
    foreach ($job in $script:MonitoringJobs) {
        if ($job) {
            Stop-Job -Job $job -ErrorAction SilentlyContinue
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        }
    }

    # Remove temporary files
    foreach ($file in $script:TempFiles) {
        if (Test-Path $file) {
            Remove-Item $file -Force -ErrorAction SilentlyContinue
        }
    }
}

# Register cleanup on exit
Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action { Cleanup } | Out-Null

# Load configuration
$ConfigPath = "$PSScriptRoot\config.ps1"
if (Test-Path $ConfigPath) {
    . $ConfigPath
    Write-Host "Configuration loaded from: $ConfigPath" -ForegroundColor Gray
} else {
    # Configuration file is required - log error and exit
    $errorLogDir = "$env:TEMP"
    $errorLogFile = Join-Path $errorLogDir "ssh_reconnect_error_$(Get-Date -Format 'yyyyMMdd').log"
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $errorMessage = "[$timestamp] ERROR: Configuration file not found: $ConfigPath"
    $errorMessage += "`n[$timestamp] ERROR: Script cannot continue without configuration file."
    $errorMessage += "`n[$timestamp] ERROR: Please create config.ps1 in the script directory."

    # Write to error log file
    try {
        Add-Content -Path $errorLogFile -Value $errorMessage -ErrorAction SilentlyContinue
    } catch {
        # If we can't write to log file, just continue
    }

    # Display error and exit
    Write-Host $errorMessage -ForegroundColor Red
    Write-Host "Error log written to: $errorLogFile" -ForegroundColor Yellow
    exit 1
}

# Python script path (same directory as this script)
$PYTHON_SCRIPT_PATH = Join-Path $PSScriptRoot "cloudflare_approve.py"

$script:LOG_FILE = "$LOG_DIR\ssh_reconnect_$(Get-Date -Format 'yyyyMMdd').log"
$LOG_FILE = $script:LOG_FILE  # For backward compatibility

# Ensure log directory exists
if (!(Test-Path $LOG_DIR)) {
    try {
        New-Item -ItemType Directory -Path $LOG_DIR -Force | Out-Null
        if (!(Test-Path $LOG_DIR)) {
            throw "Failed to create log directory"
        }
    } catch {
        # Log directory creation failed - log error and exit
        $errorLogDir = "$env:TEMP"
        $errorLogFile = Join-Path $errorLogDir "ssh_reconnect_error_$(Get-Date -Format 'yyyyMMdd').log"
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $errorMessage = "[$timestamp] ERROR: Failed to create log directory: $LOG_DIR"
        $errorMessage += "`n[$timestamp] ERROR: Error details: $_"
        $errorMessage += "`n[$timestamp] ERROR: Script cannot continue without log directory."

        # Write to error log file
        try {
            Add-Content -Path $errorLogFile -Value $errorMessage -ErrorAction SilentlyContinue
        } catch {
            # If we can't write to log file, just continue
        }

        # Display error and exit
        Write-Host $errorMessage -ForegroundColor Red
        Write-Host "Error log written to: $errorLogFile" -ForegroundColor Yellow
        exit 1
    }
}

# Clean up old log files (older than retention period)
try {
    $cutoffDate = (Get-Date).AddDays(-$LOG_RETENTION_DAYS)
    Get-ChildItem -Path $LOG_DIR -Filter "ssh_reconnect_*.log" -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $cutoffDate } |
        ForEach-Object {
            Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
            Write-Host "Deleted old log file: $($_.Name)" -ForegroundColor Gray
        }
} catch {
    Write-Host "Warning: Failed to clean up old log files: $_" -ForegroundColor Yellow
}

### Log output functions with error handling
function Write-Log {
    param(
        $Message,
        [switch]$Debug
    )
    try {
        # Skip debug messages if DEBUG_MODE is disabled
        if ($Debug -and -not $script:DEBUG_MODE) {
            return
        }

        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logMessage = "[$timestamp] $Message"

        # Debug messages: only write to file (no console output)
        # Normal messages: write to both console and file
        if (-not $Debug) {
            Write-Host $logMessage -ForegroundColor Cyan
        }
        Add-Content -Path $script:LOG_FILE -Value $logMessage -ErrorAction SilentlyContinue
    } catch {
        Write-Host "[ERROR] Failed to write log: $_" -ForegroundColor Red
    }
}

function Write-ErrorLog {
    param($Message)
    try {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logMessage = "[$timestamp] ERROR: $Message"
        Write-Host $logMessage -ForegroundColor Red
        Add-Content -Path $script:LOG_FILE -Value $logMessage -ErrorAction SilentlyContinue
    } catch {
        Write-Host "[ERROR] Failed to write error log: $_" -ForegroundColor Red
    }
}

function Write-SuccessLog {
    param($Message)
    try {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logMessage = "[$timestamp] SUCCESS: $Message"
        Write-Host $logMessage -ForegroundColor Green
        Add-Content -Path $script:LOG_FILE -Value $logMessage -ErrorAction SilentlyContinue
    } catch {
        Write-Host "[ERROR] Failed to write success log: $_" -ForegroundColor Red
    }
}

### Windows Notification Functions
# Track last notification time to prevent duplicates
$script:LastNotificationTime = @{}
$script:NotificationCooldown = 3  # seconds - minimum time between same type notifications

function Show-WindowsNotification {
    param(
        [string]$Title,
        [string]$Message,
        [string]$Type = "Info"  # Info, Success, Warning, Error
    )

    try {
        # Create unique identifier based on notification type to prevent duplicates
        $uniqueId = "SSH-Reconnect-$Type"

        # Check if same notification was shown recently (cooldown period)
        $now = Get-Date
        if ($script:LastNotificationTime.ContainsKey($uniqueId)) {
            $timeSinceLastNotification = ($now - $script:LastNotificationTime[$uniqueId]).TotalSeconds
            if ($timeSinceLastNotification -lt $script:NotificationCooldown) {
                Write-Log "Skipping duplicate notification: $Title (shown $([Math]::Round($timeSinceLastNotification, 1))s ago)" -Debug
                return
            }
        }

        # Try to find and import BurntToast module
        # Task Scheduler may have different module paths, so we use direct path
        $burntToastImported = $false

        # Import BurntToast module from direct path (most reliable for Task Scheduler)
        $directPath = "$env:USERPROFILE\Documents\PowerShell\Modules\BurntToast\1.1.0\BurntToast.psm1"
        if (Test-Path $directPath) {
            try {
                Import-Module $directPath -ErrorAction Stop -Force
                Start-Sleep -Milliseconds 200
                $moduleLoaded = Get-Module BurntToast -ErrorAction SilentlyContinue
                $commandExists = Get-Command New-BurntToastNotification -ErrorAction SilentlyContinue
                if ($moduleLoaded -and $commandExists) {
                    $burntToastImported = $true
                    Write-Log "BurntToast module imported from direct path: $directPath" -Debug
                } else {
                    Write-Log "Direct path import: Module loaded=$($null -ne $moduleLoaded), Command exists=$($null -ne $commandExists)" -Debug
                }
            } catch {
                Write-Log "Failed to import from direct path: $($_.Exception.Message)"
            }
        } else {
            Write-Log "Direct path not found: $directPath" -Debug
        }

        if ($burntToastImported) {
            # Try to remove any existing notification with the same ID first
            if (Get-Command Remove-BurntToastNotification -ErrorAction SilentlyContinue) {
                try {
                    Remove-BurntToastNotification -UniqueIdentifier $uniqueId -ErrorAction SilentlyContinue
                    Start-Sleep -Milliseconds 100
                } catch {
                    # Ignore errors when removing (notification might not exist)
                }
            }

            # Show new notification with unique identifier
            New-BurntToastNotification -Text $Title, $Message -UniqueIdentifier $uniqueId -ErrorAction Stop | Out-Null

            # Update last notification time
            $script:LastNotificationTime[$uniqueId] = $now

            Write-Log "Notification displayed successfully: $Title"
        } else {
            Write-Log "WARNING: Failed to import BurntToast module"
            Write-Log "WARNING: Failed to show notification: $Title - $Message"
            Write-Log "WARNING: Ensure BurntToast is installed: Install-Module -Name BurntToast -Scope CurrentUser"
            Write-Log "WARNING: Check if module exists at: $env:USERPROFILE\Documents\PowerShell\Modules\BurntToast\1.1.0\BurntToast.psm1" -Debug
        }
    } catch {
        Write-Log "WARNING: Failed to show notification: $Title - $Message"
        Write-Log "WARNING: BurntToast module error: $_"
        Write-Log "WARNING: Exception details: $($_.Exception.Message)" -Debug
        Write-Log "WARNING: Ensure BurntToast is installed: Install-Module -Name BurntToast -Scope CurrentUser"
    }
}

### Check if port 3956 is in use (verifies SSH connection is alive)
function Test-SSHTunnelActive {
    try {
        Write-Log "Port check: Starting Get-NetTCPConnection..." -Debug

        # Simple check without jobs (more reliable in Task Scheduler)
        $connections = Get-NetTCPConnection -LocalPort 3956 -State Listen -ErrorAction SilentlyContinue
        $result = $null -ne $connections
        Write-Log "Port check: $result" -Debug
        return $result
    } catch {
        $errorDetails = "Port check error: $($_.Exception.Message)"
        $errorDetails += " | Exception Type: $($_.Exception.GetType().FullName)"
        Write-Log $errorDetails -Debug
        Write-ErrorLog "Failed to check port 3956 status: $($_.Exception.Message)"
        return $false
    }
}

### Find SSH process
function Get-SSHProcess {
    $allSshProcesses = Get-Process -Name ssh -ErrorAction SilentlyContinue
    $matchingProcesses = @()
    $allProcessInfo = @()

    # Log all SSH processes for debugging
    Write-Log "Found $($allSshProcesses.Count) SSH process(es) in total" -Debug

    foreach ($proc in $allSshProcesses) {
        try {
            $cimProcess = Get-CimInstance Win32_Process -Filter "ProcessId = $($proc.Id)" -ErrorAction Stop
            $commandLine = $cimProcess.CommandLine
            $parentId = $cimProcess.ParentProcessId
            $creationDate = $cimProcess.CreationDate

            $processInfo = [PSCustomObject]@{
                PID = $proc.Id
                CommandLine = $commandLine
                ParentPID = $parentId
                CreationDate = $creationDate
                IsZombie = $false
            }

            # Check if parent process exists (detect zombie processes)
            try {
                $parentProcess = Get-Process -Id $parentId -ErrorAction Stop
                $processInfo.IsZombie = $false
            } catch {
                # Parent process doesn't exist - potential zombie
                $processInfo.IsZombie = $true
                Write-Log "WARNING: SSH process PID $($proc.Id) may be a zombie (parent PID $parentId not found)" -Debug
            }

            $allProcessInfo += $processInfo

            # Check if this process matches our target host
            if ($commandLine -like "*$SSH_HOST*") {
                $matchingProcesses += $proc
                Write-Log "Found matching SSH process: PID=$($proc.Id), CommandLine=$commandLine" -Debug
            } else {
                Write-Log "SSH process PID=$($proc.Id) does not match target host: $commandLine" -Debug
            }
        } catch {
            Write-Log "WARNING: Could not get details for SSH process PID $($proc.Id): $($_.Exception.Message)" -Debug
        }
    }

    # Log summary of all SSH processes
    if ($allProcessInfo.Count -gt 0) {
        Write-Log "SSH processes summary:" -Debug
        foreach ($info in $allProcessInfo) {
            $zombieStatus = if ($info.IsZombie) { " [ZOMBIE?]" } else { "" }
            Write-Log "  PID $($info.PID): $($info.CommandLine)$zombieStatus" -Debug
        }
    }

    # Warn if multiple matching processes found
    if ($matchingProcesses.Count -gt 1) {
        Write-Log "WARNING: Found $($matchingProcesses.Count) SSH processes matching target host '$SSH_HOST'"
        Write-Log "WARNING: PIDs: $($matchingProcesses.Id -join ', ')"
        Write-Log "WARNING: This may indicate duplicate connections or zombie processes"
        # Return the most recent one (highest PID, assuming newer processes get higher PIDs)
        $latestProcess = $matchingProcesses | Sort-Object Id -Descending | Select-Object -First 1
        Write-Log "WARNING: Using most recent process: PID $($latestProcess.Id)"
        return $latestProcess
    } elseif ($matchingProcesses.Count -eq 1) {
        return $matchingProcesses[0]
    }

    return $null
}

### Clean up old monitoring jobs
function Stop-OldMonitoringJobs {
    try {
        # Get all monitoring jobs that are still running
        $oldJobs = Get-Job -ErrorAction SilentlyContinue | Where-Object {
            $_.State -eq 'Running' -or $_.State -eq 'NotStarted'
        }

        if ($oldJobs) {
            Write-Log "Cleaning up $($oldJobs.Count) old monitoring job(s)..." -Debug
            foreach ($job in $oldJobs) {
                try {
                    Stop-Job -Job $job -ErrorAction SilentlyContinue
                    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
                    Write-Log "Stopped and removed old monitoring job (ID: $($job.Id))" -Debug
                } catch {
                    Write-Log "Failed to remove old monitoring job (ID: $($job.Id)): $_" -Debug
                }
            }
        }

        # Also clean up jobs from MonitoringJobs array that are no longer valid
        $validJobs = @()
        foreach ($job in $script:MonitoringJobs) {
            if ($job) {
                try {
                    $jobState = Get-Job -Id $job.Id -ErrorAction SilentlyContinue
                    if ($jobState -and ($jobState.State -eq 'Running' -or $jobState.State -eq 'NotStarted')) {
                        # Job is still running, keep it for now (will be cleaned up when SSH process stops)
                        $validJobs += $job
                    } else {
                        # Job is completed or doesn't exist, remove it
                        Write-Log "Removing completed monitoring job (ID: $($job.Id))" -Debug
                    }
                } catch {
                    # Job doesn't exist, skip it
                }
            }
        }
        $script:MonitoringJobs = $validJobs
    } catch {
        Write-Log "Error cleaning up old monitoring jobs: $_" -Debug
    }
}

### Clean up old/zombie SSH processes matching target host
function Cleanup-OldSSHProcesses {
    param([int]$KeepPID = $null)

    try {
        $allSshProcesses = Get-Process -Name ssh -ErrorAction SilentlyContinue
        $matchingProcesses = @()

        foreach ($proc in $allSshProcesses) {
            try {
                $cimProcess = Get-CimInstance Win32_Process -Filter "ProcessId = $($proc.Id)" -ErrorAction Stop
                $commandLine = $cimProcess.CommandLine

                # Check if this process matches our target host
                if ($commandLine -like "*$SSH_HOST*") {
                    # Skip the process we want to keep
                    if ($KeepPID -and $proc.Id -eq $KeepPID) {
                        continue
                    }

                    $matchingProcesses += [PSCustomObject]@{
                        Process = $proc
                        PID = $proc.Id
                        CommandLine = $commandLine
                    }
                }
            } catch {
                Write-Log "WARNING: Could not get details for SSH process PID $($proc.Id): $($_.Exception.Message)" -Debug
            }
        }

        if ($matchingProcesses.Count -gt 0) {
            Write-Log "Found $($matchingProcesses.Count) old SSH process(es) matching target host (excluding PID $KeepPID)" -Debug
            foreach ($match in $matchingProcesses) {
                Write-Log "Cleaning up old SSH process: PID=$($match.PID), CommandLine=$($match.CommandLine)" -Debug
                try {
                    Stop-Process -Id $match.PID -Force -ErrorAction Stop
                    Start-Sleep -Milliseconds 500
                    $procStillExists = Get-Process -Id $match.PID -ErrorAction SilentlyContinue
                    if ($procStillExists) {
                        Write-Log "WARNING: Old SSH process (PID: $($match.PID)) still running after cleanup attempt" -Debug
                    } else {
                        Write-Log "Successfully cleaned up old SSH process (PID: $($match.PID))" -Debug
                    }
                } catch {
                    Write-Log "WARNING: Failed to clean up old SSH process (PID: $($match.PID)): $($_.Exception.Message)" -Debug
                }
            }
        }
    } catch {
        Write-Log "Error cleaning up old SSH processes: $($_.Exception.Message)" -Debug
    }
}

### Stop only the SSH process managed by this script
# Does not affect other SSH connections (e.g. VS Code)
function Stop-ManagedSSH {
    param($ProcessToStop)

    if ($null -ne $ProcessToStop) {
        $sshPid = if ($ProcessToStop -is [int]) { $ProcessToStop } else { $ProcessToStop.Id }
        Write-Log "Cleaning up managed SSH connection (PID: $sshPid) ..."
        try {
            # Verify process exists before trying to stop it
            $procExists = Get-Process -Id $sshPid -ErrorAction SilentlyContinue
            if ($procExists) {
                Stop-Process -Id $sshPid -Force -ErrorAction Stop
                Start-Sleep -Seconds 2

                # Verify process was terminated
                $procStillExists = Get-Process -Id $sshPid -ErrorAction SilentlyContinue
                if ($procStillExists) {
                    Write-ErrorLog "SSH process (PID: $sshPid) still running after Stop-Process attempt"
                } else {
                    Write-Log "SSH process terminated"
                }
            } else {
                Write-Log "SSH process (PID: $sshPid) already terminated" -Debug
            }
        } catch {
            $errorDetails = "Error terminating SSH process (PID: $sshPid): $($_.Exception.Message)"
            $errorDetails += " | Exception Type: $($_.Exception.GetType().FullName)"
            Write-ErrorLog $errorDetails
        }
    }

    # Also clean up associated monitoring jobs
    try {
        Stop-OldMonitoringJobs
    } catch {
        Write-ErrorLog "Error cleaning up monitoring jobs: $($_.Exception.Message)"
    }
}

### Establish SSH connection
function Connect-SSH {
    param(
        [int]$RetryCount = 0,
        $PreviousProcess = $null
    )

    if ($RetryCount -gt 0) {
        Write-Log "Reconnect attempt $RetryCount/$MAX_RETRIES ..."
    } else {
        Write-Log "Starting SSH connection..."
    }

    # Clean up old monitoring jobs before starting new connection
    Stop-OldMonitoringJobs

    # Clean up only previous process (do not touch other SSH connections)
    Stop-ManagedSSH -ProcessToStop $PreviousProcess

    # Clean up any old/zombie SSH processes matching target host (before starting new one)
    # This helps prevent duplicate connections
    Cleanup-OldSSHProcesses

    try {
        # Create temporary file for SSH output monitoring
        $sshOutputFile = Join-Path $env:TEMP "ssh_output_$(Get-Random).log"

        # Track temp file for cleanup
        $script:TempFiles += $sshOutputFile

        # Start SSH connection with PowerShell redirection to file
        $sshCommand = "ssh -N $SSH_HOST"
        Write-Log "Command: $sshCommand"

        # Use cmd.exe to redirect stderr to file (more reliable than PowerShell redirection)
        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processInfo.FileName = "cmd.exe"
        $processInfo.Arguments = "/c ssh.exe -N $SSH_HOST 2>`"$sshOutputFile`""
        $processInfo.UseShellExecute = $false
        $processInfo.RedirectStandardOutput = $false
        $processInfo.RedirectStandardError = $false
        $processInfo.CreateNoWindow = $true  # Run in background

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $processInfo

        $started = $process.Start()
        if ($started) {
            # Get actual SSH process ID (not cmd.exe)
            # Wait a bit for SSH process to start
            Start-Sleep -Milliseconds 800

            $processPid = $null

            # Find SSH process by command line arguments
            try {
                $sshProcess = Get-SSHProcess
                if ($sshProcess) {
                    $processPid = $sshProcess.Id
                    Write-Log "SSH process found (PID: $processPid)"

                    # Clean up any other old SSH processes matching target host (keep current one)
                    Cleanup-OldSSHProcesses -KeepPID $processPid
                } else {
                    Write-ErrorLog "Could not find SSH process by command line arguments"
                }
            } catch {
                $errorDetails = "Failed to find SSH process: $($_.Exception.Message)"
                $errorDetails += " | Exception Type: $($_.Exception.GetType().FullName)"
                Write-ErrorLog $errorDetails
            }

            if (-not $processPid) {
                Write-ErrorLog "Could not identify SSH process ID. Process management may be affected."
                return $null
            }

            Write-Log "SSH process started (PID: $processPid)"
            Write-Log "SSH output file: $sshOutputFile" -Debug

            # Start background job to monitor SSH output file for Cloudflare URL
            # Determine test script path before passing to job
            $TestScriptPath = Join-Path $PSScriptRoot "test_browser.py"
            $monitorJob = Start-Job -ScriptBlock {
                param($OutputFile, $VenvPath, $ScriptPath, $LogFile, $TestScriptPath)

                # Helper function: Write log message
                function Write-MonitorLog {
                    param($Message)
                    Add-Content -Path $LogFile -Value $Message -ErrorAction SilentlyContinue
                }

                # Helper function: Show notification
                function Show-CloudflareNotification {
                    $tempNotificationScript = [System.IO.Path]::GetTempFileName() + ".ps1"
                    $notificationScript = @"
`$ErrorActionPreference = 'SilentlyContinue'
`$scriptPath = `"$tempNotificationScript`"
try {
    Import-Module BurntToast -Force -ErrorAction Stop
    `$uniqueId = `"SSH-Reconnect-CloudflareAuth`"
    if (Get-Command Remove-BurntToastNotification -ErrorAction SilentlyContinue) {
        Remove-BurntToastNotification -UniqueIdentifier `$uniqueId -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 100
    }
    New-BurntToastNotification -Text `"Cloudflare Authentication Required`", `"Please complete authentication in your browser`" -UniqueIdentifier `$uniqueId -ErrorAction Stop
    Start-Sleep -Seconds 2
} finally {
    Start-Sleep -Milliseconds 500
    if (Test-Path `$scriptPath) {
        Remove-Item -Path `$scriptPath -Force -ErrorAction SilentlyContinue
    }
}
"@
                    Set-Content -Path $tempNotificationScript -Value $notificationScript -ErrorAction SilentlyContinue
                    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$tempNotificationScript`"" -WindowStyle Hidden -ErrorAction SilentlyContinue | Out-Null
                }

                # Helper function: Open URL in browser
                function Open-UrlInBrowser {
                    param($Url, $Timestamp)
                    try {
                        Write-MonitorLog "[$Timestamp] Opening URL in browser: $Url"
                        Start-Process $Url -ErrorAction Stop
                        Write-MonitorLog "[$Timestamp] Browser launched successfully"
                    } catch {
                        Write-MonitorLog "[$Timestamp] Failed to open browser: $_"
                    }
                }

                # Helper function: Execute Python script for auto-approval
                function Invoke-PythonAutoApproval {
                    param($Url, $Timestamp)

                    # Use test script for browser visibility testing if it exists
                    $useTestScript = $false
                    $actualScriptPath = $ScriptPath

                    if ($TestScriptPath -and (Test-Path $TestScriptPath -ErrorAction SilentlyContinue)) {
                        $useTestScript = $true
                        $actualScriptPath = $TestScriptPath
                        Write-MonitorLog "[$Timestamp] Using test browser script: $actualScriptPath"
                    } else {
                        # Use actual Cloudflare approval script
                        if (-not ((Test-Path $VenvPath -ErrorAction SilentlyContinue) -and (Test-Path $actualScriptPath -ErrorAction SilentlyContinue))) {
                            Write-MonitorLog "[$Timestamp] ERROR: Python script or venv not found"
                            Write-MonitorLog "[$Timestamp] ERROR: VenvPath: $VenvPath (exists: $(Test-Path $VenvPath))"
                            Write-MonitorLog "[$Timestamp] ERROR: ScriptPath: $actualScriptPath (exists: $(Test-Path $actualScriptPath))"
                            return $false
                        }
                    }

                    try {
                        if ($useTestScript) {
                            Write-MonitorLog "[$Timestamp] Testing browser visibility with test script..."
                        } else {
                            Write-MonitorLog "[$Timestamp] Attempting auto-approval with Python script..."
                        }
                        Write-MonitorLog "[$Timestamp] Python executable: $VenvPath"
                        Write-MonitorLog "[$Timestamp] Script path: $actualScriptPath"

                        # Create log file for Python script output
                        $pythonLogFile = [System.IO.Path]::GetTempFileName() + ".log"
                        Write-MonitorLog "[$Timestamp] Python script log file: $pythonLogFile"

                        try {
                            Write-MonitorLog "[$Timestamp] Launching Python script..."

                            # Launch Python script using & operator directly (proven method that shows browser)
                            # Python script will write its own log file
                            Write-MonitorLog "[$Timestamp] Launching Python script with & operator..."

                            # Record time before execution to find the process
                            $beforeTime = Get-Date

                            # Execute Python script using & operator in background
                            if ($useTestScript) {
                                Write-MonitorLog "[$Timestamp] Command: & `"$VenvPath`" `"$actualScriptPath`" `"$pythonLogFile`""
                                # Launch Python script via PowerShell in new interactive session (for Task Scheduler compatibility)
                                # This ensures browser window is visible even when running from Task Scheduler
                                $pythonLauncherScript = [System.IO.Path]::GetTempFileName() + ".ps1"
                                $launcherScript = @"
`$ErrorActionPreference = 'SilentlyContinue'
try {
    `$VenvPath = `"$VenvPath`"
    `$ScriptPath = `"$actualScriptPath`"
    `$LogFile = `"$pythonLogFile`"
    & `$VenvPath `$ScriptPath `$LogFile
} catch {
    Write-Error `"Failed to launch Python script: `$_`"
} finally {
    Start-Sleep -Milliseconds 500
    if (Test-Path `"$pythonLauncherScript`") {
        Remove-Item -Path `"$pythonLauncherScript`" -Force -ErrorAction SilentlyContinue
    }
}
"@
                                Set-Content -Path $pythonLauncherScript -Value $launcherScript -ErrorAction SilentlyContinue
                                $process = Start-Process powershell.exe `
                                    -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Normal", "-File", "`"$pythonLauncherScript`"" `
                                    -WindowStyle Normal `
                                    -LoadUserProfile `
                                    -PassThru `
                                    -ErrorAction Stop
                                Write-MonitorLog "[$Timestamp] Python script launcher started (PID: $($process.Id))"
                                
                                # Wait a bit and find the actual Python process
                                Start-Sleep -Milliseconds 1500
                                $pythonProcesses = Get-Process -Name python -ErrorAction SilentlyContinue | Where-Object {
                                    $_.StartTime -gt (Get-Date).AddSeconds(-5)
                                }
                                if ($pythonProcesses) {
                                    $pythonProcess = $pythonProcesses | Sort-Object StartTime -Descending | Select-Object -First 1
                                    Write-MonitorLog "[$Timestamp] Python script process found (PID: $($pythonProcess.Id))"
                                    $process = $pythonProcess
                                } else {
                                    Write-MonitorLog "[$Timestamp] WARNING: Could not find Python process, monitoring PowerShell launcher (PID: $($process.Id))"
                                }
                            } else {
                                Write-MonitorLog "[$Timestamp] Command: & `"$VenvPath`" `"$actualScriptPath`" `"$Url`" 120 `"$pythonLogFile`""
                                # Launch Python script via PowerShell in new interactive session (for Task Scheduler compatibility)
                                # This ensures browser window is visible even when running from Task Scheduler
                                $pythonLauncherScript = [System.IO.Path]::GetTempFileName() + ".ps1"
                                $launcherScript = @"
`$ErrorActionPreference = 'SilentlyContinue'
try {
    `$VenvPath = `"$VenvPath`"
    `$ScriptPath = `"$actualScriptPath`"
    `$Url = `"$Url`"
    `$Timeout = 120
    `$LogFile = `"$pythonLogFile`"
    & `$VenvPath `$ScriptPath `$Url `$Timeout `$LogFile
} catch {
    Write-Error `"Failed to launch Python script: `$_`"
} finally {
    Start-Sleep -Milliseconds 500
    if (Test-Path `"$pythonLauncherScript`") {
        Remove-Item -Path `"$pythonLauncherScript`" -Force -ErrorAction SilentlyContinue
    }
}
"@
                                Set-Content -Path $pythonLauncherScript -Value $launcherScript -ErrorAction SilentlyContinue
                                $process = Start-Process powershell.exe `
                                    -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Normal", "-File", "`"$pythonLauncherScript`"" `
                                    -WindowStyle Normal `
                                    -LoadUserProfile `
                                    -PassThru `
                                    -ErrorAction Stop
                                Write-MonitorLog "[$Timestamp] Python script launcher started (PID: $($process.Id))"
                            }

                            # For non-test script, find Python process after Start-Process
                            if (-not $useTestScript) {
                                # Wait a bit for Python process to start, then find it
                                Start-Sleep -Milliseconds 1500
                                $pythonProcesses = Get-Process -Name python -ErrorAction SilentlyContinue | Where-Object {
                                    $_.StartTime -ge $beforeTime
                                }

                                if ($pythonProcesses) {
                                    $process = $pythonProcesses | Sort-Object StartTime -Descending | Select-Object -First 1
                                    Write-MonitorLog "[$Timestamp] Python script process found (PID: $($process.Id))"
                                } else {
                                    Write-MonitorLog "[$Timestamp] WARNING: Could not find Python process immediately, will retry..."
                                    # Retry after a bit more time
                                    Start-Sleep -Milliseconds 1000
                                    $pythonProcesses = Get-Process -Name python -ErrorAction SilentlyContinue | Where-Object {
                                        $_.StartTime -ge $beforeTime
                                    }
                                    if ($pythonProcesses) {
                                        $process = $pythonProcesses | Sort-Object StartTime -Descending | Select-Object -First 1
                                        Write-MonitorLog "[$Timestamp] Python script process found on retry (PID: $($process.Id))"
                                    } else {
                                        Write-MonitorLog "[$Timestamp] ERROR: Could not find Python process"
                                        return $false
                                    }
                                }
                            }

                            # Verify process actually started
                            try {
                                $procVerify = Get-Process -Id $process.Id -ErrorAction Stop
                                Write-MonitorLog "[$Timestamp] Process verified running (PID: $($process.Id), Name: $($procVerify.ProcessName))"

                                # Wait a bit for browser to start, then try to bring browser window to front
                                Start-Sleep -Seconds 5
                                try {
                                    # Find browser processes - check multiple times as browser may start slowly
                                    $browserFound = $false
                                    for ($i = 1; $i -le 5; $i++) {
                                        $checkTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

                                        # Method 1: Find Chrome/Chromium/Edge processes started recently
                                        $browserProcesses = Get-Process -ErrorAction SilentlyContinue | Where-Object {
                                            ($_.ProcessName -like "*chrome*" -or $_.ProcessName -like "*msedge*" -or $_.ProcessName -like "*chromium*") -and
                                            $_.StartTime -gt (Get-Date).AddMinutes(-2)
                                        }

                                        # Method 2: Find child processes of Python process
                                        try {
                                            $childProcs = Get-CimInstance Win32_Process -Filter "ParentProcessId = $($process.Id)" -ErrorAction SilentlyContinue
                                            foreach ($childProc in $childProcs) {
                                                if ($childProc.Name -like "*chrome*" -or $childProc.Name -like "*msedge*" -or $childProc.Name -like "*chromium*") {
                                                    $childProcessObj = Get-Process -Id $childProc.ProcessId -ErrorAction SilentlyContinue
                                                    if ($childProcessObj) {
                                                        $browserProcesses += $childProcessObj
                                                    }
                                                }
                                            }
                                        } catch {
                                            Write-MonitorLog "[$checkTime] Could not check child processes: $($_.Exception.Message)"
                                        }

                                        if ($browserProcesses) {
                                            Write-MonitorLog "[$checkTime] Found $($browserProcesses.Count) browser process(es), attempting to bring window to front..."
                                            $browserFound = $true
                                            break
                                        } else {
                                            Write-MonitorLog "[$checkTime] Browser process not found yet (attempt $i/5), waiting..."
                                            Start-Sleep -Seconds 2
                                        }
                                    }

                                    if ($browserFound -and $browserProcesses) {
                                        # Filter to only processes with main window handles
                                        $browserProcessesWithWindows = $browserProcesses | Where-Object {
                                            $_.MainWindowHandle -ne [IntPtr]::Zero -and $_.MainWindowTitle -ne ""
                                        }

                                        if (-not $browserProcessesWithWindows) {
                                            Write-MonitorLog "[$Timestamp] No browser processes with main windows found, trying Windows API enumeration..."

                                            # Use Windows API to enumerate all windows and find Chrome windows
                                            Add-Type -TypeDefinition @"
                                            using System;
                                            using System.Runtime.InteropServices;
                                            using System.Text;
                                            public class WindowHelper {
                                                [DllImport("user32.dll")]
                                                public static extern bool EnumWindows(EnumWindowsProc enumProc, IntPtr lParam);
                                                [DllImport("user32.dll")]
                                                public static extern bool IsWindowVisible(IntPtr hWnd);
                                                [DllImport("user32.dll", CharSet = CharSet.Unicode)]
                                                public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);
                                                [DllImport("user32.dll")]
                                                public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
                                                [DllImport("user32.dll")]
                                                public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
                                                [DllImport("user32.dll")]
                                                public static extern bool SetForegroundWindow(IntPtr hWnd);
                                                [DllImport("user32.dll")]
                                                public static extern bool IsIconic(IntPtr hWnd);
                                                public const int SW_RESTORE = 9;
                                                public const int SW_MAXIMIZE = 3;
                                                public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
                                            }
"@
                                            $chromeWindows = New-Object System.Collections.ArrayList
                                            $enumProc = [WindowHelper+EnumWindowsProc]{
                                                param($hWnd, $lParam)
                                                if ([WindowHelper]::IsWindowVisible($hWnd)) {
                                                    $className = New-Object System.Text.StringBuilder 512
                                                    [WindowHelper]::GetClassName($hWnd, $className, 512)
                                                    $classStr = $className.ToString().ToLower()
                                                    if ($classStr -like "*chrome*" -or $classStr -like "*chromium*") {
                                                        $processId = 0
                                                        [WindowHelper]::GetWindowThreadProcessId($hWnd, [ref]$processId)
                                                        if ($processId -gt 0) {
                                                            $chromeWindows.Add(@{Handle=$hWnd; ProcessId=$processId}) | Out-Null
                                                        }
                                                    }
                                                }
                                                return $true
                                            }
                                            [WindowHelper]::EnumWindows($enumProc, [IntPtr]::Zero) | Out-Null

                                            if ($chromeWindows.Count -gt 0) {
                                                Write-MonitorLog "[$Timestamp] Found $($chromeWindows.Count) Chrome window(s) via Windows API"
                                                foreach ($win in $chromeWindows) {
                                                    try {
                                                        $hwnd = $win.Handle
                                                        if ([WindowHelper]::IsIconic($hwnd)) {
                                                            [WindowHelper]::ShowWindow($hwnd, [WindowHelper]::SW_RESTORE)
                                                            Start-Sleep -Milliseconds 200
                                                        }
                                                        [WindowHelper]::ShowWindow($hwnd, [WindowHelper]::SW_MAXIMIZE)
                                                        Start-Sleep -Milliseconds 200
                                                        [WindowHelper]::SetForegroundWindow($hwnd)
                                                        Write-MonitorLog "[$Timestamp] Brought Chrome window to front (HWND: $hwnd, PID: $($win.ProcessId))"
                                                    } catch {
                                                        Write-MonitorLog "[$Timestamp] Could not bring window to front: $($_.Exception.Message)"
                                                    }
                                                }
                                            } else {
                                                Write-MonitorLog "[$Timestamp] No Chrome windows found via Windows API"
                                            }
                                        } else {
                                            Write-MonitorLog "[$Timestamp] Found $($browserProcessesWithWindows.Count) browser process(es) with main windows"
                                            foreach ($browserProc in $browserProcessesWithWindows) {
                                                try {
                                                    Write-MonitorLog "[$Timestamp] Processing browser process: PID=$($browserProc.Id), Title=$($browserProc.MainWindowTitle)"

                                                    # Use Windows API to bring window to front
                                                    Add-Type -TypeDefinition @"
                                                    using System;
                                                    using System.Runtime.InteropServices;
                                                    public class WindowHelper {
                                                        [DllImport("user32.dll")]
                                                        public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
                                                        [DllImport("user32.dll")]
                                                        public static extern bool SetForegroundWindow(IntPtr hWnd);
                                                        [DllImport("user32.dll")]
                                                        public static extern bool IsIconic(IntPtr hWnd);
                                                        public const int SW_RESTORE = 9;
                                                        public const int SW_MAXIMIZE = 3;
                                                    }
"@
                                                    if ($browserProc.MainWindowHandle -ne [IntPtr]::Zero) {
                                                        if ([WindowHelper]::IsIconic($browserProc.MainWindowHandle)) {
                                                            [WindowHelper]::ShowWindow($browserProc.MainWindowHandle, [WindowHelper]::SW_RESTORE)
                                                            Start-Sleep -Milliseconds 200
                                                        }
                                                        [WindowHelper]::ShowWindow($browserProc.MainWindowHandle, [WindowHelper]::SW_MAXIMIZE)
                                                        Start-Sleep -Milliseconds 200
                                                        [WindowHelper]::SetForegroundWindow($browserProc.MainWindowHandle)
                                                        Write-MonitorLog "[$Timestamp] Brought browser window to front (PID: $($browserProc.Id), Title: $($browserProc.MainWindowTitle))"
                                                    }
                                                } catch {
                                                    Write-MonitorLog "[$Timestamp] Could not bring browser window to front (PID: $($browserProc.Id)): $($_.Exception.Message)"
                                                }
                                            }
                                        }
                                    } else {
                                        Write-MonitorLog "[$Timestamp] WARNING: Could not find browser process after multiple attempts"
                                    }
                                } catch {
                                    Write-MonitorLog "[$Timestamp] Error finding browser processes: $($_.Exception.Message)"
                                }
                            } catch {
                                Write-MonitorLog "[$Timestamp] ERROR: Process verification failed - process may not have started correctly"
                                Write-MonitorLog "[$Timestamp] ERROR: Exception: $($_.Exception.Message)"
                                return $false
                            }

                            # Wait for process with timeout (150 seconds = 120s timeout + 30s buffer)
                            $processTimeout = 150
                            $processElapsed = 0
                            $processCompleted = $false
                            $lastLogTime = 0

                            while ($processElapsed -lt $processTimeout -and -not $processCompleted) {
                                Start-Sleep -Seconds 2
                                $processElapsed += 2

                                # Log progress every 10 seconds
                                if ($processElapsed - $lastLogTime -ge 10) {
                                    $checkTimestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                                    try {
                                        $procCheck = Get-Process -Id $process.Id -ErrorAction Stop
                                        Write-MonitorLog "[$checkTimestamp] Python script still running (PID: $($process.Id), elapsed: $processElapsed/$processTimeout seconds)"
                                    } catch {
                                        Write-MonitorLog "[$checkTimestamp] Python script process not found (may have exited, elapsed: $processElapsed seconds)"
                                    }
                                    $lastLogTime = $processElapsed
                                }

                                # Check if process has exited
                                try {
                                    $procCheck = Get-Process -Id $process.Id -ErrorAction Stop
                                    # Process still running
                                } catch {
                                    # Process has exited
                                    $processCompleted = $true
                                    $checkTimestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                                    Write-MonitorLog "[$checkTimestamp] Python script process exited (elapsed: $processElapsed seconds)"
                                }
                            }

                            if (-not $processCompleted) {
                                Write-MonitorLog "[$Timestamp] Python script timeout after $processTimeout seconds, terminating process..."
                                Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
                                Start-Sleep -Seconds 2
                            }

                            # Get exit code if process completed
                            try {
                                $procFinal = Get-Process -Id $process.Id -ErrorAction Stop
                                $exitCode = -1  # Process still running (shouldn't happen)
                            } catch {
                                # Process has exited, try to get exit code
                                try {
                                    $procInfo = Get-CimInstance Win32_Process -Filter "ProcessId = $($process.Id)" -ErrorAction SilentlyContinue
                                    if ($procInfo) {
                                        $exitCode = $procInfo.ExitCode
                                    } else {
                                        $exitCode = -1
                                    }
                                } catch {
                                    $exitCode = -1
                                }
                            }

                            Write-MonitorLog "[$Timestamp] Python script process completed (PID: $($process.Id), ExitCode: $exitCode)"

                            # Wait a bit for file system to sync
                            Start-Sleep -Seconds 1

                            # Read Python script log file
                            if (Test-Path $pythonLogFile) {
                                try {
                                    $pythonLog = Get-Content -Path $pythonLogFile -Raw -ErrorAction Stop
                                    if ($pythonLog -and $pythonLog.Trim() -ne "") {
                                        ($pythonLog -split "`n" | Where-Object { $_.Trim() -ne "" }) | ForEach-Object {
                                            Write-MonitorLog "[$Timestamp] [PYTHON] $_"
                                        }
                                    } else {
                                        Write-MonitorLog "[$Timestamp] [PYTHON] Log file is empty (size: $((Get-Item $pythonLogFile).Length) bytes)"
                                    }
                                } catch {
                                    Write-MonitorLog "[$Timestamp] [PYTHON] Error reading log file: $($_.Exception.Message)"
                                }
                            } else {
                                Write-MonitorLog "[$Timestamp] [PYTHON] Log file not found: $pythonLogFile"
                            }

                            $successMsg = if ($exitCode -eq 0) {
                                "[$Timestamp] Python script completed successfully (authentication approved)"
                            } elseif ($exitCode -eq -1) {
                                "[$Timestamp] Python script terminated or exit code unavailable"
                            } else {
                                "[$Timestamp] Python script completed with exit code $exitCode - may require manual approval"
                            }
                            Write-MonitorLog $successMsg
                            return ($exitCode -eq 0)
                        } finally {
                            # Keep files for debugging, but log their paths
                            Write-MonitorLog "[$Timestamp] [DEBUG] Stdout file: $stdoutFile, Stderr file: $stderrFile"
                            # Don't delete files immediately - keep for debugging
                            # if (Test-Path $stdoutFile) { Remove-Item -Path $stdoutFile -Force -ErrorAction SilentlyContinue }
                            # if (Test-Path $stderrFile) { Remove-Item -Path $stderrFile -Force -ErrorAction SilentlyContinue }
                        }
                    } catch {
                        Write-MonitorLog "[$Timestamp] Failed to launch Python script: $_"
                        Write-MonitorLog "[$Timestamp] Exception details: $($_.Exception.Message)"
                        return $false
                    }
                }

                # Helper function: Handle Cloudflare URL detection
                function Handle-CloudflareUrl {
                    param($Url, $Timestamp)

                    Write-MonitorLog "[$Timestamp] Cloudflare authentication required: $Url"
                    Show-CloudflareNotification

                    $pythonSuccess = Invoke-PythonAutoApproval -Url $Url -Timestamp $Timestamp
                    if (-not $pythonSuccess) {
                        Open-UrlInBrowser -Url $Url -Timestamp $Timestamp
                    }
                }

                try {
                    # Wait for file to be created (max 30 seconds)
                    $fileWaitTimeout = 30
                    $fileWaitElapsed = 0
                    while (-not (Test-Path $OutputFile) -and $fileWaitElapsed -lt $fileWaitTimeout) {
                        Start-Sleep -Seconds 1
                        $fileWaitElapsed++
                    }

                    if (-not (Test-Path $OutputFile)) {
                        return
                    }

                    Start-Sleep -Seconds 2

                    # Monitor for Cloudflare URL
                    $lastPosition = 0
                    $urlFound = $false
                    $monitoringTimeout = 120
                    $monitoringElapsed = 0
                    $checkInterval = 1  # Check every 1 second instead of 2 for faster detection
                    $lastLogTime = 0

                    while (-not $urlFound -and $monitoringElapsed -lt $monitoringTimeout) {
                        try {
                            # Use -Raw to read entire file content, then split by lines
                            # This is more reliable for detecting URLs that might span multiple reads
                            $fileContent = Get-Content -Path $OutputFile -Raw -ErrorAction SilentlyContinue
                            if (-not $fileContent) {
                                Start-Sleep -Seconds $checkInterval
                                $monitoringElapsed += $checkInterval
                                continue
                            }

                            # Split content into lines
                            $content = $fileContent -split "`n" | Where-Object { $_.Trim() -ne "" }
                            
                            # Check if file has grown
                            if ($content.Count -gt $lastPosition) {
                                $newLines = $content | Select-Object -Skip $lastPosition
                                $lastPosition = $content.Count

                                foreach ($line in $newLines) {
                                    # Improved regex to match Cloudflare URL (more flexible)
                                    if ($line -match "(https://[^\s\)]+/cdn-cgi/access/cli[^\s\)]+)") {
                                        $url = $matches[1]
                                        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                                        Write-MonitorLog "[$timestamp] [DEBUG] Found Cloudflare URL in SSH output"
                                        Handle-CloudflareUrl -Url $url -Timestamp $timestamp
                                        $urlFound = $true
                                        break
                                    }
                                }
                            }
                            
                            # Log progress every 10 seconds for debugging
                            if ($monitoringElapsed - $lastLogTime -ge 10) {
                                $logTimestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                                $fileSize = if (Test-Path $OutputFile) { (Get-Item $OutputFile).Length } else { 0 }
                                Write-MonitorLog "[$logTimestamp] [DEBUG] Monitoring SSH output (elapsed: $monitoringElapsed/$monitoringTimeout seconds, file size: $fileSize bytes, lines: $($content.Count))"
                                $lastLogTime = $monitoringElapsed
                            }
                        } catch {
                            # File might be locked, wait and retry
                            $errorTimestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                            Write-MonitorLog "[$errorTimestamp] [DEBUG] Error reading SSH output file: $($_.Exception.Message)"
                        }

                        if ($urlFound) { break }

                        Start-Sleep -Seconds $checkInterval
                        $monitoringElapsed += $checkInterval
                    }
                    
                    if (-not $urlFound) {
                        $finalTimestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                        $finalFileSize = if (Test-Path $OutputFile) { (Get-Item $OutputFile).Length } else { 0 }
                        Write-MonitorLog "[$finalTimestamp] [DEBUG] Monitoring timeout reached. File size: $finalFileSize bytes"
                        if (Test-Path $OutputFile) {
                            $finalContent = Get-Content -Path $OutputFile -Raw -ErrorAction SilentlyContinue
                            if ($finalContent) {
                                Write-MonitorLog "[$finalTimestamp] [DEBUG] Last 500 chars of SSH output: $($finalContent.Substring([Math]::Max(0, $finalContent.Length - 500)))"
                            }
                        }
                    }
                } catch {
                    $errorTimestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                    $errorDetails = "[$errorTimestamp] [MONITORING JOB ERROR] Exception: $($_.Exception.Message)"
                    $errorDetails += "`n[$errorTimestamp] [MONITORING JOB ERROR] Type: $($_.Exception.GetType().FullName)"
                    $errorDetails += "`n[$errorTimestamp] [MONITORING JOB ERROR] StackTrace: $($_.ScriptStackTrace)"
                    try {
                        Add-Content -Path $LogFile -Value $errorDetails -ErrorAction SilentlyContinue
                    } catch {
                        $errorLogFile = Join-Path $env:TEMP "ssh_reconnect_error_$(Get-Date -Format 'yyyyMMdd').log"
                        Add-Content -Path $errorLogFile -Value $errorDetails -ErrorAction SilentlyContinue
                    }
                }
            } -ArgumentList $sshOutputFile, $PYTHON_VENV_PATH, $PYTHON_SCRIPT_PATH, $script:LOG_FILE, $TestScriptPath

            # Track job for cleanup
            $script:MonitoringJobs += $monitorJob

            Write-Log "SSH output monitoring started (Job ID: $($monitorJob.Id))" -Debug

            # Wait for connection to establish (max 120 seconds to allow for Cloudflare authentication)
            Write-Log "Waiting for SSH connection and port forwarding to establish..."
            Write-Log "Monitoring process: PID $processPid" -Debug
            $waitCount = 0
            $maxWait = 120
            while ($waitCount -lt $maxWait -and -not (Test-SSHTunnelActive)) {
                Start-Sleep -Seconds 1
                $waitCount++
                # Show progress every 10 seconds
                if ($waitCount % 10 -eq 0) {
                    Write-Log "Still waiting... ($waitCount/$maxWait seconds elapsed)"
                    # Check if process is still alive
                    $processAlive = Get-Process -Id $processPid -ErrorAction SilentlyContinue
                    if (-not $processAlive) {
                        Write-ErrorLog "SSH process (PID: $processPid) terminated unexpectedly during connection wait"
                        return $null
                    }
                    Write-Log "SSH process still running (PID: $processPid)" -Debug
                }
            }

            if (Test-SSHTunnelActive) {
                Write-SuccessLog "SSH connection established, port forwarding (3956 -> RDP 3389) is active"

                # Show success notification
                if ($RetryCount -eq 0) {
                    Show-WindowsNotification -Title "SSH Connection Established" -Message "SSH connection established successfully`nPort forwarding: 3956 -> RDP 3389" -Type "Success"
                } else {
                    Show-WindowsNotification -Title "SSH Reconnected" -Message "SSH connection re-established successfully`nPort forwarding: 3956 -> RDP 3389" -Type "Success"
                }

                # Return a simple object with PID instead of Process object
                return [PSCustomObject]@{
                    Id = $processPid
                }
            } else {
                Write-ErrorLog "Failed to establish port forwarding after $maxWait seconds (may require Cloudflare authentication)"
                Stop-Process -Id $processPid -Force -ErrorAction SilentlyContinue
                return $null
            }
        } else {
            Write-ErrorLog "Failed to start SSH process"
            return $null
        }
    } catch {
        $errorDetails = "SSH connection error: $($_.Exception.Message)"
        $errorDetails += " | Exception Type: $($_.Exception.GetType().FullName)"
        if ($_.ScriptStackTrace) {
            $errorDetails += " | StackTrace: $($_.ScriptStackTrace.Split([Environment]::NewLine)[0])"
        }
        Write-ErrorLog $errorDetails
        Write-Log "SSH connection error details: $($_.Exception | Format-List -Force | Out-String)" -Debug
        return $null
    }
}

### Check if process is running
function Test-ProcessRunning {
    param($Process)

    if ($null -eq $Process) {
        Write-Log "Process check: Process is null" -Debug
        return $false
    }

    try {
        $sshPid = if ($Process -is [int]) { $Process } else { $Process.Id }
        Write-Log "Process check: Checking PID $sshPid..." -Debug
        $proc = Get-Process -Id $sshPid -ErrorAction Stop
        Write-Log "Process check: PID $sshPid is running" -Debug
        return $true
    } catch {
        $sshPid = if ($Process -is [int]) { $Process } else { $Process.Id }
        $errorDetails = "Process check: PID $sshPid not found: $($_.Exception.Message)"
        $errorDetails += " | Exception Type: $($_.Exception.GetType().FullName)"
        Write-Log $errorDetails -Debug

        # If process not found error is expected (process stopped), don't log as error
        if ($_.Exception.GetType().Name -ne 'ArgumentException') {
            Write-ErrorLog "Unexpected error checking process PID $sshPid : $($_.Exception.Message)"
        }
        return $false
    }
}

### Main loop
Write-Log "=========================================="
Write-Log "SSH auto reconnect script started"
Write-Log "=========================================="
Write-Log "Target host: $SSH_HOST"
Write-Log "SSH config: $env:USERPROFILE\.ssh\config"
Write-Log "Port forwarding: localhost:3956 -> RDP 3389"
Write-Log "Check interval: ${CHECK_INTERVAL} seconds"
Write-Log "Log file: $LOG_FILE"
Write-Log "=========================================="

$sshProcess = $null
$consecutiveFailures = 0

### Initial connection
$sshProcess = Connect-SSH
if ($null -eq $sshProcess) {
    Write-ErrorLog "Initial connection failed. Retrying in ${RECONNECT_DELAY} seconds..."
    Start-Sleep -Seconds $RECONNECT_DELAY
}

Write-Log "Note: Other SSH connections (e.g. VS Code) are not affected"

# Robust main loop with error handling
while ($true) {
    try {
        Write-Log "Starting health check..." -Debug

        # Check both process and port forwarding
        Write-Log "Checking process status..." -Debug
        $processRunning = Test-ProcessRunning -Process $sshProcess
        Write-Log "Process running: $processRunning" -Debug

        Write-Log "Checking tunnel status..." -Debug
        $tunnelActive = Test-SSHTunnelActive
        Write-Log "Tunnel active: $tunnelActive" -Debug

        if (-not $processRunning) {
            Write-ErrorLog "SSH process has stopped"
            # Show notification for disconnection
            Show-WindowsNotification -Title "SSH Connection Lost" -Message "SSH process has stopped`nAttempting to reconnect..." -Type "Warning"
        }
        if (-not $tunnelActive) {
            Write-ErrorLog "Port forwarding is inactive"
        }

        if (-not $processRunning -or -not $tunnelActive) {
            $consecutiveFailures++

            if ($consecutiveFailures -le $MAX_RETRIES) {
                Write-Log "Attempting to reconnect... (Failures: $consecutiveFailures/$MAX_RETRIES)"
                Start-Sleep -Seconds $RECONNECT_DELAY
                $sshProcess = Connect-SSH -RetryCount $consecutiveFailures -PreviousProcess $sshProcess

                if ($null -ne $sshProcess -and (Test-SSHTunnelActive)) {
                    $consecutiveFailures = 0
                    Write-SuccessLog "Reconnected successfully"
                }
            } else {
                Write-ErrorLog "Failed $MAX_RETRIES times consecutively. Waiting $CHECK_INTERVAL seconds before reset..."
                $consecutiveFailures = 0
                Start-Sleep -Seconds $CHECK_INTERVAL
            }
        } else {
            # Connection is stable
            if ($consecutiveFailures -gt 0) {
                # First check after recovery
                Write-SuccessLog "Connection is stable"
                $consecutiveFailures = 0
            }
            $sshPid = if ($sshProcess -is [int]) { $sshProcess } else { $sshProcess.Id }
            Write-Log "Connection status: OK (PID: $sshPid, Port: 3956 forwarding active)"
        }

        Write-Log "Sleeping for $CHECK_INTERVAL seconds..." -Debug
        # Split sleep into smaller intervals to ensure script is responsive
        $sleepChunks = [Math]::Max(1, [Math]::Floor($CHECK_INTERVAL / 5))
        for ($i = 1; $i -le $sleepChunks; $i++) {
            Start-Sleep -Seconds 5
            Write-Log "Sleep progress: $($i * 5)/$CHECK_INTERVAL seconds..." -Debug
        }
        # Sleep remaining time if any
        $remainingSleep = $CHECK_INTERVAL % 5
        if ($remainingSleep -gt 0) {
            Start-Sleep -Seconds $remainingSleep
        }
        Write-Log "Sleep completed, starting next check..." -Debug
    } catch {
        $errorMsg = "Unexpected error in main loop: $($_.Exception.Message)"
        $errorMsg += " | Exception Type: $($_.Exception.GetType().FullName)"
        $errorMsg += " | Line: $($_.InvocationInfo.ScriptLineNumber)"
        if ($_.ScriptStackTrace) {
            $errorMsg += " | StackTrace: $($_.ScriptStackTrace.Split([Environment]::NewLine)[0..2] -join ' | ')"
        }
        Write-ErrorLog $errorMsg
        Write-Host "[CRITICAL] $errorMsg" -ForegroundColor Magenta

        # Log full exception details for debugging
        $fullErrorDetails = $_.Exception | Format-List -Force | Out-String
        Write-Log "Full exception details: $fullErrorDetails" -Debug

        Start-Sleep -Seconds 10
        # Reset SSH process on critical error
        $sshProcess = $null
        $consecutiveFailures = 0  # Reset failure count to allow retry
    }
}
