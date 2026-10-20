@echo off
rem ==========================================================================
rem  git-gh portable launcher
rem  All git/gh commands MUST run through this file so that HOME and
rem  GH_CONFIG_DIR point at this skill's private directories.
rem ==========================================================================
setlocal EnableExtensions DisableDelayedExpansion

set "SKILL_ROOT=%~dp0"
if "%SKILL_ROOT:~-1%"=="\" set "SKILL_ROOT=%SKILL_ROOT:~0,-1%"
set "GITSKILL_ROOT=%SKILL_ROOT%"
set "GITSKILL_HOME=%SKILL_ROOT%\home"

rem --- portable, isolated environment -------------------------------------
set "HOME=%GITSKILL_HOME%"
set "GH_CONFIG_DIR=%GITSKILL_HOME%\gh"
rem Do not inherit host tokens; authenticate through the internal GH_CONFIG_DIR.
set "GH_TOKEN="
set "GITHUB_TOKEN="
set "XDG_CONFIG_HOME=%GITSKILL_HOME%\.config"
set "GIT_CONFIG_GLOBAL=%GITSKILL_HOME%\.gitconfig"
set "GIT_CONFIG_NOSYSTEM=1"
set "GIT_TERMINAL_PROMPT=0"
if /I "%GITSKILL_ALLOW_PROMPT%"=="1" set "GIT_TERMINAL_PROMPT=1"
set "GIT_PAGER=cat"
set "GH_PAGER=cat"
set "PAGER=cat"
set "GIT_EDITOR=true"
set "GH_EDITOR=true"
set "GIT_MERGE_AUTOEDIT=no"
set "GH_NO_UPDATE_NOTIFIER=1"
set "NO_COLOR=1"
set "CLICOLOR=0"
set "LANG=en_US.UTF-8"

rem Git for Windows defaults to schannel; the portable OpenSSL backend plus its
rem bundled CA store works in environments where schannel has no credentials.
set "GIT_SSL_CAINFO=%SKILL_ROOT%\tools\git\ucrt64\etc\ssl\certs\ca-bundle.crt"
if not exist "%GIT_SSL_CAINFO%" set "GIT_SSL_CAINFO=%SKILL_ROOT%\tools\git\mingw64\etc\ssl\certs\ca-bundle.crt"
if not exist "%GIT_SSL_CAINFO%" set "GIT_SSL_CAINFO=%SKILL_ROOT%\tools\git\usr\ssl\certs\ca-bundle.crt"

set "PATH=%SKILL_ROOT%\tools\gh\bin;%SKILL_ROOT%\tools\git\cmd;%SKILL_ROOT%\tools\git\ucrt64\bin;%SKILL_ROOT%\tools\git\mingw64\bin;%SKILL_ROOT%\tools\git\usr\bin;%PATH%"

if not exist "%SKILL_ROOT%\tools\git\cmd\git.exe" (
  echo [ERROR] Portable Git not found at "%SKILL_ROOT%\tools\git\cmd\git.exe".
  echo         Run the skill installer or re-extract tools\git.
  exit /b 1
)
if not exist "%SKILL_ROOT%\tools\gh\bin\gh.exe" (
  echo [ERROR] Portable GitHub CLI not found at "%SKILL_ROOT%\tools\gh\bin\gh.exe".
  echo         Run the skill installer or re-extract tools\gh.
  exit /b 1
)

if not exist "%GITSKILL_HOME%" mkdir "%GITSKILL_HOME%" >nul 2>nul
if not exist "%GH_CONFIG_DIR%" mkdir "%GH_CONFIG_DIR%" >nul 2>nul
if not exist "%GITSKILL_HOME%\.ssh" mkdir "%GITSKILL_HOME%\.ssh" >nul 2>nul
if not exist "%GIT_CONFIG_GLOBAL%" call :seed_gitconfig
if not exist "%GITSKILL_HOME%\.ssh\config" call :seed_sshconfig
if not exist "%GITSKILL_HOME%\.ssh\known_hosts" type nul > "%GITSKILL_HOME%\.ssh\known_hosts"

rem Keep the HTTPS backend on OpenSSL for older skill homes as well.
"%SKILL_ROOT%\tools\git\cmd\git.exe" config --global --get http.sslBackend >nul 2>nul
if errorlevel 1 "%SKILL_ROOT%\tools\git\cmd\git.exe" config --global http.sslBackend openssl >nul 2>nul

if "%~1"=="" goto :interactive
if /I "%~1"=="--env" goto :show_env
if /I "%~1"=="--check" goto :check
if /I "%~1"=="--bootstrap" goto :bootstrap

rem --- execute the requested command inside the isolated environment ------
%*
exit /b %ERRORLEVEL%

rem ==========================================================================
:seed_gitconfig
(
echo # Managed by the git-gh skill. Isolated from the user's global Git config.
echo # Add identity per repository instead of guessing it globally:
echo #   git config user.name  "Your Name"
echo #   git config user.email "you@example.com"
echo [init]
echo     defaultBranch = main
echo [core]
echo     autocrlf = false
echo     quotepath = false
echo [color]
echo     ui = false
echo [http]
echo     sslBackend = openssl
echo [credential]
echo     helper =
echo [help]
echo     autocorrect = 0
) > "%GIT_CONFIG_GLOBAL%"
exit /b 0

rem ==========================================================================
:seed_sshconfig
(
echo # Managed by the git-gh skill. Keys stay in this skill's home\.ssh.
echo Host *
echo     UserKnownHostsFile ~/.ssh/known_hosts
echo     StrictHostKeyChecking accept-new
echo     BatchMode yes
echo     ServerAliveInterval 30
) > "%GITSKILL_HOME%\.ssh\config"
exit /b 0

rem ==========================================================================
:show_env
echo GITSKILL_ROOT=%GITSKILL_ROOT%
echo HOME=%HOME%
echo GH_CONFIG_DIR=%GH_CONFIG_DIR%
echo GIT_CONFIG_GLOBAL=%GIT_CONFIG_GLOBAL%
echo GIT_CONFIG_NOSYSTEM=%GIT_CONFIG_NOSYSTEM%
echo GIT_TERMINAL_PROMPT=%GIT_TERMINAL_PROMPT%
echo SSH_CONFIG=%GITSKILL_HOME%\.ssh\config
where git
where gh
where ssh
exit /b 0

rem ==========================================================================
:check
echo === Portable Git/GH environment check ===
echo GITSKILL_ROOT=%GITSKILL_ROOT%
echo HOME=%HOME%
echo GH_CONFIG_DIR=%GH_CONFIG_DIR%
echo.
git --version
if errorlevel 1 echo [FAIL] git --version
gh --version
if errorlevel 1 echo [FAIL] gh --version
echo.
echo git resolved to:
where git
echo gh resolved to:
where gh
echo ssh resolved to:
where ssh
exit /b 0

rem ==========================================================================
:bootstrap
echo === git-gh first-run bootstrap ===
call :check
echo.
echo === Verifying isolated environment ===
powershell -NoProfile -ExecutionPolicy Bypass -File "%SKILL_ROOT%\scripts\check-env.ps1"
if errorlevel 1 (
  echo [ERROR] Environment check failed; bootstrap stopped.
  exit /b 1
)
echo.
echo === Ensuring an SSH key exists ===
powershell -NoProfile -ExecutionPolicy Bypass -File "%SKILL_ROOT%\scripts\setup-auth.ps1" -Mode Ensure
exit /b %ERRORLEVEL%

rem ==========================================================================
:interactive
echo ============================================================
echo  Portable Git / GitHub CLI environment
echo  HOME          = %HOME%
echo  GH_CONFIG_DIR = %GH_CONFIG_DIR%
echo  Type "exit" to leave this shell.
echo ============================================================
cmd /k
exit /b 0
