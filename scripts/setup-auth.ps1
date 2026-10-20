#requires -Version 5.1
<#
.SYNOPSIS
  First-run authentication helper for a shared git-gh skill.
.DESCRIPTION
  Generates a dedicated SSH key inside the skill's isolated home, prints only
  the PUBLIC key (safe to add to GitHub), or checks the current setup. It never
  reads or prints a private key. Run it through start.bat / setup-auth.bat.
  Ensure is the non-interactive first-run mode: if no key exists, it generates
  one without a passphrase and prints the public key.
.PARAMETER Mode
  Ensure (non-interactive first run), Generate, Check, or Login.
.PARAMETER Comment
  Comment stored in the public key, usually an email.
.PARAMETER Force
  Back up an existing key and generate a new one.
.PARAMETER NoPassphrase
  Generate without a passphrase (less secure; convenient for automation).
#>
[CmdletBinding()]
param(
    [ValidateSet('Ensure', 'Generate', 'Check', 'Login')][string]$Mode = 'Generate',
    [string]$Comment = "$env:USERNAME@$env:COMPUTERNAME",
    [switch]$Force,
    [switch]$NoPassphrase
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_common.ps1')

$root = Get-GitSkillRoot
$homeDir = Get-GitSkillHome
$sshDir = Join-Path $homeDir '.ssh'
if (-not (Test-Path -LiteralPath $sshDir)) {
    New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
}

function Get-KeygenPath {
    # Prefer Windows OpenSSH's keygen when present: the portable MSYS build can
    # fail in restricted sandboxes with "couldn't create signal pipe".
    $sys = Join-Path $env:SystemRoot 'System32\OpenSSH\ssh-keygen.exe'
    if (Test-Path -LiteralPath $sys) { return $sys }
    $cmd = Get-Command ssh-keygen -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    throw 'ssh-keygen not found. Install the Windows OpenSSH client or repair the portable Git installation.'
}

function Restrict-KeyAcl([string]$Path) {
    $icacls = Get-Command icacls.exe -ErrorAction SilentlyContinue
    if (-not $icacls) { return }
    $principal = if ($env:USERDOMAIN) { "$env:USERDOMAIN\$env:USERNAME" } else { $env:USERNAME }
    $oldEap = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & icacls.exe $Path /inheritance:r /grant:r "${principal}:(R,W)" 2>&1 | Out-Null
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $oldEap
    }
    if ($code -ne 0) {
        Write-Host 'Warning: could not tighten the key file ACL; check permissions manually.' -ForegroundColor Yellow
    }
}

function Show-PublicKey([string]$KeyPath) {
    $pub = "$KeyPath.pub"
    if (-not (Test-Path -LiteralPath $pub)) {
        Write-Host "Public key not found: $pub" -ForegroundColor Yellow
        Write-Host 'If you imported a key, provide its .pub file or derive it with: ssh-keygen -y -f <key>'
        return
    }
    $text = [System.IO.File]::ReadAllText($pub, [System.Text.Encoding]::UTF8).Trim()
    $keygen = Get-KeygenPath
    $oldEap = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $fingerprint = & $keygen -lf $pub 2>$null
    }
    finally {
        $ErrorActionPreference = $oldEap
    }
    Write-Host ''
    Write-Host 'Public key (safe to share; add it to GitHub):' -ForegroundColor Cyan
    Write-Host $text
    if ($fingerprint) { Write-Host "Fingerprint: $fingerprint" -ForegroundColor DarkGray }
    Write-Host ''
    Write-Host 'Add it at: https://github.com/settings/ssh/new' -ForegroundColor Green
    Write-Host 'Then test with: setup-auth.bat -Mode Check' -ForegroundColor Green
}

function Invoke-Generate {
    param([switch]$NonInteractive)
    $key = Join-Path $sshDir 'id_ed25519'
    $noPass = $NoPassphrase -or $NonInteractive
    if (Test-Path -LiteralPath $key) {
        if (-not $Force) {
            Write-Host "SSH key already exists: $key" -ForegroundColor Yellow
            Show-PublicKey $key
            Write-Host 'Use -Force to back it up and generate a new key.' -ForegroundColor Yellow
            return
        }
        $stamp = Get-Date -Format 'yyyyMMddHHmmss'
        Move-Item -LiteralPath $key -Destination "$key.bak-$stamp"
        if (Test-Path -LiteralPath "$key.pub") { Move-Item -LiteralPath "$key.pub" -Destination "$key.pub.bak-$stamp" }
        Write-Host "Existing key backed up with suffix .bak-$stamp" -ForegroundColor DarkGray
    }

    $keygen = Get-KeygenPath
    $keygenArgs = @('-t', 'ed25519', '-f', $key, '-C', $Comment)
    if ($noPass) { $keygenArgs += @('-N', '""', '-q') }

    # Some restricted Windows sandboxes fail when ssh-keygen creates the .pub
    # file itself. Pre-creating it makes ssh-keygen write through the existing
    # handle instead.
    $pub = "$key.pub"
    if (-not (Test-Path -LiteralPath $pub)) {
        New-Item -ItemType File -Path $pub -Force | Out-Null
    }

    Write-Host "Generating an ed25519 key in the isolated skill home..." -ForegroundColor Cyan
    if (-not $noPass) {
        Write-Host 'You will be asked for a passphrase. Press Enter twice for no passphrase.' -ForegroundColor DarkGray
        Write-Host 'Note: git runs with BatchMode=yes here. A passphrase-protected key must be loaded into ssh-agent before git can use it; otherwise use -NoPassphrase.' -ForegroundColor Yellow
    }
    & $keygen @keygenArgs
    if ($LASTEXITCODE -ne 0) {
        if ((Test-Path -LiteralPath $key) -and (Get-Item -LiteralPath $key).Length -gt 0 -and
            (Test-Path -LiteralPath $pub) -and (Get-Item -LiteralPath $pub).Length -eq 0) {
            Remove-Item -LiteralPath $key -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $pub -Force -ErrorAction SilentlyContinue
        }
        Write-Host 'ssh-keygen failed. If this is a restricted sandbox, run setup-auth.bat in a normal terminal.' -ForegroundColor Red
        exit 1
    }

    if (-not (Test-Path -LiteralPath $pub) -or (Get-Item -LiteralPath $pub).Length -eq 0) {
        & $keygen -y -f $key > $pub
        if ($LASTEXITCODE -ne 0) {
            Write-Host 'Key generated, but the public key could not be derived.' -ForegroundColor Red
            exit 1
        }
    }

    Restrict-KeyAcl $key
    Show-PublicKey $key
}

function Invoke-Ensure {
    $candidates = @(@('id_ed25519', 'id_rsa', 'id_ecdsa') | ForEach-Object { Join-Path $sshDir $_ } | Where-Object { Test-Path -LiteralPath $_ })
    if ($candidates.Count -gt 0) {
        Write-Host "SSH key found: $($candidates[0])" -ForegroundColor Green
        Show-PublicKey $candidates[0]
        return
    }
    Write-Host 'No SSH key found; generating a dedicated ed25519 key without a passphrase...' -ForegroundColor Cyan
    Invoke-Generate -NonInteractive
}

function Invoke-Check {
    Write-Host 'Internal SSH material (names only):' -ForegroundColor Cyan
    $files = @(Get-ChildItem -LiteralPath $sshDir -File -ErrorAction SilentlyContinue)
    if ($files.Count -eq 0) {
        Write-Host '  (empty)' -ForegroundColor Yellow
    }
    else {
        foreach ($f in $files) { Write-Host ("  {0,-28} {1,8} bytes" -f $f.Name, $f.Length) }
    }

    $keygen = Get-KeygenPath
    $privateKeys = @($files | Where-Object { $_.Name -match '^id_' -and $_.Extension -ne '.pub' })
    foreach ($k in $privateKeys) {
        $oldEap = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $fp = & $keygen -lf $k.FullName 2>$null
        }
        finally {
            $ErrorActionPreference = $oldEap
        }
        if ($fp) { Write-Host "  fingerprint: $fp" -ForegroundColor DarkGray }
        if (Test-Path -LiteralPath "$($k.FullName).pub") { Show-PublicKey $k.FullName }
    }

    Write-Host ''
    Write-Host 'Testing GitHub SSH authentication...' -ForegroundColor Cyan
    $oldEap = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = & ssh -o ConnectTimeout=8 -T git@github.com 2>&1
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $oldEap
    }
    $text = ($output | ForEach-Object { [string]$_ }) -join "`n"
    if ($text -match '(?i)successfully authenticated') {
        Write-Host 'SSH authentication succeeded.' -ForegroundColor Green
    }
    elseif ($text -match '(?i)signal pipe') {
        Write-Host 'ssh could not start in this restricted environment (named pipe blocked).' -ForegroundColor Yellow
        Write-Host 'Use HTTPS in this sandbox, or run setup-auth.bat in a normal terminal.' -ForegroundColor Yellow
    }
    else {
        Write-Host (Redact-Text $text) -ForegroundColor Yellow
        Write-Host "ssh exit=$code" -ForegroundColor DarkGray
        Write-Host 'If the key is new, add the public key to GitHub first.' -ForegroundColor Yellow
    }
}

function Invoke-Login {
    Write-Host 'HTTPS / GitHub CLI login is interactive. Run this yourself in a terminal:' -ForegroundColor Cyan
    Write-Host "  & `"$root\start.bat`" gh auth login" -ForegroundColor Green
    Write-Host ''
    Write-Host 'After login, verify with:' -ForegroundColor Cyan
    Write-Host "  & `"$root\start.bat`" gh auth status" -ForegroundColor Green
    Write-Host ''
    Write-Host 'Credentials are stored only in the skill home\gh directory.' -ForegroundColor DarkGray
}

switch ($Mode) {
    'Ensure'   { Invoke-Ensure }
    'Generate' { Invoke-Generate }
    'Check'    { Invoke-Check }
    'Login'    { Invoke-Login }
}
exit 0
