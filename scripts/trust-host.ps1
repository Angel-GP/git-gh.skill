#requires -Version 5.1
<#
.SYNOPSIS
  Verify a host key out-of-band and add it to the skill's known_hosts.
.DESCRIPTION
  For github.com the keyscan result is compared with GitHub's published SSH
  fingerprints. For other hosts, pass -Fingerprint with a value obtained from
  a trusted channel. Only fingerprints are printed, never key material.
#>
[CmdletBinding()]
param(
    [string]$HostName = 'github.com',
    [int]$Port = 22,
    [string]$Fingerprint
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_common.ps1')

# https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints
$githubFingerprints = @(
    'SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU', # ED25519
    'SHA256:uNiVztksCsDhcc0u9e8BujQXVUpKZIDTMczCvj3tD2s', # RSA
    'SHA256:p2QAMXNIC1TJYWeIOttrVc98/R1BUFWu3/LiyKgUfQM'  # ECDSA
)

$knownHosts = Join-Path (Get-GitSkillHome) '.ssh\known_hosts'
$sshDir = Split-Path -Parent $knownHosts
if (-not (Test-Path -LiteralPath $sshDir)) { New-Item -ItemType Directory -Path $sshDir -Force | Out-Null }
if (-not (Test-Path -LiteralPath $knownHosts)) { New-Item -ItemType File -Path $knownHosts -Force | Out-Null }

Write-Host "Scanning $HostName port $Port ..." -ForegroundColor Cyan
$scanOutput = & ssh-keyscan -p $Port -T 10 $HostName 2>$null
if ($LASTEXITCODE -ne 0 -or -not $scanOutput) {
    Write-Host 'ssh-keyscan failed. Check DNS, network and port 22.' -ForegroundColor Red
    exit 1
}

$candidates = New-Object System.Collections.ArrayList
foreach ($line in @($scanOutput)) {
    $text = [string]$line
    if ($text.StartsWith('#') -or $text.Trim() -eq '') { continue }
    $tmp = [System.IO.Path]::GetTempFileName()
    try {
        [System.IO.File]::WriteAllText($tmp, $text + "`n", (New-Object System.Text.UTF8Encoding($false)))
        $fpOut = & ssh-keygen -lf $tmp 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $fpOut) { continue }
        $fpLine = [string]($fpOut | Select-Object -First 1)
        $fields = $fpLine -split '\s+'
        if ($fields.Count -lt 2) { continue }
        $keyType = 'unknown'
        $tm = [regex]::Match($fpLine, '\((?<t>[^)]+)\)\s*$')
        if ($tm.Success) { $keyType = $tm.Groups['t'].Value }
        [void]$candidates.Add([pscustomobject]@{
            Line        = $text
            Fingerprint = $fields[1]
            Type        = $keyType
        })
    }
    finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
}

if ($candidates.Count -eq 0) {
    Write-Host 'No host keys were returned.' -ForegroundColor Red
    exit 1
}

$allowed = @()
if ($HostName -ieq 'github.com') { $allowed = $githubFingerprints }
if ($Fingerprint) { $allowed += $Fingerprint }
if ($allowed.Count -eq 0) {
    Write-Host 'No trusted fingerprint supplied. Re-run with -Fingerprint <SHA256:...> after verifying it out-of-band.' -ForegroundColor Yellow
    foreach ($c in $candidates) { Write-Host ("  {0} {1}" -f $c.Fingerprint, $c.Type) }
    exit 2
}

$trusted = @($candidates | Where-Object { $allowed -contains $_.Fingerprint })
if ($trusted.Count -eq 0) {
    Write-Host 'Fingerprint mismatch. Nothing was written to known_hosts.' -ForegroundColor Red
    foreach ($c in $candidates) { Write-Host ("  {0} {1}" -f $c.Fingerprint, $c.Type) }
    Write-Host 'Verify the fingerprint through a trusted channel before retrying.' -ForegroundColor Yellow
    exit 2
}

$existing = New-Object 'System.Collections.Generic.HashSet[string]'
if (Test-Path -LiteralPath $knownHosts) {
    foreach ($line in ([System.IO.File]::ReadAllLines($knownHosts))) {
        if ($line) { [void]$existing.Add($line.TrimEnd()) }
    }
}

$added = 0
foreach ($c in $trusted) {
    if ($existing.Add($c.Line.TrimEnd())) {
        Add-Content -LiteralPath $knownHosts -Value $c.Line.TrimEnd() -Encoding Ascii
        $added++
    }
    Write-Host ("Trusted {0}:{1} {2} ({3})" -f $HostName, $Port, $c.Fingerprint, $c.Type) -ForegroundColor Green
}
Write-Host "known_hosts: $knownHosts (+$added line(s))" -ForegroundColor DarkGray
exit 0
