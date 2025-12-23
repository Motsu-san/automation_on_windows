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
        Write-Log "Port check error: $_" -Debug
        return $false
    }
}

### Find SSH process
function Get-SSHProcess {
    $processes = Get-Process -Name ssh -ErrorAction SilentlyContinue
    foreach ($proc in $processes) {
        $commandLine = (Get-CimInstance Win32_Process -Filter "ProcessId = $($proc.Id)").CommandLine
        if ($commandLine -like "*$SSH_HOST*") {
            return $proc
        }
    }
    return $null
}

### Stop only the SSH process managed by this script
# Does not affect other SSH connections (e.g. VS Code)
function Stop-ManagedSSH {
    param($ProcessToStop)

    if ($null -ne $ProcessToStop) {
        $sshPid = if ($ProcessToStop -is [int]) { $ProcessToStop } else { $ProcessToStop.Id }
        Write-Log "Cleaning up managed SSH connection (PID: $sshPid) ..."
        try {
            Stop-Process -Id $sshPid -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
            Write-Log "SSH process terminated"
        } catch {
            Write-ErrorLog "Error terminating SSH process: $_"
        }
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

    # Clean up only previous process (do not touch other SSH connections)
    Stop-ManagedSSH -ProcessToStop $PreviousProcess

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
            Start-Sleep -Milliseconds 500
            $sshProcess = Get-Process -Name ssh -ErrorAction SilentlyContinue | Where-Object { $_.StartTime -gt (Get-Date).AddSeconds(-5) } | Select-Object -First 1
            $processPid = if ($sshProcess) { $sshProcess.Id } else { $process.Id }

            Write-Log "SSH process started (PID: $processPid)"
            Write-Log "SSH output file: $sshOutputFile" -Debug

            # Start background job to monitor SSH output file for Cloudflare URL
            $monitorJob = Start-Job -ScriptBlock {
                param($OutputFile, $VenvPath, $ScriptPath, $LogFile)

                try {
                    # Wait for file to be created
                    $timeout = 60
                    $elapsed = 0
                    while (-not (Test-Path $OutputFile) -and $elapsed -lt $timeout) {
                        Start-Sleep -Milliseconds 500
                        $elapsed++
                    }

                    if (-not (Test-Path $OutputFile)) {
                        return
                    }

                    # Give SSH time to write initial output
                    Start-Sleep -Seconds 2

                    # Read existing content first
                    $lastPosition = 0
                    $urlFound = $false

                    while (-not $urlFound) {
                        try {
                            $content = Get-Content -Path $OutputFile -ErrorAction SilentlyContinue
                            if ($content) {
                                $newLines = $content | Select-Object -Skip $lastPosition
                                $lastPosition = $content.Count

                                foreach ($line in $newLines) {
                                    # Check for Cloudflare URL
                                    if ($line -match "(https://[^\s]+/cdn-cgi/access/cli[^\s]+)") {
                                        $url = $matches[1]
                                        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

                                        # Log to main log file
                                        $msg = "[$timestamp] Cloudflare authentication required: $url"
                                        Add-Content -Path $LogFile -Value $msg -ErrorAction SilentlyContinue

                                        # Try Python script first
                                        if ((Test-Path $VenvPath -ErrorAction SilentlyContinue) -and (Test-Path $ScriptPath -ErrorAction SilentlyContinue)) {
                                            try {
                                                $logMsg = "[$timestamp] Attempting auto-approval with Python script..."
                                                Add-Content -Path $LogFile -Value $logMsg -ErrorAction SilentlyContinue

                                                Start-Process -FilePath $VenvPath -ArgumentList "`"$ScriptPath`" `"$url`"" -NoNewWindow -Wait:$false -ErrorAction Stop

                                                $successMsg = "[$timestamp] Python script launched successfully"
                                                Add-Content -Path $LogFile -Value $successMsg -ErrorAction SilentlyContinue
                                            } catch {
                                                $errMsg = "[$timestamp] Failed to launch Python script: $_"
                                                Add-Content -Path $LogFile -Value $errMsg -ErrorAction SilentlyContinue

                                                # Fallback to browser
                                                try {
                                                    Start-Process $url -ErrorAction Stop
                                                    $browserMsg = "[$timestamp] Opened URL in browser"
                                                    Add-Content -Path $LogFile -Value $browserMsg -ErrorAction SilentlyContinue
                                                } catch {
                                                    $browserErrMsg = "[$timestamp] Failed to open browser: $_"
                                                    Add-Content -Path $LogFile -Value $browserErrMsg -ErrorAction SilentlyContinue
                                                }
                                            }
                                        } else {
                                            # No Python, just open browser
                                            try {
                                                $browserMsg = "[$timestamp] Opening URL in browser: $url"
                                                Add-Content -Path $LogFile -Value $browserMsg -ErrorAction SilentlyContinue

                                                Start-Process $url -ErrorAction Stop

                                                $successMsg = "[$timestamp] Browser launched successfully"
                                                Add-Content -Path $LogFile -Value $successMsg -ErrorAction SilentlyContinue
                                            } catch {
                                                $errMsg = "[$timestamp] Failed to open browser: $_"
                                                Add-Content -Path $LogFile -Value $errMsg -ErrorAction SilentlyContinue
                                            }
                                        }

                                        $urlFound = $true
                                        break
                                    }
                                }
                            }
                        } catch {
                            # File might be locked, wait and retry
                        }

                        Start-Sleep -Seconds 2

                        # Exit after 2 minutes of monitoring
                        if ($elapsed -gt 120) {
                            break
                        }
                        $elapsed += 2
                    }
                } catch {
                    # Silently ignore errors in monitoring job
                }
            } -ArgumentList $sshOutputFile, $PYTHON_VENV_PATH, $PYTHON_SCRIPT_PATH, $script:LOG_FILE

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
        Write-ErrorLog "SSH connection error: $_"
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
        Write-Log "Process check: PID $sshPid not found: $_" -Debug
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

        if (-not $processRunning -or -not $tunnelActive) {
            if (-not $processRunning) {
                Write-ErrorLog "SSH process has stopped"
            }
            if (-not $tunnelActive) {
                Write-ErrorLog "Port forwarding is inactive"
            }

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
        $errorMsg = "Unexpected error in main loop: $_ | $($_.Exception.Message) | Line: $($_.InvocationInfo.ScriptLineNumber)"
        Write-ErrorLog $errorMsg
        Write-Host "[CRITICAL] $errorMsg" -ForegroundColor Magenta
        Start-Sleep -Seconds 10
        # Reset SSH process on critical error
        $sshProcess = $null
    }
}
