### Chrome Process Killer Script
### Terminates all Chrome processes running in the background

# Log output function
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Host $logMessage

    # Write to log file (optional)
    $logDir = Join-Path $PSScriptRoot "logs"
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    $logFile = Join-Path $logDir "kill_chrome_$(Get-Date -Format 'yyyyMMdd').log"
    try {
        Add-Content -Path $logFile -Value $logMessage -ErrorAction SilentlyContinue
    } catch {
        # Continue even if log file write fails
    }
}

# Search and terminate Chrome processes
function Stop-ChromeProcesses {
    Write-Log "Starting Chrome process search..." "INFO"

    # Get Chrome-related process names
    $chromeProcesses = Get-Process -Name "chrome","chrome.exe","GoogleChrome","GoogleChromePortable" -ErrorAction SilentlyContinue

    if ($null -eq $chromeProcesses -or $chromeProcesses.Count -eq 0) {
        Write-Log "No running Chrome processes found." "INFO"
        return 0
    }

    $processCount = $chromeProcesses.Count
        Write-Log "Found $processCount Chrome process(es)." "INFO"

    # Display information for each process
    foreach ($process in $chromeProcesses) {
        Write-Log "Process ID: $($process.Id), Process Name: $($process.ProcessName), CPU Time: $($process.CPU), Memory Usage: $([math]::Round($process.WorkingSet64 / 1MB, 2)) MB" "INFO"
    }

    # Terminate processes
    Write-Log "Terminating Chrome processes..." "INFO"
    $killedCount = 0
    $failedCount = 0

    foreach ($process in $chromeProcesses) {
        try {
            Stop-Process -Id $process.Id -Force -ErrorAction Stop
            Write-Log "Successfully terminated process ID $($process.Id)." "INFO"
            $killedCount++
        } catch {
            Write-Log "Failed to terminate process ID $($process.Id): $($_.Exception.Message)" "ERROR"
            $failedCount++
        }
    }

    # Display results
    Write-Log "Processing complete: Successfully terminated $killedCount, Failed $failedCount" "INFO"

    # Wait a moment and verify again
    Start-Sleep -Seconds 1
    $remainingProcesses = Get-Process -Name "chrome","chrome.exe","GoogleChrome","GoogleChromePortable" -ErrorAction SilentlyContinue

    if ($null -ne $remainingProcesses -and $remainingProcesses.Count -gt 0) {
        Write-Log "Warning: $($remainingProcesses.Count) Chrome process(es) still remaining. Retrying force termination..." "WARN"
        foreach ($process in $remainingProcesses) {
            try {
                Stop-Process -Id $process.Id -Force -ErrorAction Stop
                Write-Log "Force terminated process ID $($process.Id)." "INFO"
            } catch {
                Write-Log "Failed to force terminate process ID $($process.Id): $($_.Exception.Message)" "ERROR"
            }
        }
    } else {
        Write-Log "All Chrome processes have been successfully terminated." "INFO"
    }

    return $killedCount
}

# Main processing
try {
    Write-Log "=== Chrome Process Termination Script Started ===" "INFO"
    $killed = Stop-ChromeProcesses
    Write-Log "=== Chrome Process Termination Script Completed ===" "INFO"
    exit 0
} catch {
    Write-Log "An error occurred: $($_.Exception.Message)" "ERROR"
    Write-Log "Stack trace: $($_.ScriptStackTrace)" "ERROR"
    exit 1
}
