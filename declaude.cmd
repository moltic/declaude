@echo off
setlocal
cd /d "%~dp0"
if exist "declaude.exe" (
    "%~dp0declaude.exe"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0declaude.ps1"
)
