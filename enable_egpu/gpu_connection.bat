@echo off
chcp 932
setlocal EnableDelayedExpansion

:: ���z���̃A�N�e�B�x�[�V�����X�N���v�g�̃p�X
for /f "usebackq tokens=1,2 delims==" %%A in (".env") do (
    set "%%A=%%B"
)
echo %VENV_ACTIVATION_PATH%

:: ���O�ݒ�
set LOGDIR=logs
set LOGFILE=application_%date:~0,4%%date:~5,2%%date:~8,2%.log
set MAX_LOG_SIZE=1048576
set KEEP_DAYS=7
set MAX_LOGS=10

cd /d %~dp0

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
    call :WriteLog "Right click and select �gRun as administrator�h."
    pause
    exit /b 1
)

call :WriteLog "================================"
call :WriteLog "Start eGPU activation script..."

call %VENV_ACTIVATION_PATH%

:: Python�X�N���v�g�����s���A�o�͂�ϐ��ɕۑ�
for /f "delims=" %%i in ('python get_gpu_instance_id.py') do (
    set GPU_INSTANCE_ID=%%i
    call :WriteLog "!GPU_INSTANCE_ID!"
)

if not "!GPU_INSTANCE_ID!"=="None" (
    call :WriteLog "Successfully retrieved my GPU instance ID."
) else (
    call :WriteLog "Failed to get my GPU instance ID."
    call :WriteLog "�������������܂����B"
    exit /b 1
)

:: �f�o�C�X�̏�Ԃ��m�F�ƗL����
call :WriteLog "�f�o�C�X���������ėL���������݂Ă��܂�..."
    powershell -ExecutionPolicy Bypass -File "reset_gpu.ps1"


if %errorLevel% equ 0 (
    call :WriteLog "�f�o�C�X�̗L�����ɐ������܂����B"
) else (
    call :WriteLog "�f�o�C�X�̗L�����Ɏ��s���܂����B"
    call :WriteLog "�G���[�R�[�h: %errorLevel%"
)

call :WriteLog "�������������܂����B"

endlocal


:: ���O�o�͂ƃT�C�Y�`�F�b�N���s���֐�
:WriteLog
if "%~1"=="" (
    echo �G���[: ���O���b�Z�[�W���w�肳��Ă��܂���
    exit /b 1
)
set "MESSAGE=%~1"
echo !MESSAGE!
echo [%date% %time%] !MESSAGE! >> %LOGDIR%\%LOGFILE%

:: �T�C�Y�`�F�b�N
for %%F in (%LOGDIR%\%LOGFILE%) do set SIZE=%%~zF
if !SIZE! geq %MAX_LOG_SIZE% (
    set "TIMESTAMP=%time::=-%"
    set "TIMESTAMP=!TIMESTAMP: =0!"
    ren %LOGDIR%\%LOGFILE% "enable_egpu_powershell_%date:~0,4%%date:~5,2%%date:~8,2%_!TIMESTAMP!.log"
)
exit /b 0
