"""
Cloudflare Access Auto-Approval Script using Playwright
Usage: python cloudflare_approve.py <auth_url>
"""

import sys
import time
from playwright.sync_api import sync_playwright, TimeoutError as PlaywrightTimeout


def approve_cloudflare_access(auth_url: str, timeout: int = 30) -> bool:
    """
    Open Cloudflare authentication page and click Approve button

    Args:
        auth_url: Cloudflare authentication URL
        timeout: Maximum wait time in seconds (default: 30)

    Returns:
        True if approval succeeded, False otherwise
    """
    print(f"[INFO] Opening Cloudflare authentication page...")
    print(f"[INFO] URL: {auth_url}")

    try:
        with sync_playwright() as p:
            # Launch browser (headless=False to see what's happening)
            browser = p.chromium.launch(headless=False)
            context = browser.new_context()
            page = context.new_page()

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

            # Close browser
            browser.close()

            return approved

    except Exception as e:
        print(f"[ERROR] Failed to approve Cloudflare access: {e}")
        import traceback
        traceback.print_exc()
        return False


def main():
    if len(sys.argv) < 2:
        print("Usage: python cloudflare_approve.py <auth_url>")
        print("Example: python cloudflare_approve.py https://example.cloudflareaccess.com/cdn-cgi/access/cli")
        sys.exit(1)

    auth_url = sys.argv[1]

    print("=" * 60)
    print("Cloudflare Access Auto-Approval Script")
    print("=" * 60)

    success = approve_cloudflare_access(auth_url)

    if success:
        print("[SUCCESS] Cloudflare authentication approved")
        sys.exit(0)
    else:
        print("[WARNING] Could not automatically approve - may require manual approval")
        sys.exit(1)


if __name__ == "__main__":
    main()
