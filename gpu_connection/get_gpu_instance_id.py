# get_gpu_instance_id.py
# Resolves the PnP device (Win32_PnPEntity) for the configured GPU and returns it.
# Matching uses only MY_GPU_HARDWARE_ID from .env (VEN/DEV/SUBSYS etc. = hardware id prefix).
# If multiple GPUs share the same hardware id, this cannot pick one: do not use in that case.
#
# Piping each stdout line to cmd "for /f" breaks on & inside PnP instance ids.
# Results are written to last_pnp_id.txt and last_gpu_status.txt (UTF-8, one line each) under gpu_connection.
import os
import sys
from dotenv import load_dotenv
from pathlib import Path

try:
    import wmi
except ImportError as e:
    print(f"ImportError: {e}", file=sys.stderr)
    print(f"sys.executable = {sys.executable!r}", file=sys.stderr)
    print(
        'Install in THIS interpreter:  "%s" -m pip install "WMI==1.5.1"'
        % sys.executable,
        file=sys.stderr,
    )
    raise SystemExit(1) from e

SCRIPT_DIR = Path(__file__).resolve().parent
OUT_PNP = SCRIPT_DIR / "last_pnp_id.txt"
OUT_STATUS = SCRIPT_DIR / "last_gpu_status.txt"

load_dotenv(dotenv_path=SCRIPT_DIR / ".env")

# Model id: prefix of PnPDeviceID (part of InstanceId before the first backslash).
my_gpu_hardware_id = os.getenv("MY_GPU_HARDWARE_ID")


def _print_dbg(msg: str) -> None:
    print(msg, file=sys.stderr)


def get_gpu_instance_id():
    if not my_gpu_hardware_id:
        _print_dbg("MY_GPU_HARDWARE_ID is not set in .env")
    try:
        wmi_instance = wmi.WMI()
        display_info = wmi_instance.query("SELECT * FROM Win32_PnPEntity WHERE PNPClass='Display'")
        video_info = wmi_instance.query("SELECT * FROM Win32_VideoController")

        active_gpu = None
        for video in video_info:
            if video.CurrentNumberOfColors is not None:
                active_gpu = video.Caption
        _print_dbg(f"Active GPU: {active_gpu}")
        _print_dbg(f"MY_GPU_HARDWARE_ID: {my_gpu_hardware_id}")

        for display in display_info:
            display_name = display.Caption
            display_device_id = display.PNPDeviceID
            display_status = display.Status
            _print_dbg("Display Info =====")
            _print_dbg(f"Device Name: {display.Name}")
            _print_dbg(f"Device ID: {display.PNPDeviceID}")
            _print_dbg(f"Status: {display.Status}")

            for video in video_info:
                _print_dbg("Video Info =====")
                _print_dbg(f"Device ID: {video.PNPDeviceID}")
                if video.PNPDeviceID in display_device_id:
                    gpu_name = video.Caption
                    _print_dbg(f"{display_name} is connected to {gpu_name}")

            if my_gpu_hardware_id and (my_gpu_hardware_id in display_device_id):
                is_ok = display_status == "OK"
                if is_ok:
                    _print_dbg("My GPU is connected and OK.")
                else:
                    _print_dbg("Something wrong on my GPU")
                return display_device_id, is_ok
            else:
                _print_dbg("ID is not matched.")
                _print_dbg(f"Display Device ID:  {display_device_id}")
                _print_dbg(f"MY_GPU_HARDWARE_ID: {my_gpu_hardware_id}")

    except Exception as e:
        _print_dbg(f"Error: {e}")
        return None, False

    return None, False


if __name__ == "__main__":
    for f in (OUT_PNP, OUT_STATUS):
        try:
            f.unlink()
        except OSError:
            pass

    gpu_id, matched_and_ok = get_gpu_instance_id()
    if gpu_id:
        OUT_PNP.write_text(gpu_id, encoding="utf-8", newline="")
        OUT_STATUS.write_text("1" if matched_and_ok else "0", encoding="utf-8", newline="")
        # Human-readable summary on stderr; the batch file reads last_pnp_id.txt
        _print_dbg(f"Wrote {OUT_PNP.name} (length {len(gpu_id)}) and {OUT_STATUS.name} ({1 if matched_and_ok else 0})")
        sys.exit(0)
    else:
        _print_dbg("Can't get gpu instance id")
        sys.exit(1)
