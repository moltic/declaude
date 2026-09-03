@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0declaude.ps1"
if %errorlevel% neq 0 (
    echo.
    echo Exited with code %errorlevel%.
    pause
)
