"""
SSH Auto Reconnect Script (Cloudflare Access + RDP Port Forwarding)
Python version - replaces ssh_reconnect.ps1 to fix browser visibility issues
"""

import sys
import os
import subprocess
import time
import threading
import signal
import re
import tempfile
import shutil
from pathlib import Path
from datetime import datetime, timedelta
from typing import Optional, Tuple

# Windows-specific imports
if sys.platform == 'win32':
    import ctypes
    CREATE_NO_WINDOW = 0x08000000  # Windows flag to hide console window
else:
    CREATE_NO_WINDOW = 0

# Windows-specific imports
try:
    import psutil
    PSUTIL_AVAILABLE = True
except ImportError:
    PSUTIL_AVAILABLE = False
    print("[WARNING] psutil not available - process management may be limited")

try:
    from win10toast import ToastNotifier
    TOAST_AVAILABLE = True
except ImportError:
    TOAST_AVAILABLE = False
    print("[WARNING] win10toast not available - notifications disabled")

# Import configuration
try:
    from config import (
        SSH_HOST, CHECK_INTERVAL, HEALTH_CHECK_INTERVAL, RECONNECT_DELAY, MAX_RETRIES,
        LOG_DIR, LOG_RETENTION_DAYS, DEBUG_MODE
    )
except ImportError:
    print("[ERROR] Configuration file (config.py) not found!")
    print("[ERROR] Please copy config.py.example to config.py and configure it.")
    sys.exit(1)

# Cloudflare approval function will be imported after write_log is defined
CLOUDFLARE_SCRIPT_PATH = os.path.join(os.path.dirname(__file__), "cloudflare_approve.py")
CLOUDFLARE_MODULE_AVAILABLE = False
approve_cloudflare_access = None

# Global variables
ssh_process: Optional[subprocess.Popen] = None
monitoring_thread: Optional[threading.Thread] = None
ssh_output_file: Optional[str] = None
log_file: Optional[str] = None
last_notification_time: dict = {}
notification_cooldown = 3  # seconds

# Hide console window on Windows (if running with pythonw.exe, this won't have effect)
# But we'll hide it programmatically as well for extra safety
if sys.platform == 'win32':
    try:
        # Hide console window if it exists
        kernel32 = ctypes.windll.kernel32
        user32 = ctypes.windll.user32

        # Get console window handle
        console_window = kernel32.GetConsoleWindow()
        if console_window:
            # Hide the console window
            user32.ShowWindow(console_window, 0)  # SW_HIDE = 0
    except Exception:
        pass  # Ignore errors - window might already be hidden or not exist

# Force unbuffered output (only if stdout/stderr exist - pythonw.exe doesn't have them)
try:
    if sys.stdout and hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(line_buffering=True)
except (AttributeError, OSError):
    pass  # stdout might not be available (e.g., pythonw.exe)

try:
    if sys.stderr and hasattr(sys.stderr, 'reconfigure'):
        sys.stderr.reconfigure(line_buffering=True)
except (AttributeError, OSError):
    pass  # stderr might not be available (e.g., pythonw.exe)


def setup_logging():
    """Initialize logging directory and file"""
    global log_file

    # Create log directory if it doesn't exist
    try:
        os.makedirs(LOG_DIR, exist_ok=True)
    except Exception as e:
        error_log_dir = os.path.join(os.environ.get("TEMP", os.getcwd()), "ssh_reconnect_error.log")
        error_msg = f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] ERROR: Failed to create log directory: {LOG_DIR}"
        error_msg += f"\n[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] ERROR: {e}"
        try:
            with open(error_log_dir, "a", encoding="utf-8") as f:
                f.write(error_msg + "\n")
                f.flush()
        except:
            pass
        # Try to print, but don't fail if stdout is not available
        try:
            if sys.stdout and sys.stdout is not None:
                print(error_msg)
        except:
            pass
        sys.exit(1)

    # Set up log file
    log_filename = f"ssh_reconnect_{datetime.now().strftime('%Y%m%d')}.log"
    log_file = os.path.join(LOG_DIR, log_filename)

    # Clean up old log files
    try:
        cutoff_date = datetime.now() - timedelta(days=LOG_RETENTION_DAYS)
        for log_path in Path(LOG_DIR).glob("ssh_reconnect_*.log"):
            if datetime.fromtimestamp(log_path.stat().st_mtime) < cutoff_date:
                log_path.unlink()
                # Log to file directly since write_log may not be defined yet
                try:
                    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                    with open(log_file, "a", encoding="utf-8") as f:
                        f.write(f"[{timestamp}] Deleted old log file: {log_path.name}\n")
                        f.flush()
                except:
                    pass
    except Exception as e:
        # Log to file directly
        try:
            timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            with open(log_file, "a", encoding="utf-8") as f:
                f.write(f"[{timestamp}] Warning: Failed to clean up old log files: {e}\n")
                f.flush()
        except:
            pass

    # Load Cloudflare approval module after logging is set up
    _load_cloudflare_module()

    return log_file


def _load_cloudflare_module():
    """Load Cloudflare approval module"""
    global CLOUDFLARE_MODULE_AVAILABLE, approve_cloudflare_access

    if os.path.exists(CLOUDFLARE_SCRIPT_PATH):
        try:
            import importlib.util
            spec = importlib.util.spec_from_file_location("cloudflare_approve", CLOUDFLARE_SCRIPT_PATH)
            cloudflare_module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(cloudflare_module)
            approve_cloudflare_access = cloudflare_module.approve_cloudflare_access
            CLOUDFLARE_MODULE_AVAILABLE = True
            # Log to file instead of print (pythonw.exe doesn't have stdout)
            try:
                if log_file:
                    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                    with open(log_file, "a", encoding="utf-8") as f:
                        f.write(f"[{timestamp}] Cloudflare approval module loaded successfully\n")
                        f.flush()
            except:
                pass
        except Exception as e:
            # Log to file instead of print
            try:
                if log_file:
                    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                    with open(log_file, "a", encoding="utf-8") as f:
                        f.write(f"[{timestamp}] WARNING: Failed to load cloudflare_approve module: {e}\n")
                        f.flush()
            except:
                pass


def write_log(message: str, debug: bool = False, error: bool = False, success: bool = False):
    """Write log message to file and console"""
    if debug and not DEBUG_MODE:
        return

    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    prefix = ""
    if error:
        prefix = "ERROR: "
    elif success:
        prefix = "SUCCESS: "

    log_message = f"[{timestamp}] {prefix}{message}"

    # Write to console (except debug messages) - only if stdout/stderr are available
    if not debug:
        try:
            if error:
                if sys.stderr and sys.stderr is not None:
                    print(log_message, file=sys.stderr)
            else:
                if sys.stdout and sys.stdout is not None:
                    print(log_message)
        except (AttributeError, OSError):
            pass  # stdout/stderr might not be available (e.g., pythonw.exe)

    # Write to log file (this is the most important part)
    try:
        if log_file:
            with open(log_file, "a", encoding="utf-8") as f:
                f.write(log_message + "\n")
                f.flush()  # Ensure data is written immediately
    except Exception as e:
        # Try to log error, but don't fail if we can't
        try:
            if sys.stderr and sys.stderr is not None:
                print(f"[ERROR] Failed to write log: {e}", file=sys.stderr)
        except:
            pass


def show_notification(title: str, message: str, notification_type: str = "Info"):
    """Show Windows notification"""
    if not TOAST_AVAILABLE:
        write_log(f"Notification: {title} - {message}", debug=True)
        return

    # Check cooldown
    unique_id = f"SSH-Reconnect-{notification_type}"
    now = time.time()
    if unique_id in last_notification_time:
        time_since_last = now - last_notification_time[unique_id]
        if time_since_last < notification_cooldown:
            write_log(f"Skipping duplicate notification: {title} (shown {time_since_last:.1f}s ago)", debug=True)
            return

    try:
        toaster = ToastNotifier()
        duration = 5  # seconds
        toaster.show_toast(title, message, duration=duration, threaded=True)
        last_notification_time[unique_id] = now
        write_log(f"Notification displayed: {title}")
    except Exception as e:
        write_log(f"Failed to show notification: {e}", debug=True)


def test_ssh_tunnel_active() -> bool:
    """Check if port 3956 is listening (SSH tunnel is active)"""
    try:
        import socket
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(1)
        result = sock.connect_ex(('localhost', 3956))
        sock.close()
        is_active = result == 0
        write_log(f"Port check: {is_active}", debug=True)
        return is_active
    except Exception as e:
        write_log(f"Port check error: {e}", debug=True)
        write_log(f"Failed to check port 3956 status: {e}", error=True)
        return False


def get_ssh_process() -> Optional["psutil.Process"]:
    """Find SSH process matching target host"""
    if not PSUTIL_AVAILABLE:
        return None

    try:
        matching_processes = []
        for proc in psutil.process_iter(['pid', 'name', 'cmdline']):
            try:
                if proc.info['name'] and 'ssh' in proc.info['name'].lower():
                    cmdline = proc.info['cmdline']
                    if cmdline and SSH_HOST in ' '.join(cmdline):
                        matching_processes.append(proc)
                        write_log(f"Found matching SSH process: PID={proc.info['pid']}, CMDLINE={' '.join(cmdline)}", debug=True)
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                continue

        if len(matching_processes) > 1:
            write_log(f"WARNING: Found {len(matching_processes)} SSH processes matching target host '{SSH_HOST}'", error=True)
            # Return the most recent one
            matching_processes.sort(key=lambda p: p.create_time(), reverse=True)
            return matching_processes[0]
        elif len(matching_processes) == 1:
            return matching_processes[0]

        return None
    except Exception as e:
        write_log(f"Error finding SSH process: {e}", debug=True)
        return None


def cleanup_old_ssh_processes(keep_pid: Optional[int] = None):
    """Clean up old/zombie SSH processes matching target host"""
    if not PSUTIL_AVAILABLE:
        return

    try:
        matching_processes = []
        for proc in psutil.process_iter(['pid', 'name', 'cmdline']):
            try:
                if proc.info['name'] and 'ssh' in proc.info['name'].lower():
                    cmdline = proc.info['cmdline']
                    if cmdline and SSH_HOST in ' '.join(cmdline):
                        if keep_pid and proc.info['pid'] == keep_pid:
                            continue
                        matching_processes.append(proc)
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                continue

        if matching_processes:
            write_log(f"Found {len(matching_processes)} old SSH process(es) matching target host", debug=True)
            for proc in matching_processes:
                try:
                    write_log(f"Cleaning up old SSH process: PID={proc.info['pid']}", debug=True)
                    proc.terminate()
                    time.sleep(0.5)
                    if proc.is_running():
                        proc.kill()
                    write_log(f"Successfully cleaned up old SSH process (PID: {proc.info['pid']})", debug=True)
                except Exception as e:
                    write_log(f"Failed to clean up old SSH process (PID: {proc.info['pid']}): {e}", debug=True)
    except Exception as e:
        write_log(f"Error cleaning up old SSH processes: {e}", debug=True)


def stop_managed_ssh(process: Optional[subprocess.Popen] = None):
    """Stop the SSH process managed by this script"""
    global ssh_process

    if process:
        try:
            ssh_pid = process.pid
            write_log(f"Cleaning up managed SSH connection (PID: {ssh_pid})...")

            # Terminate process
            process.terminate()
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                process.kill()

            time.sleep(0.5)

            # Verify process was terminated
            if PSUTIL_AVAILABLE:
                try:
                    proc = psutil.Process(ssh_pid)
                    write_log(f"SSH process (PID: {ssh_pid}) still running after termination attempt", error=True)
                except psutil.NoSuchProcess:
                    write_log("SSH process terminated")
            else:
                write_log("SSH process terminated")
        except Exception as e:
            write_log(f"Error terminating SSH process: {e}", error=True)

    ssh_process = None


def monitor_ssh_output(output_file: str):
    """Monitor SSH output file for Cloudflare authentication URL"""
    def monitor():
        try:
            # Wait for file to be created (max 30 seconds)
            file_wait_timeout = 30
            file_wait_elapsed = 0
            while not os.path.exists(output_file) and file_wait_elapsed < file_wait_timeout:
                time.sleep(1)
                file_wait_elapsed += 1

            if not os.path.exists(output_file):
                write_log("SSH output file not created within timeout", debug=True)
                return

            time.sleep(2)

            # Monitor for Cloudflare URL
            last_position = 0
            url_found = False
            monitoring_timeout = 120
            monitoring_elapsed = 0
            check_interval = 1

            while not url_found and monitoring_elapsed < monitoring_timeout:
                try:
                    if not os.path.exists(output_file):
                        time.sleep(check_interval)
                        monitoring_elapsed += check_interval
                        continue

                    with open(output_file, 'r', encoding='utf-8', errors='ignore') as f:
                        content = f.read()

                    if not content:
                        time.sleep(check_interval)
                        monitoring_elapsed += check_interval
                        continue

                    # Split content into lines
                    lines = [line.strip() for line in content.split('\n') if line.strip()]

                    # Check if file has grown
                    if len(lines) > last_position:
                        new_lines = lines[last_position:]
                        last_position = len(lines)

                        for line in new_lines:
                            # Match Cloudflare URL
                            match = re.search(r'(https://[^\s\)]+/cdn-cgi/access/cli[^\s\)]+)', line)
                            if match:
                                url = match.group(1)
                                timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                                write_log(f"Found Cloudflare URL in SSH output: {url}")
                                handle_cloudflare_url(url, timestamp)
                                url_found = True
                                break

                    # Log progress every 10 seconds
                    if monitoring_elapsed % 10 == 0:
                        file_size = os.path.getsize(output_file) if os.path.exists(output_file) else 0
                        write_log(f"Monitoring SSH output (elapsed: {monitoring_elapsed}/{monitoring_timeout} seconds, file size: {file_size} bytes, lines: {len(lines)})", debug=True)

                    if url_found:
                        break

                    time.sleep(check_interval)
                    monitoring_elapsed += check_interval

                except Exception as e:
                    write_log(f"Error reading SSH output file: {e}", debug=True)
                    time.sleep(check_interval)
                    monitoring_elapsed += check_interval

            if not url_found:
                timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                file_size = os.path.getsize(output_file) if os.path.exists(output_file) else 0
                write_log(f"Monitoring timeout reached. File size: {file_size} bytes", debug=True)

        except Exception as e:
            timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            write_log(f"MONITORING THREAD ERROR: {e}", error=True)
            import traceback
            write_log(f"MONITORING THREAD TRACEBACK: {traceback.format_exc()}", error=True)

    thread = threading.Thread(target=monitor, daemon=True)
    thread.start()
    return thread


def handle_cloudflare_url(url: str, timestamp: str):
    """Handle Cloudflare authentication URL"""
    write_log(f"Cloudflare authentication required: {url}")
    show_notification("Cloudflare Authentication Required", "Please complete authentication in your browser", "CloudflareAuth")

    # Try auto-approval using imported function
    # Since we're calling it directly from Python, browser window will be visible
    if CLOUDFLARE_MODULE_AVAILABLE and approve_cloudflare_access:
        try:
            write_log("Attempting auto-approval with Cloudflare approval function...")
            # Suppress stderr temporarily to avoid Windows API errors from being displayed
            import sys
            import io
            import contextlib

            # Create a context manager to suppress stderr
            @contextlib.contextmanager
            def suppress_stderr():
                old_stderr = sys.stderr
                try:
                    sys.stderr = io.StringIO()
                    yield
                finally:
                    stderr_output = sys.stderr.getvalue()
                    sys.stderr = old_stderr
                    # Only log non-Windows API errors
                    if stderr_output:
                        # Filter out Windows API type conversion warnings
                        filtered_output = []
                        for line in stderr_output.split('\n'):
                            if line.strip() and "WNDPROC" not in line and "WPARAM" not in line and "TypeError" not in line:
                                filtered_output.append(line)
                        if filtered_output:
                            write_log(f"Cloudflare approval stderr: {''.join(filtered_output)}", debug=True)

            with suppress_stderr():
                success = approve_cloudflare_access(url, timeout=120)

            if success:
                write_log("Cloudflare authentication approved automatically", success=True)
                return
            else:
                write_log("Auto-approval failed, browser should be open for manual approval", debug=True)
        except Exception as e:
            write_log(f"Auto-approval error: {e}", error=True)
            import traceback
            write_log(f"Auto-approval traceback: {traceback.format_exc()}", debug=True)
            # Continue execution even if auto-approval fails
    else:
        write_log("Cloudflare approval module not available, opening URL in browser", debug=True)

    # Fallback: Open URL in default browser
    try:
        import webbrowser
        webbrowser.open(url)
        write_log(f"Opened URL in browser: {url}")
    except Exception as e:
        write_log(f"Failed to open browser: {e}", error=True)


def connect_ssh(retry_count: int = 0, previous_process: Optional[subprocess.Popen] = None) -> Optional[subprocess.Popen]:
    """Establish SSH connection"""
    global ssh_process, ssh_output_file, monitoring_thread

    if retry_count > 0:
        write_log(f"Reconnect attempt {retry_count}/{MAX_RETRIES}...")
    else:
        write_log("Starting SSH connection...")

    # Clean up previous process
    stop_managed_ssh(previous_process)

    # Clean up old SSH processes
    cleanup_old_ssh_processes()

    try:
        # Create temporary file for SSH output monitoring
        ssh_output_file = os.path.join(tempfile.gettempdir(), f"ssh_output_{os.getpid()}_{int(time.time())}.log")

        # Start SSH connection
        ssh_command = ["ssh", "-N", SSH_HOST]
        write_log(f"Command: {' '.join(ssh_command)}")

        # Start SSH process with stderr redirected to file
        try:
            with open(ssh_output_file, 'w', encoding='utf-8') as f:
                process = subprocess.Popen(
                    ssh_command,
                    stderr=f,
                    stdout=subprocess.DEVNULL,
                    creationflags=CREATE_NO_WINDOW if sys.platform == 'win32' else 0
                )
        except Exception as e:
            write_log(f"Failed to start SSH process: {e}", error=True)
            return None

        write_log(f"SSH process started (PID: {process.pid})")
        write_log(f"SSH output file: {ssh_output_file}", debug=True)

        # Start monitoring thread
        monitoring_thread = monitor_ssh_output(ssh_output_file)
        write_log("SSH output monitoring started", debug=True)

        # Wait for connection to establish (max 120 seconds)
        write_log("Waiting for SSH connection and port forwarding to establish...")
        wait_count = 0
        max_wait = 120

        while wait_count < max_wait and not test_ssh_tunnel_active():
            time.sleep(1)
            wait_count += 1

            # Show progress every 10 seconds
            if wait_count % 10 == 0:
                write_log(f"Still waiting... ({wait_count}/{max_wait} seconds elapsed)")
                # Check if process is still alive
                if process.poll() is not None:
                    write_log(f"SSH process (PID: {process.pid}) terminated unexpectedly during connection wait", error=True)
                    return None
                write_log(f"SSH process still running (PID: {process.pid})", debug=True)

        if test_ssh_tunnel_active():
            write_log("SSH connection established, port forwarding (3956 -> RDP 3389) is active", success=True)

            # Show success notification
            if retry_count == 0:
                show_notification("SSH Connection Established", "SSH connection established successfully\nPort forwarding: 3956 -> RDP 3389", "Success")
            else:
                show_notification("SSH Reconnected", "SSH connection re-established successfully\nPort forwarding: 3956 -> RDP 3389", "Success")

            ssh_process = process
            return process
        else:
            write_log(f"Failed to establish port forwarding after {max_wait} seconds (may require Cloudflare authentication)", error=True)
            process.terminate()
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                process.kill()
            return None

    except Exception as e:
        write_log(f"SSH connection error: {e}", error=True)
        import traceback
        write_log(f"SSH connection error details: {traceback.format_exc()}", debug=True)
        return None


def test_process_running(process: Optional[subprocess.Popen]) -> bool:
    """Check if SSH process is running"""
    if process is None:
        write_log("Process check: Process is None", debug=True)
        return False

    try:
        if process.poll() is None:
            write_log(f"Process check: PID {process.pid} is running", debug=True)
            return True
        else:
            write_log(f"Process check: PID {process.pid} is not running (exit code: {process.returncode})", debug=True)
            return False
    except Exception as e:
        write_log(f"Process check error: {e}", debug=True)
        return False


def cleanup():
    """Cleanup function for signal handlers"""
    global ssh_process, ssh_output_file

    write_log("Cleaning up...", debug=True)

    # Stop SSH process
    if ssh_process:
        stop_managed_ssh(ssh_process)

    # Clean up temporary files
    if ssh_output_file and os.path.exists(ssh_output_file):
        try:
            os.remove(ssh_output_file)
        except:
            pass


def main():
    """Main loop"""
    global ssh_process

    # Set up logging
    setup_logging()

    # Register cleanup handlers
    signal.signal(signal.SIGINT, lambda s, f: cleanup() or sys.exit(0))
    signal.signal(signal.SIGTERM, lambda s, f: cleanup() or sys.exit(0))

    # Print startup information
    write_log("=" * 50)
    write_log("SSH auto reconnect script started")
    write_log("=" * 50)
    write_log(f"Target host: {SSH_HOST}")
    write_log(f"SSH config: {os.path.expanduser('~/.ssh/config')}")
    write_log("Port forwarding: localhost:3956 -> RDP 3389")
    write_log(f"Check interval: {CHECK_INTERVAL} seconds (health check: {HEALTH_CHECK_INTERVAL} seconds)")
    write_log(f"Log file: {log_file}")
    write_log("=" * 50)

    ssh_process = None
    consecutive_failures = 0
    connection_status_logged = False  # Track if we've logged connection status

    # Initial connection
    ssh_process = connect_ssh()
    if ssh_process is None:
        write_log(f"Initial connection failed. Retrying in {RECONNECT_DELAY} seconds...", error=True)
        time.sleep(RECONNECT_DELAY)

    write_log("Note: Other SSH connections (e.g. VS Code) are not affected")

    # Main loop
    while True:
        try:
            write_log("Starting health check...", debug=True)

            # Check both process and port forwarding
            write_log("Checking process status...", debug=True)
            process_running = test_process_running(ssh_process)
            write_log(f"Process running: {process_running}", debug=True)

            write_log("Checking tunnel status...", debug=True)
            tunnel_active = test_ssh_tunnel_active()
            write_log(f"Tunnel active: {tunnel_active}", debug=True)

            if not process_running:
                write_log("SSH process has stopped", error=True)
                show_notification("SSH Connection Lost", "SSH process has stopped\nAttempting to reconnect...", "Warning")

            if not tunnel_active:
                write_log("Port forwarding is inactive", error=True)

            if not process_running or not tunnel_active:
                consecutive_failures += 1

                if consecutive_failures <= MAX_RETRIES:
                    write_log(f"Attempting to reconnect... (Failures: {consecutive_failures}/{MAX_RETRIES})")
                    time.sleep(RECONNECT_DELAY)
                    previous_process = ssh_process
                    ssh_process = connect_ssh(retry_count=consecutive_failures, previous_process=previous_process)

                    if ssh_process is not None and test_ssh_tunnel_active():
                        consecutive_failures = 0
                        write_log("Reconnected successfully", success=True)
                else:
                    write_log(f"Failed {MAX_RETRIES} times consecutively. Waiting {CHECK_INTERVAL} seconds before reset...", error=True)
                    consecutive_failures = 0
                    connection_status_logged = False  # Reset flag to log status after reset
                    time.sleep(CHECK_INTERVAL)
            else:
                # Connection is stable
                if consecutive_failures > 0:
                    write_log("Connection is stable", success=True)
                    consecutive_failures = 0
                    connection_status_logged = False  # Reset flag after reconnection

                # Show connection status only once (first time after connection is established)
                if not connection_status_logged:
                    ssh_pid = ssh_process.pid if ssh_process else 'N/A'
                    write_log(f"Connection status: OK (PID: {ssh_pid}, Port: 3956 forwarding active)")
                    connection_status_logged = True

            # Sleep for health check interval (3 seconds)
            write_log(f"Sleeping for {HEALTH_CHECK_INTERVAL} seconds...", debug=True)
            time.sleep(HEALTH_CHECK_INTERVAL)
            write_log("Sleep completed, starting next check...", debug=True)

        except KeyboardInterrupt:
            write_log("Interrupted by user")
            cleanup()
            sys.exit(0)
        except Exception as e:
            error_msg = f"Unexpected error in main loop: {e}"
            write_log(error_msg, error=True)
            import traceback
            write_log(f"Full exception details: {traceback.format_exc()}", debug=True)
            time.sleep(10)
            # Reset SSH process on critical error
            ssh_process = None
            consecutive_failures = 0


if __name__ == "__main__":
    main()
