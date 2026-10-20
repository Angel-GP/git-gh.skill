#requires -Version 5.1
<#
.SYNOPSIS
  Validate a Conventional Commits message.
.DESCRIPTION
  Checks the header format, allowed type, length, breaking-change marker and
  BREAKING CHANGE footer. Read-only. Exit 0 = valid, 2 = invalid.
#>
[CmdletBinding(DefaultParameterSetName = 'Message')]
param(
    [Parameter(ParameterSetName = 'Message', Mandatory = $true)][string]$Message,
    [Parameter(ParameterSetName = 'MessageFile', Mandatory = $true)][string]$MessageFile
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$allowedTypes = @('feat', 'fix', 'docs', 'style', 'refactor', 'perf', 'test', 'build', 'ci', 'chore', 'revert')
$errors = New-Object System.Collections.ArrayList
$warnings = New-Object System.Collections.ArrayList

if ($PSCmdlet.ParameterSetName -eq 'MessageFile') {
    if (-not (Test-Path -LiteralPath $MessageFile -PathType Leaf)) {
        Write-Host "ERROR: message file not found: $MessageFile" -ForegroundColor Red
        exit 2
    }
    $text = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $MessageFile).Path, [System.Text.Encoding]::UTF8)
}
else {
    $text = $Message
}

$lines = [regex]::Split($text.TrimEnd(), '\r?\n')
if ($lines.Count -eq 0 -or [string]::IsNullOrWhiteSpace($lines[0])) {
    Write-Host 'INVALID: commit message is empty.' -ForegroundColor Red
    exit 2
}

$header = $lines[0].TrimEnd()
$m = [regex]::Match($header, '^(?<type>[a-z]+)(?:\((?<scope>[A-Za-z0-9][A-Za-z0-9._/-]*)\))?(?<bang>!)?: (?<desc>.+)$')
if (-not $m.Success) {
    [void]$errors.Add('Header must match <type>(<scope>): <description> (scope optional, one space after colon).')
}
else {
    $type = $m.Groups['type'].Value
    if ($allowedTypes -notcontains $type) {
        [void]$errors.Add("Type '$type' is not allowed. Use one of: $($allowedTypes -join ', ').")
    }
    if ($m.Groups['desc'].Value.Trim().Length -eq 0) {
        [void]$errors.Add('Description is empty.')
    }
    if ($m.Groups['desc'].Value.EndsWith('.')) {
        [void]$errors.Add('Description must not end with a period.')
    }
}

if ($header.Length -gt 72) {
    [void]$errors.Add("Header is $($header.Length) characters; keep it at or below 72.")
}

if ($lines.Count -gt 1) {
    if ($lines[1].Trim() -ne '') {
        [void]$errors.Add('Leave a blank line between the header and the body.')
    }
}

$body = if ($lines.Count -gt 2) { ($lines[2..($lines.Count - 1)] -join "`n") } else { '' }
$hasBreakingFooter = [regex]::IsMatch($body, '(?im)^BREAKING[ -]CHANGE:\s*\S+')
$hasBang = $m.Success -and $m.Groups['bang'].Value -eq '!'
if ($hasBang -and -not $hasBreakingFooter) {
    [void]$warnings.Add('A ! header should be accompanied by a BREAKING CHANGE: footer describing the migration.')
}

if ($errors.Count -gt 0) {
    Write-Host 'INVALID commit message:' -ForegroundColor Red
    foreach ($e in $errors) { Write-Host "  - $e" -ForegroundColor Yellow }
    exit 2
}

Write-Host 'VALID Conventional Commit.' -ForegroundColor Green
foreach ($w in $warnings) { Write-Host "  warning: $w" -ForegroundColor Yellow }
Write-Host "  type : $($m.Groups['type'].Value)"
if ($m.Groups['scope'].Value) { Write-Host "  scope: $($m.Groups['scope'].Value)" }
Write-Host "  desc : $($m.Groups['desc'].Value)"
exit 0
