# Network Connection Check Script
# Checks connection for up to 2 minutes and records a custom event on success

# Configuration
$targetAddress = "1.1.1.1"         # Primary target (Internet connectivity)
$sshHost = "dpc2302001_rdp"        # SSH host to check (optional, uses ~/.ssh/config)
$maxDurationSeconds = 120          # Maximum check duration (seconds)
$checkIntervalSeconds = 5          # Check interval (seconds)
$eventSource = "NetworkMonitor"    # Event source name
$eventIdSuccess = 1001             # Event ID for network connection success
$eventIdSshReachable = 1002        # Event ID for SSH host reachable
$eventIdFailure = 1003             # Event ID for connection failure

# Check if event source exists (should be registered via Register-EventSource.ps1)
if (-not [System.Diagnostics.EventLog]::SourceExists($eventSource)) {
    Write-Host "ERROR: Event source '$eventSource' is not registered." -ForegroundColor Red
    Write-Host "Please run 'Register-EventSource.ps1' as administrator first." -ForegroundColor Yellow
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
Write-Host "Starting network connection check: $targetAddress"
if ($sshHost) {
    Write-Host "SSH host to check: $sshHost"
}
Write-Host "Maximum check duration: $maxDurationSeconds seconds"

# Check loop
$connected = $false
while (((Get-Date) - $startTime).TotalSeconds -lt $maxDurationSeconds) {
    Write-Host "Checking connection... ($(((Get-Date) - $startTime).TotalSeconds.ToString('0.0')) seconds elapsed)"

    # Connection test
    $result = Test-Connection -ComputerName $targetAddress -Count 1 -Quiet -ErrorAction SilentlyContinue

    if ($result) {
        $connected = $true
        $elapsedTime = ((Get-Date) - $startTime).TotalSeconds.ToString('0.2')
        Write-Host "Network connection successful! (after $elapsedTime seconds)" -ForegroundColor Green

        # Write network connection success event
        $message = "Successfully connected to network address '$targetAddress'. Elapsed time: $elapsedTime seconds"
        Write-EventLog -LogName Application -Source $eventSource -EventId $eventIdSuccess -EntryType Information -Message $message
        Write-Host "Recorded network connection event (EventID: $eventIdSuccess)" -ForegroundColor Green

        # Check SSH host reachability if configured
        if ($sshHost) {
            Write-Host "Checking SSH host reachability: $sshHost" -ForegroundColor Cyan
            $sshReachable = Test-SSHHostReachable -HostName $sshHost
            
            if ($sshReachable) {
                Write-Host "SSH host is reachable!" -ForegroundColor Green
                $sshMessage = "SSH host '$sshHost' is reachable. Ready for SSH connection."
                Write-EventLog -LogName Application -Source $eventSource -EventId $eventIdSshReachable -EntryType Information -Message $sshMessage
                Write-Host "Recorded SSH reachable event (EventID: $eventIdSshReachable)" -ForegroundColor Green
            } else {
                Write-Host "Warning: SSH host is not reachable yet" -ForegroundColor Yellow
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
    Write-Host "Connection failed: Could not connect for $maxDurationSeconds seconds." -ForegroundColor Red
    
    # Write failure event to event log
    $failureMessage = "Failed to connect to network address '$targetAddress' after $totalTime seconds (timeout: $maxDurationSeconds seconds)."
    Write-EventLog -LogName Application -Source $eventSource -EventId $eventIdFailure -EntryType Warning -Message $failureMessage
    Write-Host "Recorded connection failure event (EventID: $eventIdFailure)" -ForegroundColor Yellow
    
    exit 1
}

exit 0
