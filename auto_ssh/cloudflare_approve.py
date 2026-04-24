"""
Cloudflare Access Auto-Approval Script using Playwright
Usage: python cloudflare_approve.py <auth_url> [timeout]
"""

import sys
import time
import tempfile
import os
import shutil
from pathlib import Path
from playwright.sync_api import sync_playwright, TimeoutError as PlaywrightTimeout

# プロファイルディレクトリのパス（永続化してログイン情報を保存）
# 環境変数 BROWSER_PROFILE_DIR でカスタマイズ可能
DEFAULT_PROFILE_DIR = Path(__file__).parent / "browser_profile"
BROWSER_PROFILE_DIR = Path(os.environ.get("BROWSER_PROFILE_DIR", str(DEFAULT_PROFILE_DIR)))

# Windows API imports for window management
try:
    import ctypes
    from ctypes import wintypes
    WINDOWS_API_AVAILABLE = True
except ImportError:
    WINDOWS_API_AVAILABLE = False


def approve_cloudflare_access(auth_url: str, timeout: int) -> bool:
    """
    Open Cloudflare authentication page and click Approve button

    Args:
        auth_url: Cloudflare authentication URL
        timeout: Maximum wait time in seconds

    Returns:
        True if approval succeeded, False otherwise
    """
    print(f"[INFO] Opening Cloudflare authentication page...")
    print(f"[INFO] URL: {auth_url}")

    # 永続的なプロファイルディレクトリを使用（ログイン情報を保存）
    # プロファイルディレクトリが存在しない場合は作成
    user_data_dir = str(BROWSER_PROFILE_DIR)
    BROWSER_PROFILE_DIR.mkdir(parents=True, exist_ok=True)
    print(f"[INFO] Using browser profile: {user_data_dir}")

    try:
        with sync_playwright() as p:
            # Launch browser with isolated user data directory using launch_persistent_context
            # This prevents conflicts with other Playwright scripts running simultaneously
            context = p.chromium.launch_persistent_context(
                user_data_dir=user_data_dir,
                headless=False,
                args=[
                    "--disable-blink-features=AutomationControlled",
                    "--start-maximized",  # Start maximized to ensure visibility
                ],
                viewport=None,  # Use default viewport (full screen)
                ignore_default_args=["--enable-automation"],  # Remove automation flags
            )
            page = context.new_page()
            
            # Bring browser window to front using Windows API
            try:
                import ctypes
                from ctypes import wintypes
                import time
                import sys
                import io
                import contextlib
                
                # Wait a bit for browser to fully start
                time.sleep(2)
                
                # Suppress stderr to avoid Windows API type conversion warnings
                @contextlib.contextmanager
                def suppress_stderr():
                    old_stderr = sys.stderr
                    try:
                        sys.stderr = io.StringIO()
                        yield
                    finally:
                        sys.stderr = old_stderr
                
                # Windows API functions to bring window to front
                user32 = ctypes.windll.user32
                SW_RESTORE = 9
                SW_MAXIMIZE = 3
                
                # Find Chrome/Chromium windows by enumerating all windows
                chrome_windows = []
                
                # Define callback function with proper error handling and return type
                # Use a simple approach that avoids ctypes callback issues
                def enum_windows_proc(hwnd, lParam):
                    # Always return 1 (True) to continue enumeration
                    # Use minimal error checking to avoid ctypes issues
                    try:
                        if hwnd:
                            try:
                                if user32.IsWindowVisible(hwnd):
                                    class_name = ctypes.create_unicode_buffer(512)
                                    if user32.GetClassNameW(hwnd, class_name, 512) > 0:
                                        class_str = class_name.value.lower()
                                        if any(x in class_str for x in ["chrome", "chromium", "chrome_widget"]):
                                            chrome_windows.append(hwnd)
                            except:
                                pass
                    except:
                        pass
                    return 1  # Always return 1 (int) to continue enumeration
                
                # Use WINFUNCTYPE with c_int (BOOL is actually int in Windows API)
                EnumWindowsProc = ctypes.WINFUNCTYPE(ctypes.c_int, wintypes.HWND, wintypes.LPARAM)
                callback = EnumWindowsProc(enum_windows_proc)
                
                # Suppress stderr during window enumeration to avoid type conversion warnings
                with suppress_stderr():
                    try:
                        user32.EnumWindows(callback, 0)
                    except Exception as e:
                        # Only print if it's not a type conversion error
                        if "WNDPROC" not in str(e) and "WPARAM" not in str(e) and "LRESULT" not in str(e):
                            print(f"[DEBUG] Error enumerating windows: {e}")
                
                if chrome_windows:
                    print(f"[INFO] Found {len(chrome_windows)} Chrome/Chromium window(s), bringing to front...")
                    for hwnd in chrome_windows[:3]:  # Process first 3 windows
                        try:
                            # Restore if minimized
                            if user32.IsIconic(hwnd):
                                user32.ShowWindow(hwnd, SW_RESTORE)
                                time.sleep(0.2)
                            # Maximize and bring to front
                            user32.ShowWindow(hwnd, SW_MAXIMIZE)
                            time.sleep(0.2)
                            user32.SetForegroundWindow(hwnd)
                            print(f"[INFO] Brought browser window to front (HWND: {hwnd})")
                        except Exception as e:
                            print(f"[DEBUG] Could not bring window to front: {e}")
                else:
                    print(f"[INFO] Chrome/Chromium windows not found, browser may still be starting...")
            except Exception as e:
                print(f"[DEBUG] Could not bring window to front: {e}")
                import traceback
                traceback.print_exc()

            # Navigate to authentication page
            print(f"[INFO] Navigating to authentication page...")
            page.goto(auth_url, timeout=timeout * 1000)

            # Wait for page to load
            print(f"[INFO] Waiting for page to load...")
            page.wait_for_load_state("networkidle", timeout=timeout * 1000)

            # Check if redirected to Google login
            if "accounts.google.com" in page.url:
                print(f"[INFO] Redirected to Google login page")
                print(f"[INFO] Please complete Google authentication manually...")
                print(f"[INFO] Waiting up to {timeout} seconds for Approve page...")

                # Wait for navigation to Approve page (after Google login)
                try:
                    page.wait_for_url("**/cdn-cgi/access/**", timeout=timeout * 1000)
                    print(f"[INFO] Navigated to Cloudflare Approve page")
                    page.wait_for_load_state("networkidle", timeout=10000)
                except PlaywrightTimeout:
                    print(f"[WARNING] Timeout waiting for Approve page - user may need to complete login manually")
                    # Continue anyway to try finding the button

            # Selectors based on actual Cloudflare Access page
            # <button type="submit" form="code-form" name="action" value="approve" class="Button Button-is-block Button-is-juicy Approve">
            approve_selectors = [
                'button[name="action"][value="approve"]',  # Most specific - matches name and value
                'button.Approve',  # Class name
                'button[type="submit"][form="code-form"]',  # Form and type
                'button:has-text("Approve")',  # Text content
                'button.Button-is-juicy',  # Alternative class
                'button:has-text("Allow")',  # Fallback for different text
            ]

            # Try each selector
            approved = False
            for selector in approve_selectors:
                try:
                    print(f"[INFO] Trying selector: {selector}")
                    button = page.locator(selector).first

                    if button.is_visible(timeout=2000):
                        print(f"[SUCCESS] Found Approve button with selector: {selector}")
                        button.click(timeout=5000)
                        print(f"[SUCCESS] Clicked Approve button")
                        approved = True
                        break
                except PlaywrightTimeout:
                    continue
                except Exception as e:
                    print(f"[DEBUG] Selector {selector} failed: {e}")
                    continue

            if not approved:
                print(f"[WARNING] Could not find Approve button with any known selector")
                print(f"[INFO] Page title: {page.title()}")
                print(f"[INFO] Current URL: {page.url}")

                # Take screenshot for debugging
                screenshot_path = "cloudflare_auth_page.png"
                page.screenshot(path=screenshot_path)
                print(f"[INFO] Screenshot saved to: {screenshot_path}")

                # Wait a bit to allow manual approval if needed
                print(f"[INFO] Waiting 10 seconds for manual approval...")
                time.sleep(10)
            else:
                # Wait for redirect after approval
                print(f"[INFO] Waiting for authentication to complete...")
                time.sleep(3)

            # Close browser context
            try:
                context.close()
            except Exception as close_error:
                print(f"[DEBUG] Error closing browser context: {close_error}")

            return approved

    except Exception as e:
        print(f"[ERROR] Failed to approve Cloudflare access: {e}")
        import traceback
        traceback.print_exc()
        # Return False instead of raising exception to allow main script to continue
        return False
    # プロファイルディレクトリは削除しない（永続化してログイン情報を保存）


def main():
    # Force unbuffered output
    import sys
    sys.stdout.reconfigure(line_buffering=True)
    sys.stderr.reconfigure(line_buffering=True)
    
    # Set up log file if provided as argument
    log_file = None
    log_f = None
    if len(sys.argv) >= 4:
        log_file = sys.argv[3]
        # Redirect stdout and stderr to log file while keeping console output
        class TeeOutput:
            def __init__(self, *files):
                self.files = files
            def write(self, obj):
                for f in self.files:
                    f.write(obj)
                    f.flush()
            def flush(self):
                for f in self.files:
                    f.flush()
        
        if log_file:
            log_f = open(log_file, 'w', encoding='utf-8')
            sys.stdout = TeeOutput(sys.stdout, log_f)
            sys.stderr = TeeOutput(sys.stderr, log_f)
    
    try:
        if len(sys.argv) < 2:
            print("Usage: python cloudflare_approve.py <auth_url> [timeout] [log_file]")
            print("Example: python cloudflare_approve.py https://example.cloudflareaccess.com/cdn-cgi/access/cli")
            print("Example: python cloudflare_approve.py https://example.cloudflareaccess.com/cdn-cgi/access/cli 120")
            sys.exit(1)

        auth_url = sys.argv[1]

        # Get timeout from command line argument, or use default
        timeout = 60  # Default timeout
        if len(sys.argv) >= 3:
            try:
                timeout = int(sys.argv[2])
                if timeout <= 0:
                    print("[ERROR] Timeout must be a positive integer")
                    sys.exit(1)
            except ValueError:
                print("[ERROR] Timeout must be a valid integer")
                sys.exit(1)

        print("=" * 60)
        print("Cloudflare Access Auto-Approval Script")
        print("=" * 60)
        print(f"[INFO] Timeout: {timeout} seconds")

        success = approve_cloudflare_access(auth_url, timeout)

        if success:
            print("[SUCCESS] Cloudflare authentication approved")
            sys.exit(0)
        else:
            print("[WARNING] Could not automatically approve - may require manual approval")
            sys.exit(1)
    finally:
        if log_f:
            log_f.close()


if __name__ == "__main__":
    main()
