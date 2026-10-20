#requires -Version 5.1
<#
.SYNOPSIS
  Install or update this skill in the DSH user skill directory.
.DESCRIPTION
  Copies the skill bundle to the fixed global skill directory
  <DSH_HOME>\skills\git-gh. Project-level installation is intentionally not
  supported. The skill's home\ directory (credentials, SSH keys, gh auth) is
  never copied. Existing target files are overwritten only with -Force.
#>
[CmdletBinding()]
param(
    [switch]$Force
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$source = $PSScriptRoot.TrimEnd('\')
$dshHome = if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $env:USERPROFILE '.dsh' }
$Target = [System.IO.Path]::GetFullPath((Join-Path $dshHome 'skills\git-gh')).TrimEnd('\')

if ($source -ieq $Target) {
    Write-Host "Source and target are the same global skill: $Target" -ForegroundColor Yellow
    exit 0
}

if (Test-Path -LiteralPath $Target) {
    if (-not $Force) {
        Write-Host "Global skill already exists: $Target" -ForegroundColor Yellow
        Write-Host 'Re-run with -Force to overwrite skill files. The target home\ directory is never touched.' -ForegroundColor Yellow
        exit 1
    }
}

Write-Host "Installing git-gh globally" -ForegroundColor Cyan
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
Write-Host 'Installed as a global DSH skill.' -ForegroundColor Green
Write-Host 'DSH will discover it at the target path.'
Write-Host 'On first load, the skill automatically runs start.bat --bootstrap to create home\ and prepare the SSH key.'
Write-Host ''
Write-Host 'Credentials stay in the target home\ directory and are not copied from the source.' -ForegroundColor DarkGray
exit 0
