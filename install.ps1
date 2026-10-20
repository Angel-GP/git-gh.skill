#requires -Version 5.1
<#
.SYNOPSIS
  Install or update this skill in the DSH user skill directory.
.DESCRIPTION
  Copies the skill bundle to <DSH_HOME>\skills\git-gh. The skill's home\
  directory (credentials, SSH keys, gh auth) is intentionally NOT copied.
  Existing target files are overwritten only with -Force.
#>
[CmdletBinding()]
param(
    [string]$Target,
    [switch]$Force
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$source = $PSScriptRoot.TrimEnd('\')
if (-not $Target) {
    $dshHome = if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $env:USERPROFILE '.dsh' }
    $Target = Join-Path $dshHome 'skills\git-gh'
}
$Target = [System.IO.Path]::GetFullPath($Target).TrimEnd('\')

if ($source -ieq $Target) {
    Write-Host "Source and target are the same: $Target" -ForegroundColor Yellow
    exit 0
}

if (Test-Path -LiteralPath $Target) {
    if (-not $Force) {
        Write-Host "Target already exists: $Target" -ForegroundColor Yellow
        Write-Host 'Re-run with -Force to overwrite skill files. The target home\ directory is never touched.' -ForegroundColor Yellow
        exit 1
    }
}

Write-Host "Installing git-gh" -ForegroundColor Cyan
Write-Host "  from: $source"
Write-Host "  to  : $Target"

New-Item -ItemType Directory -Path $Target -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $Target 'home\gh') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $Target 'home\.ssh') -Force | Out-Null

# /E copies without deleting anything in the target; home\ is excluded so
# credentials and SSH keys are never overwritten or removed.
$robocopyArgs = @(
    $source, $Target,
    '/E', '/COPY:DAT', '/R:2', '/W:1',
    '/XD', (Join-Path $source 'home'), (Join-Path $source '.git'), (Join-Path $source '_build'),
    '/XF', '*.log',
    '/NFL', '/NDL', '/NJH', '/NJS', '/NP'
)
& robocopy.exe @robocopyArgs | Out-Null
$code = $LASTEXITCODE
if ($code -ge 8) {
    Write-Host "robocopy failed with exit code $code." -ForegroundColor Red
    exit 1
}

Write-Host ''
Write-Host 'Installed. Next steps:' -ForegroundColor Green
Write-Host "  1. Run: & `"$Target\start.bat`" --check"
Write-Host "  2. In DSH, invoke /git-gh or ask the agent to use the git-gh skill."
Write-Host "  3. Authenticate if needed: & `"$Target\start.bat`" gh auth login"
Write-Host ''
Write-Host 'Credentials stay in the target home\ directory and are not copied from the source.' -ForegroundColor DarkGray
exit 0
