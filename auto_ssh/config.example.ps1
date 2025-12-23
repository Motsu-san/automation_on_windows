### Configuration file for SSH Auto Reconnect Script
# This file contains all configurable parameters

# SSH Connection Settings
$SSH_HOST = "XXX_rdp"  # Host name defined in ~/.ssh/config
$CHECK_INTERVAL = 30  # Connection check interval (seconds)
$RECONNECT_DELAY = 5  # Wait time before reconnect (seconds)
$MAX_RETRIES = 3  # Maximum consecutive retry count

# Logging Settings
$LOG_DIR = "$env:USERPROFILE\automation_on_windows\auto_ssh\logs"
$LOG_RETENTION_DAYS = 7  # Number of days to keep log files
$DEBUG_MODE = $false  # Enable detailed debug logs (true/false)

# Python Environment Settings (for Cloudflare auto-approval)
$PYTHON_VENV_PATH = "$env:USERPROFILE\venv\your_venv_name\Scripts\python.exe"

# Export configuration as a hashtable for easy access
$Config = @{
    SSH_HOST = $SSH_HOST
    CHECK_INTERVAL = $CHECK_INTERVAL
    RECONNECT_DELAY = $RECONNECT_DELAY
    MAX_RETRIES = $MAX_RETRIES
    LOG_DIR = $LOG_DIR
    LOG_RETENTION_DAYS = $LOG_RETENTION_DAYS
    DEBUG_MODE = $DEBUG_MODE
    PYTHON_VENV_PATH = $PYTHON_VENV_PATH
}
