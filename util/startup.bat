@echo off
chcp 65001 >NUL

REM Check Google Drive process
tasklist /FI "IMAGENAME eq GoogleDriveFS.exe" 2>NUL | find /I /N "GoogleDriveFS.exe">NUL
if "%ERRORLEVEL%"=="0" (
    echo Google Drive is already running.
) else (
    start "" "%USERPROFILE%\startup\Google Drive.lnk"
)
