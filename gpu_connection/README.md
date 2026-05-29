# gpu_connection

Script to check eGPU status and disable/enable (reset) it.
The GPU sometimes stops being recognized even when connected and enabled; this recovers it by removing and re-scanning the PnP device.

## File Structure

| File | Description |
|---|---|
| `gpu_connection.bat` | Main script. Must be run as Administrator. |
| `get_gpu_instance_id.py` | Uses WMI to get the GPU PNPDeviceID and status, then writes to `last_pnp_id.txt` / `last_gpu_status.txt` |
| `reset_gpu.ps1` | Removes the GPU device and re-scans the PCI bus (for enable/reset) |
| `disable_gpu.ps1` | Removes the GPU device only (for disable) |
| `.env` | Configuration file (create from `.env_sample`) |
| `reset_egpu_connection.lnk` | Shortcut to `gpu_connection.bat` |

## How It Works

1. Reads `VENV_ACTIVATION_PATH` and `MY_GPU_HARDWARE_ID` from `.env`
2. Runs `get_gpu_instance_id.py` with the venv Python to get the GPU PNPDeviceID and status
3. No argument (default): if the GPU is not OK (disabled), runs `reset_gpu.ps1` to reconnect
4. Argument `1`: if the GPU is enabled, runs `disable_gpu.ps1` to disable it

## Environment

Confirmed on Windows 11

- Python 3.12.0
- pip 23.2.1
- Uses venv

## Setup

### 1. Create venv and install packages

```cmd
python -m venv ..\..\venv\[your_venv_dir]
..\..\venv\[your_venv_dir]\Scripts\activate
pip install WMI==1.5.1 python-dotenv
```

### 2. Find your GPU InstanceId

Run the following in PowerShell to find the `InstanceId` of your GPU.

```powershell
Get-PnpDevice -Class Display | Format-List FriendlyName, InstanceId, Status
```

### 3. Create `.env`

Copy `.env_sample` to `.env` and set the following values.

```
VENV_ACTIVATION_PATH=..\..\venv\[your_venv_dir]\Scripts\activate
MY_GPU_HARDWARE_ID=PCI\VEN_XXXX&DEV_XXXX&SUBSYS_XXXXXXXX&REV_XX\...
```

- `VENV_ACTIVATION_PATH`: Path to the venv `activate` script
- `MY_GPU_HARDWARE_ID`: The `InstanceId` found in step 2 (partial match is used, so a unique prefix is also acceptable)

### 4. Run

**Run `gpu_connection.bat` as Administrator** (or run the shortcut `reset_egpu_connection.lnk` as Administrator).

## Logs

- `logs\application_YYYYMMDD.log`: Main log (rotated with a timestamped filename when it exceeds 1 MB)
- `logs\get_gpu_instance_id.debug.log`: Detailed Python script output (for debugging)
- Log files older than 7 days are automatically deleted; at most 10 files are kept

## Troubleshooting

**`ModuleNotFoundError: No module named 'wmi'`**

```cmd
..\..\venv\[your_venv_dir]\Scripts\python.exe -m pip install WMI==1.5.1
```

**GPU not found (`last_pnp_id.txt` not generated)**

Check `logs\get_gpu_instance_id.debug.log` and verify that `MY_GPU_HARDWARE_ID` is a substring of the GPU's PNPDeviceID.
