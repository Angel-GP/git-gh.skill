#requires -Version 5.1
<#
.SYNOPSIS
  Read-only diagnostics for the portable Git/GH environment.
.DESCRIPTION
  Prints versions, environment variables, resolved tool paths, Git config
  origins, remotes (credentials redacted), gh auth status (redacted), and SSH
  key file names. It never reads private key contents.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_common.ps1')

function Show-Command {
    param([string]$Label, [string]$Command, [string[]]$Arguments)
    Write-Host "`n$ $Command $($Arguments -join ' ')" -ForegroundColor DarkGray
    $oldEap = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = & $Command @Arguments 2>&1
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $oldEap
    }
    foreach ($line in @($output)) {
        Write-Host (Redact-Text ([string]$line))
    }
    Write-Host "exit=$code" -ForegroundColor DarkGray
}

Write-Host '=== git-gh diagnostics (read-only) ===' -ForegroundColor Cyan
Write-Host "Skill root : $(Get-GitSkillRoot)"
Write-Host "HOME       : $env:HOME"
Write-Host "GH_CONFIG_DIR: $env:GH_CONFIG_DIR"
Write-Host "GIT_CONFIG_GLOBAL: $env:GIT_CONFIG_GLOBAL"
Write-Host "GIT_CONFIG_NOSYSTEM: $env:GIT_CONFIG_NOSYSTEM"
Write-Host "GIT_TERMINAL_PROMPT: $env:GIT_TERMINAL_PROMPT"

Write-Section 'Tool versions'
Show-Command 'git' 'git' @('--version')
Show-Command 'git exec-path' 'git' @('--exec-path')
Show-Command 'gh' 'gh' @('--version')

Write-Section 'Resolved paths'
foreach ($name in @('git', 'gh', 'ssh', 'ssh-keygen', 'ssh-keyscan')) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd) { Write-Host ("{0,-12} {1}" -f $name, $cmd.Source) }
    else { Write-Host ("{0,-12} <not found>" -f $name) -ForegroundColor Yellow }
}

Write-Section 'Git configuration (with origins)'
Show-Command 'git config' 'git' @('config', '--list', '--show-origin')

$repoRoot = Get-RepoRoot
if ($repoRoot) {
    Write-Section 'Repository'
    Write-Host "Root   : $repoRoot"
    Show-Command 'branch' 'git' @('rev-parse', '--abbrev-ref', 'HEAD')
    Show-Command 'remotes' 'git' @('remote', '-v')
    Show-Command 'status' 'git' @('status', '--short', '--branch')
}
else {
    Write-Host "`nNot inside a Git repository." -ForegroundColor Yellow
}

Write-Section 'GitHub CLI auth status'
Show-Command 'gh auth' 'gh' @('auth', 'status')

Write-Section 'SSH material (names only, contents are never read)'
$sshDir = Join-Path (Get-GitSkillHome) '.ssh'
if (Test-Path -LiteralPath $sshDir) {
    Get-ChildItem -LiteralPath $sshDir -File | ForEach-Object {
        Write-Host ("{0,-24} {1,8} bytes" -f $_.Name, $_.Length)
    }
    if (Test-Path -LiteralPath (Join-Path $sshDir 'config')) {
        Write-Host "`nssh config:" -ForegroundColor DarkGray
        [System.IO.File]::ReadAllLines((Join-Path $sshDir 'config')) | ForEach-Object { Write-Host (Redact-Text $_) }
    }
}
else {
    Write-Host 'No .ssh directory.' -ForegroundColor Yellow
}
Show-Command 'ssh-add -l' 'ssh-add' @('-l')
Write-Host 'Note: a restricted sandbox may block ssh-add/ssh with "couldn''t create signal pipe"; use HTTPS there.' -ForegroundColor DarkGray

Write-Section 'Next steps'
Write-Host 'If git/gh paths are outside the skill, run commands through start.bat.'
Write-Host 'If gh is not authenticated, run: start.bat gh auth login'
Write-Host 'If SSH fails, run: start.bat ssh -T git@github.com'
exit 0
