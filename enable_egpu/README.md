# enable_egpu
Script to check status and try to disable -> enable, as it sometimes stops even if it is connected and enabled.
Log rotation is a major part of the script.
# Environment
Confirmed with the following environment on Windows11
- Use venv
  - Command `python -m venv ..\..\venv\[your_venv_dir]` on this dir.
- Python 3.12.0
- pip 23.2.1
# How to use
1. Confirm your GPU instanceID with the following command on terminal.
   - `powershell -Command "Get-PnpDevice -Class Display | Format-List FriendlyName, InstanceId, Status"`
2. Edit `MY_GPU_INSTANCE_ID` in get_gpu_instance_id.py
3. Edit `..\..\venv\[your_venv_dir]` path in enable-egpu-powershell.py
4. Run enable-egpu-powershell.bat
