"""
Configuration file for SSH Auto Reconnect Script (Python version)
Copy this file to config.py and modify the values as needed.
"""

import os

# SSH Connection Settings
SSH_HOST = "XXX_rdp"  # Host name defined in ~/.ssh/config
CHECK_INTERVAL = 30  # Connection check interval (seconds)
HEALTH_CHECK_INTERVAL = 3  # Health check interval (seconds) - how often to check connection status
RECONNECT_DELAY = 5  # Wait time before reconnect (seconds)
MAX_RETRIES = 3  # Maximum consecutive retry count

# Logging Settings
LOG_DIR = os.path.join(os.path.expanduser("~"), "automation_on_windows", "auto_ssh", "logs")
LOG_RETENTION_DAYS = 7  # Number of days to keep log files
DEBUG_MODE = False  # Enable detailed debug logs (True/False)

# Python Environment Settings (for Cloudflare auto-approval)
# Not needed in Python version - we use the current Python environment
# PYTHON_VENV_PATH is kept for compatibility but not used
