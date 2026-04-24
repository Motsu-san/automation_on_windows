#Requires -RunAsAdministrator

# Register Event Source Script
# Registers the "NetworkMonitor" event source for the NetworkCheck.ps1 script

$eventSource = "NetworkMonitor"

# Check if running as administrator
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: This script must be run as administrator." -ForegroundColor Red
    exit 1
}

# Check if event source already exists
if ([System.Diagnostics.EventLog]::SourceExists($eventSource)) {
    Write-Host "Event source '$eventSource' is already registered." -ForegroundColor Green
    exit 0
}

# Register the event source
try {
    New-EventLog -LogName Application -Source $eventSource
    Write-Host "Successfully registered event source '$eventSource'." -ForegroundColor Green
} catch {
    Write-Host "ERROR: Failed to register event source '$eventSource'." -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}