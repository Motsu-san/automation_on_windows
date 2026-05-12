# Network Connection Check Script
# Checks connection for up to 2 minutes and records a custom event on success
#
# NOTE: In Task Scheduler, use a trigger: "On an event" → Log: Security, Source:
# Microsoft-Windows-Security-Auditing, Event ID: 4801 (Workstation Unlock). Run this
# script (or a wrapper) as the task action.
# This task requires Event ID 4801 (Workstation Unlock) to be logged.
# By default, this event may NOT be recorded due to audit policy settings.
#
# To enable it, configure the following audit policy:
#   secpol.msc
#   → Advanced Audit Policy Configuration
#   → Logon/Logoff
#   → "Audit Other Logon/Logoff Events" → Check "Success"
#
# Without this setting, the task scheduler trigger on Event ID 4801
# will never fire, even if the trigger is enabled.

# Configuration
$targetAddress = "1.1.1.1"         # Primary target (Internet connectivity)
$sshHost = "dpc2302001_rdp"        # SSH host to check (optional, uses ~/.ssh/config)
$maxDurationSeconds = 43200          # Maximum check duration (seconds)
$checkIntervalSeconds = 5          # Check interval (seconds)
$eventSource = "NetworkMonitor"    # Event source name
$eventIdSuccess = 1001             # Event ID for network connection success
$eventIdSshReachable = 1002        # Event ID for SSH host reachable
$eventIdFailure = 1003             # Event ID for connection failure

# Logging configuration
$logDir = Join-Path $PSScriptRoot "logs"
$logRetentionDays = 14                  # Delete NetworkCheck_*.log files older than this at startup

# Ensure log directory exists
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

# Remove log files older than retention (2 weeks)
$logCutoff = (Get-Date).AddDays(-$logRetentionDays)
Get-ChildItem -Path $logDir -File -Filter "NetworkCheck_*.log" -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -lt $logCutoff } |
    Remove-Item -Force -ErrorAction SilentlyContinue

# Log path: append to today's file if present, otherwise create a new timestamped file
$logDayStamp = Get-Date -Format "yyyyMMdd"
$todayLogFilter = "NetworkCheck_$logDayStamp*.log"
$todayLogs = @(Get-ChildItem -Path $logDir -File -Filter $todayLogFilter -ErrorAction SilentlyContinue)
if ($todayLogs.Count -gt 0) {
    $logFile = ($todayLogs | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
} else {
    $logFile = Join-Path $logDir ("NetworkCheck_" + $logDayStamp + "_" + (Get-Date -Format "HHmmss") + ".log")
}

# Function to write log messages to both console and file
function Write-Log {
    param(
        [string]$Message,
        [string]$ForegroundColor = "White"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] $Message"
    Write-Host $logMessage -ForegroundColor $ForegroundColor
    Add-Content -Path $logFile -Value $logMessage
}

# Check if event source exists (should be registered via Register-EventSource.ps1)
try {
    $sourceExists = [System.Diagnostics.EventLog]::SourceExists($eventSource)
} catch {
    # If SourceExists fails due to access issues, assume source doesn't exist
    $sourceExists = $false
    Write-Log "Warning: Could not verify event source due to access restrictions. Assuming source does not exist." "Yellow"
}

if (-not $sourceExists) {
    Write-Log "ERROR: Event source '$eventSource' is not registered." "Red"
    Write-Log "Please run 'Register-EventSource.ps1' as administrator first." "Yellow"
    exit 1
}

# Function to test SSH host reachability
function Test-SSHHostReachable {
    param($HostName)
    try {
        # Try to resolve SSH host from config
        $sshConfig = Get-Content "$env:USERPROFILE\.ssh\config" -ErrorAction SilentlyContinue
        if ($sshConfig) {
            $hostEntry = $sshConfig | Select-String -Pattern "Host $HostName" -Context 0,5
            if ($hostEntry) {
                $hostname = ($hostEntry.Context.PostContext | Select-String -Pattern "HostName").ToString().Split()[-1]
                if ($hostname) {
                    $result = Test-Connection -ComputerName $hostname -Count 1 -Quiet -ErrorAction SilentlyContinue
                    return $result
                }
            }
        }
        return $false
    } catch {
        return $false
    }
}

# Record start time
$startTime = Get-Date
Write-Log "Starting network connection check: $targetAddress"
if ($sshHost) {
    Write-Log "SSH host to check: $sshHost"
}
Write-Log "Maximum check duration: $maxDurationSeconds seconds"

# Check loop
$connected = $false
while (((Get-Date) - $startTime).TotalSeconds -lt $maxDurationSeconds) {
    Write-Log "Checking connection... ($(((Get-Date) - $startTime).TotalSeconds.ToString('0.0')) seconds elapsed)"

    # Connection test
    $result = Test-Connection -ComputerName $targetAddress -Count 1 -Quiet -ErrorAction SilentlyContinue

    if ($result) {
        $connected = $true
        $elapsedTime = ((Get-Date) - $startTime).TotalSeconds.ToString('0.2')
        Write-Log "Network connection successful! (after $elapsedTime seconds)" "Green"

        # Write network connection success event
        $message = "Successfully connected to network address '$targetAddress'. Elapsed time: $elapsedTime seconds"
        try {
            Write-EventLog -LogName Application -Source $eventSource -EventId $eventIdSuccess -EntryType Information -Message $message
            Write-Log "Recorded network connection event (EventID: $eventIdSuccess)" "Green"
        } catch {
            Write-Log "Warning: Could not write to event log due to access restrictions. Event: $message" "Yellow"
        }

        # Check SSH host reachability if configured
        if ($sshHost) {
            Write-Log "Checking SSH host reachability: $sshHost" "Cyan"
            $sshReachable = Test-SSHHostReachable -HostName $sshHost

            if ($sshReachable) {
                Write-Log "SSH host is reachable!" "Green"
                $sshMessage = "SSH host '$sshHost' is reachable. Ready for SSH connection."
                try {
                    Write-EventLog -LogName Application -Source $eventSource -EventId $eventIdSshReachable -EntryType Information -Message $sshMessage
                    Write-Log "Recorded SSH reachable event (EventID: $eventIdSshReachable)" "Green"
                } catch {
                    Write-Log "Warning: Could not write to event log due to access restrictions. Event: $sshMessage" "Yellow"
                }
            } else {
                Write-Log "Warning: SSH host is not reachable yet" "Yellow"
            }
        }
        break
    }

    # Wait until next check
    Start-Sleep -Seconds $checkIntervalSeconds
}

# Output result
if (-not $connected) {
    $totalTime = ((Get-Date) - $startTime).TotalSeconds.ToString('0.2')
    Write-Log "Connection failed: Could not connect for $maxDurationSeconds seconds." "Red"

    # Write failure event to event log
    $failureMessage = "Failed to connect to network address '$targetAddress' after $totalTime seconds (timeout: $maxDurationSeconds seconds)."
    try {
        Write-EventLog -LogName Application -Source $eventSource -EventId $eventIdFailure -EntryType Warning -Message $failureMessage
        Write-Log "Recorded connection failure event (EventID: $eventIdFailure)" "Yellow"
    } catch {
        Write-Log "Warning: Could not write to event log due to access restrictions. Event: $failureMessage" "Yellow"
    }

    exit 1
}

exit 0
