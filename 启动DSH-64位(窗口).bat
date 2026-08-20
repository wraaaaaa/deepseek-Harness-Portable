@echo off
rem DSH Portable - 64-bit window entry (Electron)
setlocal
cd /d "%~dp0"
if not exist "%~dp0electron\electron.exe" goto missing
start "" "%~dp0electron\electron.exe" "%~dp0shell"
exit /b

:missing
echo [DSH] electron.exe not found. Please re-extract the full package.
pause
exit /b 1
