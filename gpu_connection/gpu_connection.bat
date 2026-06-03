@echo off
chcp 932
setlocal EnableDelayedExpansion

:: Logging
set LOGDIR=logs
set LOGFILE=application_%date:~0,4%%date:~5,2%%date:~8,2%.log
set MAX_LOG_SIZE=1048576
set KEEP_DAYS=7
set MAX_LOGS=10
set IS_GPU_CONNECTED=0
set "AHK_EXE=%LOCALAPPDATA%\Programs\AutoHotkey\v2\AutoHotkey64.exe"

cd /d %~dp0

:: venv activation script path from .env
for /f "usebackq tokens=1,2 delims==" %%A in (".env") do (
    set "%%A=%%B"
)
:: Same venv: use Scripts\python.exe so we do not run a different "python" on PATH
:: (cannot use %VENV% for this; it is expanded at parse time empty ? use delayed !)
set "VENV_PYTHON=!VENV_ACTIVATION_PATH:activate=python.exe!"
if not exist "!VENV_PYTHON!" set "VENV_PYTHON=!VENV_ACTIVATION_PATH:activate.bat=python.exe!"

:: Create log directory if it does not exist
if not exist %LOGDIR% (
    mkdir %LOGDIR%
)

:: Delete old log files (files older than KEEP_DAYS days)
forfiles /P %LOGDIR% /M *.log /D -%KEEP_DAYS% /C "cmd /c del @path" 2>nul

:: Check limit on number of log files
set "COUNT=0"
for %%F in (%LOGDIR%\*.log) do set /a COUNT+=1
if %COUNT% gtr %MAX_LOGS% (
    for /f "skip=%MAX_LOGS%" %%F in ('dir /B /O-D %LOGDIR%\*.log') do del %LOGDIR%\%%F
)

:: Administrator check
NET SESSION >nul 2>&1
if %errorLevel% neq 0 (
    call :WriteLog "Administrative privileges are required."
    call :WriteLog "Right click the file and select Run as administrator."
    pause
    exit /b 1
)

call :WriteLog "================================"
call :WriteLog "Start eGPU activation script..."

if not exist "!VENV_PYTHON!" (
    call :WriteLog "FATAL: Venv Python not found. Expected: !VENV_PYTHON!"
    call :WriteLog "Fix VENV_ACTIVATION_PATH in .env (e.g. ...\Scripts\activate) or create the venv."
    call :WriteLog "Done."
    exit /b 1
)
call :WriteLog "Python.exe used for get_gpu: !VENV_PYTHON!"

call %VENV_ACTIVATION_PATH%

:: Python writes last_pnp_id.txt / last_gpu_status.txt (one UTF-8 line each).
:: Capturing stdout in "for /f" breaks on & inside PnP strings.
:: Always use venv python.exe: plain "python" may be another interpreter without WMI
"!VENV_PYTHON!" get_gpu_instance_id.py 2> "%LOGDIR%\get_gpu_instance_id.debug.log"
if %errorlevel% neq 0 (
    call :WriteLog "get_gpu_instance_id.py failed. See get_gpu_instance_id.debug.log in logs\."
    call :WriteLog "If ModuleNotFoundError wmi:  !VENV_PYTHON!  -m pip install WMI==1.5.1"
    call :WriteLog "Done."
    exit /b 1
)
if not exist "last_pnp_id.txt" (
    call :WriteLog "last_pnp_id.txt missing after Python success."
    call :WriteLog "Done."
    exit /b 1
)
if not exist "last_gpu_status.txt" (
    call :WriteLog "last_gpu_status.txt missing after Python success."
    call :WriteLog "Done."
    exit /b 1
)
for /f "usebackq delims=" %%i in ("last_pnp_id.txt") do set "GPU_INSTANCE_ID=%%i"
for /f "usebackq" %%A in ("last_gpu_status.txt") do set "IS_GPU_CONNECTED=%%A"

:: Verification: PNP id vs MY_GPU_HARDWARE_ID in .env
call :WriteLog "----- GPU ID (for verification)"
call :WriteLog "MY_GPU_HARDWARE_ID (.env): !MY_GPU_HARDWARE_ID!"
call :WriteLog "PNPDeviceID (resolved, passed to PowerShell): !GPU_INSTANCE_ID!"
call :WriteLog "IS_GPU_CONNECTED: !IS_GPU_CONNECTED!  (1=connected+StatusOK)"

if "!GPU_INSTANCE_ID!"=="" (
    call :WriteLog "Failed: PNPDeviceID is empty after reading last_pnp_id.txt."
    call :WriteLog "Done."
    exit /b 1
)
if "!GPU_INSTANCE_ID!"=="None" (
    call :WriteLog "Failed: invalid PNP id in file."
    call :WriteLog "Done."
    exit /b 1
)
call :WriteLog "Successfully retrieved my GPU instance ID."


:: Device enable/disable
if "%1"=="1" (
    if %IS_GPU_CONNECTED%==0 (
        call :WriteLog "GPU is already disabled."
    ) else (
        call :WriteLog "Locating device and attempting to disable..."
        powershell -ExecutionPolicy Bypass -File "disable_gpu.ps1" -DeviceInstanceId "!GPU_INSTANCE_ID!"
        if %errorLevel% equ 0 (
            call :WriteLog "Device disabled successfully."
        ) else (
            call :WriteLog "Failed to disable the device."
            call :WriteLog "Error code: %errorLevel%"
        )
    )
) else (
    if %IS_GPU_CONNECTED%==0 (
        call :WriteLog "Locating device and attempting to enable..."
        if exist "!AHK_EXE!" start "" /B "!AHK_EXE!" "%~dp0dismiss_loadlibrary_error.ahk"
        powershell -ExecutionPolicy Bypass -File "reset_gpu.ps1" -DeviceInstanceId "!GPU_INSTANCE_ID!"
        if %errorLevel% equ 0 (
            call :WriteLog "Device enabled successfully."
        ) else (
            call :WriteLog "Failed to enable the device."
            call :WriteLog "Error code: %errorLevel%"
        )
    ) else (
        call :WriteLog "GPU is already enabled (connected and Status OK)."
    )
)

call :WriteLog "Done."

endlocal


:: Append a line to the log and rotate the file if it grows too large
:WriteLog
if "%~1"=="" (
    echo Error: no log message
    exit /b 1
)
set "MESSAGE=%~1"
echo !MESSAGE!
echo [%date% %time%] !MESSAGE! >> %LOGDIR%\%LOGFILE%

:: Rotate if at size cap
for %%F in (%LOGDIR%\%LOGFILE%) do set SIZE=%%~zF
if !SIZE! geq %MAX_LOG_SIZE% (
    set "TIMESTAMP=%time::=-%"
    set "TIMESTAMP=!TIMESTAMP: =0!"
    ren %LOGDIR%\%LOGFILE% "enable_egpu_powershell_%date:~0,4%%date:~5,2%%date:~8,2%_!TIMESTAMP!.log"
)
exit /b 0
