### Note: This script is for reference only. Please review before executing.
### Setup Python Environment for Cloudflare Auto-Approval
# This script sets up a Python virtual environment and installs dependencies

$ScriptDir = "$env:USERPROFILE\automation_on_windows\auto_ssh"
$VenvPath = "$ScriptDir\venv"
$RequirementsFile = "$ScriptDir\requirements.txt"

Write-Host "Setting up Python environment for Cloudflare auto-approval..." -ForegroundColor Cyan
Write-Host ""

# Check if Python is installed
try {
    $pythonVersion = python --version 2>&1
    Write-Host "Found Python: $pythonVersion" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Python is not installed or not in PATH" -ForegroundColor Red
    Write-Host "Please install Python from https://www.python.org/downloads/" -ForegroundColor Yellow
    exit 1
}

# Create virtual environment if it doesn't exist
if (!(Test-Path $VenvPath)) {
    Write-Host "Creating virtual environment..." -ForegroundColor Cyan
    python -m venv $VenvPath

    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Failed to create virtual environment" -ForegroundColor Red
        exit 1
    }

    Write-Host "Virtual environment created successfully" -ForegroundColor Green
} else {
    Write-Host "Virtual environment already exists" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Installing dependencies..." -ForegroundColor Cyan

# Activate virtual environment and install dependencies
$ActivateScript = "$VenvPath\Scripts\Activate.ps1"
& $ActivateScript

# Upgrade pip
python -m pip install --upgrade pip

# Install requirements
pip install -r $RequirementsFile

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to install dependencies" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Installing Playwright browsers..." -ForegroundColor Cyan
playwright install chromium

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to install Playwright browsers" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "=" * 60 -ForegroundColor Green
Write-Host "Setup completed successfully!" -ForegroundColor Green
Write-Host "=" * 60 -ForegroundColor Green
Write-Host ""
Write-Host "To test the script, run:" -ForegroundColor Yellow
Write-Host "  python $ScriptDir\cloudflare_approve.py <auth_url>" -ForegroundColor White
Write-Host ""
Write-Host "The SSH reconnect script will automatically use this Python script" -ForegroundColor Cyan
Write-Host "when Cloudflare authentication is required." -ForegroundColor Cyan
