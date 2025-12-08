### SSH Auto Reconnect Script (Cloudflare Access + RDP Port Forwarding)
# Configuration
$SSH_HOST = "dpc2302001_rdp"  # Host name defined in ~/.ssh/config
$CHECK_INTERVAL = 30  # Connection check interval (seconds)
$RECONNECT_DELAY = 5  # Wait time before reconnect (seconds)
$LOG_FILE = "$env:USERPROFILE\automation_on_windows\auto_ssh\logs\ssh_reconnect.log"
$MAX_RETRIES = 3  # Maximum consecutive retry count

# Ensure log directory exists (extract from $LOG_FILE)
$logDir = Split-Path $LOG_FILE -Parent
if (!(Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir | Out-Null
}

### Log output functions with error handling
function Write-Log {
    param($Message)
    try {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logMessage = "[$timestamp] $Message"
        Write-Host $logMessage -ForegroundColor Cyan
        Add-Content -Path $LOG_FILE -Value $logMessage -ErrorAction SilentlyContinue
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
        Add-Content -Path $LOG_FILE -Value $logMessage -ErrorAction SilentlyContinue
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
        Add-Content -Path $LOG_FILE -Value $logMessage -ErrorAction SilentlyContinue
    } catch {
        Write-Host "[ERROR] Failed to write success log: $_" -ForegroundColor Red
    }
}

### Check if port 3956 is in use (verifies SSH connection is alive)
function Test-SSHTunnelActive {
    try {
        $connections = Get-NetTCPConnection -LocalPort 3956 -State Listen -ErrorAction SilentlyContinue
        return $null -ne $connections
    } catch {
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
        Write-Log "Cleaning up managed SSH connection (PID: $($ProcessToStop.Id)) ..."
        try {
            Stop-Process -Id $ProcessToStop.Id -Force -ErrorAction SilentlyContinue
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
        [System.Diagnostics.Process]$PreviousProcess = $null
    )

    if ($RetryCount -gt 0) {
        Write-Log "Reconnect attempt $RetryCount/$MAX_RETRIES ..."
    } else {
        Write-Log "Starting SSH connection..."
    }

    # Clean up only previous process (do not touch other SSH connections)
    Stop-ManagedSSH -ProcessToStop $PreviousProcess

    try {
        # Start SSH connection in a new window
        $sshCommand = "ssh -N $SSH_HOST"
        Write-Log "Command: $sshCommand"

        # Start SSH connection in a new PowerShell window
        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processInfo.FileName = "ssh.exe"
        $processInfo.Arguments = "-N $SSH_HOST"
        $processInfo.UseShellExecute = $false
        $processInfo.RedirectStandardOutput = $true
        $processInfo.RedirectStandardError = $true
        $processInfo.CreateNoWindow = $false

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $processInfo

        # Monitor error output (for Cloudflare authentication URL detection)
        $errorDataReceived = {
            param($sender, $e)
            if ($e.Data) {
                Write-Log "SSH output: $($e.Data)"
                # Detect Cloudflare authentication URL
                if ($e.Data -match "(https://[^\s]+\.cloudflareaccess\.com[^\s]+)") {
                    $url = $matches[1]
                    Write-Log "Cloudflare authentication URL detected: $url"
                    Write-Log "Opening authentication page in browser and attempting auto-approval..."
                    
                    # Open the Cloudflare authentication page
                    Start-Process $url
                    
                    # Wait for browser window to open and page to fully load
                    try {
                        $shell = New-Object -ComObject WScript.Shell
                        
                        # Wait for browser window with Cloudflare title to appear (max 30 seconds)
                        Write-Log "Waiting for Cloudflare authentication page to load..."
                        $pageLoaded = $false
                        $waitTime = 0
                        $maxPageWait = 30
                        
                        while (-not $pageLoaded -and $waitTime -lt $maxPageWait) {
                            Start-Sleep -Seconds 1
                            $waitTime++
                            
                            # Check if browser window with Cloudflare-related title exists
                            # This approach checks for active window, assuming browser comes to foreground
                            try {
                                $activeWindow = $shell.AppActivate("Cloudflare")
                                if ($activeWindow) {
                                    $pageLoaded = $true
                                    Write-Log "Cloudflare page detected in browser (waited $waitTime seconds)"
                                }
                            } catch {
                                # Window not found yet, continue waiting
                            }
                            
                            # Show progress every 5 seconds
                            if ($waitTime % 5 -eq 0) {
                                Write-Log "Still waiting for page to load... ($waitTime/$maxPageWait seconds)"
                            }
                        }
                        
                        if ($pageLoaded) {
                            # Page is loaded, wait a bit more for JavaScript to render the button
                            Write-Log "Page loaded, waiting for button to render..."
                            Start-Sleep -Seconds 3
                            
                            # Ensure browser window is active
                            $shell.AppActivate("Cloudflare") | Out-Null
                            Start-Sleep -Milliseconds 500
                            
                            # Send Tab keys to navigate to Approve button (adjust count if needed)
                            # Typically 1-3 tabs reach the Approve button
                            1..3 | ForEach-Object {
                                $shell.SendKeys("{TAB}")
                                Start-Sleep -Milliseconds 500
                            }
                            
                            # Press Enter to click the focused button
                            $shell.SendKeys("{ENTER}")
                            Write-Log "Auto-click attempt completed (sent TAB + ENTER keys)"
                        } else {
                            Write-Log "Page load timeout after $maxPageWait seconds, manual approval may be required"
                        }
                        
                        [System.Runtime.Interopservices.Marshal]::ReleaseComObject($shell) | Out-Null
                    } catch {
                        Write-Log "Auto-click failed, manual approval may be required: $_"
                    }
                }
            }
        }

        $process.add_ErrorDataReceived($errorDataReceived)

        $started = $process.Start()
        if ($started) {
            $process.BeginErrorReadLine()
            Write-Log "SSH process started (PID: $($process.Id))"

            # Wait for connection to establish (max 120 seconds to allow for Cloudflare authentication)
            Write-Log "Waiting for SSH connection and port forwarding to establish..."
            $waitCount = 0
            $maxWait = 120
            while ($waitCount -lt $maxWait -and -not (Test-SSHTunnelActive)) {
                Start-Sleep -Seconds 1
                $waitCount++
                # Show progress every 10 seconds
                if ($waitCount % 10 -eq 0) {
                    Write-Log "Still waiting... ($waitCount/$maxWait seconds elapsed)"
                }
            }

            if (Test-SSHTunnelActive) {
                Write-SuccessLog "SSH connection established, port forwarding (3956 -> RDP 3389) is active"
                return $process
            } else {
                Write-ErrorLog "Failed to establish port forwarding after $maxWait seconds (may require Cloudflare authentication)"
                Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
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
        return $false
    }

    try {
        $proc = Get-Process -Id $Process.Id -ErrorAction Stop
        return $true
    } catch {
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
        # Check both process and port forwarding
        $processRunning = Test-ProcessRunning -Process $sshProcess
        $tunnelActive = Test-SSHTunnelActive

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
            Write-Log "Connection status: OK (PID: $($sshProcess.Id), Port: 3956 forwarding active)"
        }

        Start-Sleep -Seconds $CHECK_INTERVAL
    } catch {
        $errorMsg = "Unexpected error in main loop: $_ | $($_.Exception.Message) | Line: $($_.InvocationInfo.ScriptLineNumber)"
        Write-ErrorLog $errorMsg
        Write-Host "[CRITICAL] $errorMsg" -ForegroundColor Magenta
        Start-Sleep -Seconds 10
        # Reset SSH process on critical error
        $sshProcess = $null
    }
}
