@echo off
rem DSH Portable - smart launcher: x64 -> Electron window, x86 -> browser mode
setlocal
cd /d "%~dp0"

rem Detect the OS architecture (handle cmd running under WOW64).
set "ARCH=%PROCESSOR_ARCHITECTURE%"
if /i "%ARCH%"=="x86" if defined PROCESSOR_ARCHITEW6432 set "ARCH=%PROCESSOR_ARCHITEW6432%"

if /i "%ARCH%"=="AMD64" goto x64
if /i "%ARCH%"=="ARM64" goto x64
goto x86

:x64
if not exist "%~dp0electron\electron.exe" goto missing
start "" "%~dp0electron\electron.exe" "%~dp0shell"
exit /b

:x86
if not exist "%~dp0node\win-x86\node.exe" goto missing
start "DSH 32-bit" "%~dp0node\win-x86\node.exe" "%~dp0shell\browser-launch.js"
exit /b

:missing
echo [DSH] Missing runtime files. Please re-extract the full package.
pause
exit /b 1
