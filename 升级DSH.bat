@echo off
rem DSH Portable - one-click kernel upgrade (backs up data/ automatically).
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0upgrade.ps1" %*
echo.
echo Upgrade finished. Press any key to close...
pause >nul
