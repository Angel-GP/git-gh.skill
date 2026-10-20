#requires -Version 5.1
<#
.SYNOPSIS
  Verify that git/gh resolve to this skill's portable tools and that the
  isolated HOME / GH_CONFIG_DIR are active.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_common.ps1')

$root = Get-GitSkillRoot
$homeDir = Get-GitSkillHome
$failures = New-Object System.Collections.ArrayList

function Check([string]$Name, [bool]$Ok, [string]$Detail) {
    if ($Ok) {
        Write-Host "[PASS] $Name" -ForegroundColor Green
    }
    else {
        Write-Host "[FAIL] $Name - $Detail" -ForegroundColor Red
        [void]$failures.Add($Name)
    }
}

function Normalize([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    return $Path.TrimEnd('\')
}

Write-Host 'Portable Git/GH environment check' -ForegroundColor Cyan
Write-Host "Skill root: $root"
Write-Host ''

$homeValue = Normalize $env:HOME
$ghValue = Normalize $env:GH_CONFIG_DIR
$globalValue = Normalize $env:GIT_CONFIG_GLOBAL
$expectedHome = Normalize $homeDir
$expectedGh = Normalize (Join-Path $homeDir 'gh')
$expectedGlobal = Normalize (Join-Path $homeDir '.gitconfig')

Check 'HOME points inside the skill' ($homeValue -ne '' -and $homeValue -eq $expectedHome) "HOME=$homeValue expected=$expectedHome"
Check 'GH_CONFIG_DIR points inside the skill' ($ghValue -ne '' -and $ghValue -eq $expectedGh) "GH_CONFIG_DIR=$ghValue expected=$expectedGh"
Check 'GIT_CONFIG_GLOBAL points inside the skill' ($globalValue -ne '' -and $globalValue -eq $expectedGlobal) "GIT_CONFIG_GLOBAL=$globalValue expected=$expectedGlobal"

$gitCmd = Get-Command git -ErrorAction SilentlyContinue
$ghCmd = Get-Command gh -ErrorAction SilentlyContinue
$expectedGit = Normalize (Join-Path $root 'tools\git\cmd\git.exe')
$expectedGh = Normalize (Join-Path $root 'tools\gh\bin\gh.exe')
$gitSource = if ($gitCmd) { Normalize $gitCmd.Source } else { '' }
$ghSource = if ($ghCmd) { Normalize $ghCmd.Source } else { '' }

Check 'git resolves to the portable copy' ($gitSource -ne '' -and $gitSource -eq $expectedGit) "resolved=$gitSource expected=$expectedGit"
Check 'gh resolves to the portable copy' ($ghSource -ne '' -and $ghSource -eq $expectedGh) "resolved=$ghSource expected=$expectedGh"

if ($gitCmd) {
    $version = (& git --version 2>&1 | Select-Object -First 1)
    Write-Host "git: $version"
}
if ($ghCmd) {
    $version = (& gh --version 2>&1 | Select-Object -First 1)
    Write-Host "gh : $version"
}

Write-Host ''
if ($failures.Count -eq 0) {
    Write-Host 'Environment OK.' -ForegroundColor Green
    exit 0
}
Write-Host 'Environment is not isolated. Run commands through start.bat.' -ForegroundColor Red
exit 1
