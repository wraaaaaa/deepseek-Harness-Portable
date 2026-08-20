@echo off
rem DSH Portable - 32-bit compatibility entry (system browser)
setlocal
cd /d "%~dp0"
if not exist "%~dp0node\win-x86\node.exe" goto missing
start "DSH 32-bit" "%~dp0node\win-x86\node.exe" "%~dp0shell\browser-launch.js"
exit /b

:missing
echo [DSH] node.exe (win-x86) not found. Please re-extract the full package.
pause
exit /b 1
