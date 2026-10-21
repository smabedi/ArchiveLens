@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%ArchiveToText.ps1"

if not exist "%PS_SCRIPT%" (
    echo ERROR: ArchiveToText.ps1 was not found in "%SCRIPT_DIR%". 1>&2
    exit /b 1
)

where pwsh.exe >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" %*
    exit /b %ERRORLEVEL%
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" %*
exit /b %ERRORLEVEL%