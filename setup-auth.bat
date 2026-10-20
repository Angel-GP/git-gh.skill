@echo off
rem Convenience wrapper for first-run authentication setup.
rem It still launches everything through start.bat so HOME stays isolated.
setlocal
call "%~dp0start.bat" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\setup-auth.ps1" %*
set "CODE=%ERRORLEVEL%"
echo.
if "%~1"=="" pause
exit /b %CODE%
