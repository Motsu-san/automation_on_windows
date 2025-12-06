# Network Connection Check Script
# Checks connection for up to 2 minutes and records a custom event on success

# Configuration
$targetAddress = "1.1.1.1"  # Target IP address or hostname to check
$maxDurationSeconds = 120          # Maximum check duration (seconds)
$checkIntervalSeconds = 5          # Check interval (seconds)
$eventSource = "NetworkMonitor"    # Event source name
$eventId = 1001                    # Event ID

# Create event source if it doesn't exist (requires administrator privileges)
if (-not [System.Diagnostics.EventLog]::SourceExists($eventSource)) {
    try {
        New-EventLog -LogName Application -Source $eventSource
        Write-Host "Created event source '$eventSource'."
    }
    catch {
        Write-Host "Warning: Failed to create event source. Please run with administrator privileges." -ForegroundColor Yellow
        Write-Host "Error: $_" -ForegroundColor Red
        exit 1
    }
}

# Record start time
$startTime = Get-Date
Write-Host "Starting network connection check: $targetAddress"
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
        Write-Host "Connection successful! (after $elapsedTime seconds)" -ForegroundColor Green

        # Write custom event to event log
        $message = "Successfully connected to network address '$targetAddress'. Elapsed time: $elapsedTime seconds"
        Write-EventLog -LogName Application -Source $eventSource -EventId $eventId -EntryType Information -Message $message

        Write-Host "Recorded to event log (EventID: $eventId)" -ForegroundColor Green
        break
    }

    # Wait until next check
    Start-Sleep -Seconds $checkIntervalSeconds
}

# Output result
if (-not $connected) {
    $totalTime = ((Get-Date) - $startTime).TotalSeconds.ToString('0.2')
    Write-Host "Connection failed: Could not connect for $maxDurationSeconds seconds." -ForegroundColor Red
    exit 1
}

exit 0
