@echo off
chcp 932
setlocal EnableDelayedExpansion

:: ログ設定
set LOGDIR=logs
set LOGFILE=application_%date:~0,4%%date:~5,2%%date:~8,2%.log
set MAX_LOG_SIZE=1048576
set KEEP_DAYS=7
set MAX_LOGS=10
set IS_GPU_CONNECTED=0

cd /d %~dp0

:: 仮想環境のアクティベーションスクリプトのパス
for /f "usebackq tokens=1,2 delims==" %%A in (".env") do (
    set "%%A=%%B"
)
:: 同一 venv: activate 由来の「python」が PATH 上の別物でない保証のため、Scripts\python.exe を明示する
:: ※ 直後の展開に %VENV% は使えない（パースで空）ので遅延 ! を使う
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

:: Administrator Authority Check
NET SESSION >nul 2>&1
if %errorLevel% neq 0 (
    call :WriteLog "Administrative privileges are required."
    call :WriteLog "Right click and select “Run as administrator”."
    pause
    exit /b 1
)

call :WriteLog "================================"
call :WriteLog "Start eGPU activation script..."

if not exist "!VENV_PYTHON!" (
    call :WriteLog "FATAL: Venv Python not found. Expected: !VENV_PYTHON!"
    call :WriteLog "Fix VENV_ACTIVATION_PATH in .env (e.g. ...\Scripts\activate) or create the venv."
    call :WriteLog "処理が完了しました。"
    exit /b 1
)
call :WriteLog "Python.exe used for get_gpu: !VENV_PYTHON!"

call %VENV_ACTIVATION_PATH%

:: Python 結果は last_pnp_id.txt / last_gpu_status.txt（UTF-8 1 行）に出す。
:: stdout を for /f で扱うと PNP 文字列中の & で cmd 側の解釈が壊れ空になる。
:: ここは必ず venv の python.exe。単に「python」と書くと別インタプリタ（未 pip）になる場合がある
"!VENV_PYTHON!" get_gpu_instance_id.py 2> "%LOGDIR%\get_gpu_instance_id.debug.log"
if %errorlevel% neq 0 (
    call :WriteLog "get_gpu_instance_id.py failed. See get_gpu_instance_id.debug.log in logs\."
    call :WriteLog "If ModuleNotFoundError wmi:  !VENV_PYTHON!  -m pip install WMI==1.5.1"
    call :WriteLog "処理が完了しました。"
    exit /b 1
)
if not exist "last_pnp_id.txt" (
    call :WriteLog "last_pnp_id.txt missing after Python success."
    call :WriteLog "処理が完了しました。"
    exit /b 1
)
if not exist "last_gpu_status.txt" (
    call :WriteLog "last_gpu_status.txt missing after Python success."
    call :WriteLog "処理が完了しました。"
    exit /b 1
)
for /f "usebackq delims=" %%i in ("last_pnp_id.txt") do set "GPU_INSTANCE_ID=%%i"
for /f "usebackq" %%A in ("last_gpu_status.txt") do set "IS_GPU_CONNECTED=%%A"

:: 最終行の PNPDeviceID と .env の機種ID（ログで突き合わせ用）
call :WriteLog "----- GPU ID (for verification)"
call :WriteLog "MY_GPU_HARDWARE_ID (.env): !MY_GPU_HARDWARE_ID!"
call :WriteLog "PNPDeviceID (resolved, passed to PowerShell): !GPU_INSTANCE_ID!"
call :WriteLog "IS_GPU_CONNECTED: !IS_GPU_CONNECTED!  (1=接続+StatusOK)"

if "!GPU_INSTANCE_ID!"=="" (
    call :WriteLog "Failed: PNPDeviceID is empty after reading last_pnp_id.txt."
    call :WriteLog "処理が完了しました。"
    exit /b 1
)
if "!GPU_INSTANCE_ID!"=="None" (
    call :WriteLog "Failed: invalid PNP id in file."
    call :WriteLog "処理が完了しました。"
    exit /b 1
)
call :WriteLog "Successfully retrieved my GPU instance ID."


:: デバイスの状態を確認と有効化
if "%1"=="1" (
    if %IS_GPU_CONNECTED%==0 (
        call :WriteLog "GPUは既に無効です。"
    ) else (
        call :WriteLog "デバイスを検索して無効化を試みています..."
        powershell -ExecutionPolicy Bypass -File "disable_gpu.ps1" -DeviceInstanceId "!GPU_INSTANCE_ID!"
        if %errorLevel% equ 0 (
            call :WriteLog "デバイスの無効化に成功しました。"
        ) else (
            call :WriteLog "デバイスの無効化に失敗しました。"
            call :WriteLog "エラーコード: %errorLevel%"
        )
    )
) else (
    if %IS_GPU_CONNECTED%==0 (
        call :WriteLog "デバイスを検索して有効化を試みています..."
        powershell -ExecutionPolicy Bypass -File "reset_gpu.ps1" -DeviceInstanceId "!GPU_INSTANCE_ID!"
        if %errorLevel% equ 0 (
            call :WriteLog "デバイスの有効化に成功しました。"
        ) else (
            call :WriteLog "デバイスの有効化に失敗しました。"
            call :WriteLog "エラーコード: %errorLevel%"
        )
    ) else (
        call :WriteLog "GPUは既に有効です。"
    )
)

call :WriteLog "処理が完了しました。"

endlocal


:: ログ出力とサイズチェックを行う関数
:WriteLog
if "%~1"=="" (
    echo エラー: ログメッセージが指定されていません
    exit /b 1
)
set "MESSAGE=%~1"
echo !MESSAGE!
echo [%date% %time%] !MESSAGE! >> %LOGDIR%\%LOGFILE%

:: サイズチェック
for %%F in (%LOGDIR%\%LOGFILE%) do set SIZE=%%~zF
if !SIZE! geq %MAX_LOG_SIZE% (
    set "TIMESTAMP=%time::=-%"
    set "TIMESTAMP=!TIMESTAMP: =0!"
    ren %LOGDIR%\%LOGFILE% "enable_egpu_powershell_%date:~0,4%%date:~5,2%%date:~8,2%_!TIMESTAMP!.log"
)
exit /b 0
