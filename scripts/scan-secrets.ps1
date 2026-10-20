#requires -Version 5.1
<#
.SYNOPSIS
  Scan code, staged content, commit messages and branch names for secrets.
.DESCRIPTION
  Reports only rule, file and line. It never prints the matched secret.
  Exit codes: 0 = clean, 2 = HIGH finding (block), 3 = MEDIUM finding
  (review required), 1 = scanner error.
.PARAMETER Worktree
  Scan modified and untracked files in the working tree (default).
.PARAMETER Staged
  Scan the content that is currently staged (git index).
.PARAMETER Tracked
  Scan all tracked files from the working tree (useful in CI).
.PARAMETER Paths
  Scan specific files or directories.
.PARAMETER Message
  Scan a commit message string.
.PARAMETER MessageFile
  Scan a commit message file.
.PARAMETER Branch
  Scan a branch name (defaults to the current branch when -Branch is used
  without a value is not supported; pass the name explicitly).
.PARAMETER Json
  Emit machine-readable JSON only.
#>
[CmdletBinding(DefaultParameterSetName = 'Worktree')]
param(
    [Parameter(ParameterSetName = 'Worktree')][switch]$Worktree,
    [Parameter(ParameterSetName = 'Staged')][switch]$Staged,
    [Parameter(ParameterSetName = 'Tracked')][switch]$Tracked,
    [Parameter(ParameterSetName = 'Paths')][string[]]$Paths,
    [Parameter(ParameterSetName = 'Message')][string]$Message,
    [Parameter(ParameterSetName = 'MessageFile')][string]$MessageFile,
    [Parameter(ParameterSetName = 'Branch')][string]$Branch,
    [string]$RepoPath = (Get-Location).Path,
    [switch]$Json
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_common.ps1')

$maxFileBytes = 5MB
$binaryExtensions = @(
    '.png', '.jpg', '.jpeg', '.gif', '.webp', '.ico', '.bmp', '.tif', '.tiff',
    '.pdf', '.zip', '.gz', '.tgz', '.bz2', '.xz', '.7z', '.rar', '.jar', '.war',
    '.exe', '.dll', '.so', '.dylib', '.bin', '.dat', '.class', '.pyc', '.pyo',
    '.woff', '.woff2', '.ttf', '.otf', '.eot', '.mp3', '.mp4', '.mov', '.avi',
    '.mkv', '.wav', '.flac', '.sqlite', '.db', '.kdbx', '.jks', '.keystore',
    '.pfx', '.p12'
)

# High-confidence patterns: a match blocks the commit.
$highRules = @(
    [pscustomobject]@{ Id = 'PRIVATE_KEY'; Pattern = '-----BEGIN (?:RSA |EC |DSA |OPENSSH |PGP )?PRIVATE KEY-----'; Advice = 'Remove the private key and load it from a secret manager or environment variable.' },
    [pscustomobject]@{ Id = 'GITHUB_TOKEN'; Pattern = '\bgh[pousr]_[A-Za-z0-9]{20,}\b'; Advice = 'Revoke the token, then use gh auth login or an environment variable.' },
    [pscustomobject]@{ Id = 'GITHUB_PAT'; Pattern = '\bgithub_pat_[A-Za-z0-9_]{20,}\b'; Advice = 'Revoke the fine-grained PAT and store it outside the repository.' },
    [pscustomobject]@{ Id = 'GITLAB_TOKEN'; Pattern = '\bglpat-[A-Za-z0-9_-]{20,}\b'; Advice = 'Revoke the GitLab token and store it outside the repository.' },
    [pscustomobject]@{ Id = 'AWS_ACCESS_KEY'; Pattern = '\b(?:AKIA|ASIA)[0-9A-Z]{16}\b'; Advice = 'Revoke the AWS key and use an IAM role or secret manager.' },
    [pscustomobject]@{ Id = 'OPENAI_KEY'; Pattern = '\bsk-[A-Za-z0-9_-]{20,}\b'; Advice = 'Revoke the API key and load it from the environment.' },
    [pscustomobject]@{ Id = 'ANTHROPIC_KEY'; Pattern = '\bsk-ant-[A-Za-z0-9_-]{20,}\b'; Advice = 'Revoke the API key and load it from the environment.' },
    [pscustomobject]@{ Id = 'SLACK_TOKEN'; Pattern = '\bxox[baprs]-[A-Za-z0-9-]{10,}\b'; Advice = 'Revoke the Slack token and rotate it.' },
    [pscustomobject]@{ Id = 'GOOGLE_API_KEY'; Pattern = '\bAIza[0-9A-Za-z_-]{35}\b'; Advice = 'Revoke the Google API key and restrict it.' },
    [pscustomobject]@{ Id = 'NPM_TOKEN'; Pattern = '\bnpm_[A-Za-z0-9]{36}\b'; Advice = 'Revoke the npm token and use .npmrc outside the repository.' },
    [pscustomobject]@{ Id = 'SENDGRID_KEY'; Pattern = '\bSG\.[A-Za-z0-9_-]{22}\.[A-Za-z0-9_-]{43}\b'; Advice = 'Revoke the SendGrid key.' },
    [pscustomobject]@{ Id = 'JWT'; Pattern = '\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b'; Advice = 'Do not commit JWTs; issue short-lived tokens at runtime.' },
    [pscustomobject]@{ Id = 'URL_CREDENTIALS'; Pattern = 'https?://[^/\s:@]+:[^/\s@]+@'; Advice = 'Remove credentials from the URL and use a credential helper.' },
    [pscustomobject]@{ Id = 'BEARER_TOKEN'; Pattern = '(?i)\bBearer\s+[A-Za-z0-9._~+/-]{20,}'; Advice = 'Load bearer tokens from the environment at runtime.' }
)

# Medium-confidence patterns: review is required before committing.
$mediumRules = @(
    [pscustomobject]@{ Id = 'PASSWORD_ASSIGNMENT'; Pattern = '(?i)\b(?:password|passwd|pwd)\s*[:=]\s*[''"]([^''"]{8,})[''"]'; Advice = 'Move the password to a secret store or environment variable.' },
    [pscustomobject]@{ Id = 'SECRET_ASSIGNMENT'; Pattern = '(?i)\b(?:api[_-]?key|apikey|secret|token|access[_-]?key|client[_-]?secret)\s*[:=]\s*[''"]([A-Za-z0-9_\-\.]{16,})[''"]'; Advice = 'Load the value from the environment instead of hard-coding it.' }
)

$script:findings = New-Object System.Collections.ArrayList
$script:seen = New-Object 'System.Collections.Generic.HashSet[string]'
$script:scannedFiles = 0
$script:skippedFiles = New-Object System.Collections.ArrayList

function Add-Finding {
    param(
        [string]$Severity,
        [string]$Rule,
        [string]$Path,
        [int]$Line,
        [string]$Advice
    )
    $key = "$Rule|$Path|$Line"
    if (-not $script:seen.Add($key)) { return }
    [void]$script:findings.Add([pscustomobject]@{
        Severity = $Severity
        Rule     = $Rule
        Path     = Redact-Text $Path
        Line     = $Line
        Advice   = $Advice
    })
}

function Test-Placeholder {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $true }
    return ($Value -match '^(?i)(?:\*+|x{4,}|<.*>|\$\{.*\}|%.*%|\{\{.*\}\}|your[_-]?.*|example.*|sample.*|changeme|placeholder|dummy|test.*|none|null|todo|redacted)$')
}

function Scan-Line {
    param([string]$LineText, [string]$DisplayPath, [int]$LineNumber)
    foreach ($rule in $highRules) {
        if ([regex]::IsMatch($LineText, $rule.Pattern)) {
            Add-Finding -Severity 'HIGH' -Rule $rule.Id -Path $DisplayPath -Line $LineNumber -Advice $rule.Advice
        }
    }
    foreach ($rule in $mediumRules) {
        $m = [regex]::Match($LineText, $rule.Pattern)
        if ($m.Success) {
            $value = if ($m.Groups.Count -gt 1) { $m.Groups[1].Value } else { '' }
            if (-not (Test-Placeholder $value)) {
                Add-Finding -Severity 'MEDIUM' -Rule $rule.Id -Path $DisplayPath -Line $LineNumber -Advice $rule.Advice
            }
        }
    }
}

function Scan-Text {
    param([string]$Text, [string]$DisplayPath)
    if ($null -eq $Text) { return }
    $lines = [regex]::Split($Text, '\r?\n')
    for ($i = 0; $i -lt $lines.Count; $i++) {
        Scan-Line -LineText $lines[$i] -DisplayPath $DisplayPath -LineNumber ($i + 1)
    }
}

function Test-SensitiveFileName {
    param([string]$Path)
    $name = Split-Path -Leaf $Path
    if ($name -match '^(?i)\.env(\..+)?$') {
        if ($name -notmatch '(?i)\.(example|sample|template)$') {
            Add-Finding -Severity 'HIGH' -Rule 'ENV_FILE' -Path $Path -Line 0 -Advice 'Do not commit .env files; add them to .gitignore.'
        }
        return
    }
    if ($name -match '^(?i)(id_rsa|id_dsa|id_ecdsa|id_ed25519|identity)$' -or
        $name -match '(?i)\.(pem|pfx|p12|key|kdbx|jks|keystore)$' -or
        $name -match '^(?i)(credentials\.json|hosts\.yml|\.npmrc|\.pypirc|\.netrc|_netrc)$') {
        Add-Finding -Severity 'HIGH' -Rule 'SENSITIVE_FILE' -Path $Path -Line 0 -Advice 'Remove the file from the commit and keep it outside the repository.'
    }
}

function Unquote-GitPath {
    param([string]$Path)
    $p = $Path.Trim()
    if ($p.Length -ge 2 -and $p.StartsWith('"') -and $p.EndsWith('"')) {
        $p = $p.Substring(1, $p.Length - 2)
        $p = $p.Replace('\"', '"').Replace('\\', '\').Replace('\t', "`t").Replace('\n', "`n")
    }
    return $p
}

function Get-SkillPrefixInRepo {
    param([string]$RepoRoot)
    $repo = $RepoRoot.Replace('\', '/').TrimEnd('/')
    $skill = (Get-GitSkillRoot).Replace('\', '/').TrimEnd('/')
    if ($skill -ieq $repo) { return '' }
    $prefix = $repo + '/'
    if ($skill.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $skill.Substring($prefix.Length).Trim('/')
    }
    return $null
}

function Test-ExcludedPath {
    param([string]$RelativePath, [string]$RepoRoot)
    $normalized = $RelativePath.Replace('\', '/')
    while ($normalized.StartsWith('./')) { $normalized = $normalized.Substring(2) }

    if ([System.IO.Path]::IsPathRooted($RelativePath)) {
        $repo = $RepoRoot.Replace('\', '/').TrimEnd('/')
        $full = [System.IO.Path]::GetFullPath($RelativePath).Replace('\', '/')
        if (-not $full.StartsWith($repo + '/', [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
        $normalized = $full.Substring($repo.Length + 1)
    }

    if ($normalized -eq '..' -or $normalized.StartsWith('../') -or $normalized.Contains('/../')) { return $true }
    if ($normalized -match '(^|/)\.git/' -or $normalized -match '(^|/)node_modules/') { return $true }

    $prefix = Get-SkillPrefixInRepo -RepoRoot $RepoRoot
    if ($null -ne $prefix) {
        $p = if ($prefix) { $prefix + '/' } else { '' }
        if ($normalized.StartsWith($p + 'tools/git/', [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
        if ($normalized.StartsWith($p + 'tools/gh/', [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
        if ($normalized.StartsWith($p + 'home/', [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Test-TextBytes {
    param([byte[]]$Bytes)
    if ($null -eq $Bytes -or $Bytes.Length -eq 0) { return $true }
    $limit = [Math]::Min($Bytes.Length, 8000)
    for ($i = 0; $i -lt $limit; $i++) {
        if ($Bytes[$i] -eq 0) { return $false }
    }
    return $true
}

function Read-TextFile {
    param([string]$FullPath)
    $bytes = [System.IO.File]::ReadAllBytes($FullPath)
    if (-not (Test-TextBytes $bytes)) { return $null }
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
    }
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        return [System.Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2)
    }
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
        return [System.Text.Encoding]::BigEndianUnicode.GetString($bytes, 2, $bytes.Length - 2)
    }
    return [System.Text.Encoding]::UTF8.GetString($bytes)
}

function Scan-WorktreeFile {
    param([string]$RelativePath, [string]$RepoRoot)
    $ext = [System.IO.Path]::GetExtension($RelativePath).ToLowerInvariant()
    if ($binaryExtensions -contains $ext) { [void]$script:skippedFiles.Add($RelativePath); return }
    $full = Join-Path $RepoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { return }
    $size = (Get-Item -LiteralPath $full).Length
    if ($size -gt $maxFileBytes) { [void]$script:skippedFiles.Add("$RelativePath (too large)"); return }
    $text = Read-TextFile -FullPath $full
    if ($null -eq $text) { [void]$script:skippedFiles.Add("$RelativePath (binary)"); return }
    $script:scannedFiles++
    Scan-Text -Text $text -DisplayPath $RelativePath
}

function Scan-StagedFile {
    param([string]$RelativePath, [string]$RepoRoot)
    $ext = [System.IO.Path]::GetExtension($RelativePath).ToLowerInvariant()
    if ($binaryExtensions -contains $ext) { [void]$script:skippedFiles.Add($RelativePath); return }
    $sizeResult = Invoke-GitCapture -Arguments @('cat-file', '-s', ":$RelativePath") -WorkingDirectory $RepoRoot
    if ($sizeResult.ExitCode -ne 0) { return }
    $size = 0L
    [void][long]::TryParse(($sizeResult.Output | Select-Object -First 1), [ref]$size)
    if ($size -gt $maxFileBytes) { [void]$script:skippedFiles.Add("$RelativePath (too large)"); return }
    $show = Invoke-GitCapture -Arguments @('show', ":$RelativePath") -WorkingDirectory $RepoRoot
    if ($show.ExitCode -ne 0) { return }
    $text = ($show.Output -join "`n")
    if ($text.IndexOf([char]0) -ge 0) { [void]$script:skippedFiles.Add("$RelativePath (binary)"); return }
    $script:scannedFiles++
    Scan-Text -Text $text -DisplayPath $RelativePath
}

function Get-WorktreeFiles {
    param([string]$RepoRoot)
    $result = Invoke-GitCapture -Arguments @('status', '--porcelain=v1', '--untracked-files=all') -WorkingDirectory $RepoRoot
    if ($result.ExitCode -ne 0) { throw 'git status failed.' }
    $files = New-Object System.Collections.ArrayList
    foreach ($line in $result.Output) {
        if ($line.Length -lt 4) { continue }
        $status = $line.Substring(0, 2)
        if ($status -match 'D') { continue }
        $path = $line.Substring(3)
        if ($path -match ' -> ') { $path = ($path -split ' -> ')[-1] }
        $path = Unquote-GitPath $path
        if ($path) { [void]$files.Add($path) }
    }
    return $files
}

function Get-StagedFiles {
    param([string]$RepoRoot)
    $result = Invoke-GitCapture -Arguments @('diff', '--cached', '--name-only', '--diff-filter=ACMR') -WorkingDirectory $RepoRoot
    if ($result.ExitCode -ne 0) { throw 'git diff --cached failed.' }
    $files = New-Object System.Collections.ArrayList
    foreach ($line in $result.Output) {
        $path = Unquote-GitPath $line
        if ($path) { [void]$files.Add($path) }
    }
    return $files
}

function Get-TrackedFiles {
    param([string]$RepoRoot)
    $result = Invoke-GitCapture -Arguments @('ls-files') -WorkingDirectory $RepoRoot
    if ($result.ExitCode -ne 0) { throw 'git ls-files failed.' }
    $files = New-Object System.Collections.ArrayList
    foreach ($line in $result.Output) {
        $path = Unquote-GitPath $line
        if ($path) { [void]$files.Add($path) }
    }
    return $files
}

function Scan-BranchName {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name) -or $Name -eq 'HEAD') { return }
    foreach ($rule in $highRules) {
        if ([regex]::IsMatch($Name, $rule.Pattern)) {
            Add-Finding -Severity 'HIGH' -Rule 'BRANCH_NAME' -Path '<branch>' -Line 0 -Advice 'Rename the branch; it contains a credential-like string.'
            return
        }
    }
    if ($Name -match '(?i)(password|passwd|secret|token|apikey|api[_-]key)') {
        Add-Finding -Severity 'MEDIUM' -Rule 'BRANCH_NAME_KEYWORD' -Path '<branch>' -Line 0 -Advice 'Consider a neutral branch name that does not invite secret leakage.'
    }
}

try {
    if (-not (Test-Path -LiteralPath $RepoPath -PathType Container)) { throw "Repository path not found: $RepoPath" }
    Set-Location -LiteralPath $RepoPath
    $mode = $PSCmdlet.ParameterSetName

    if ($mode -eq 'Message' -or $mode -eq 'MessageFile' -or $mode -eq 'Branch') {
        if ($mode -eq 'Message') {
            Scan-Text -Text $Message -DisplayPath '<commit-message>'
        }
        elseif ($mode -eq 'MessageFile') {
            if (-not (Test-Path -LiteralPath $MessageFile -PathType Leaf)) { throw "Message file not found: $MessageFile" }
            $text = Read-TextFile -FullPath (Resolve-Path -LiteralPath $MessageFile).Path
            if ($null -eq $text) { throw 'Message file is binary.' }
            Scan-Text -Text $text -DisplayPath '<commit-message>'
        }
        else {
            Scan-BranchName -Name $Branch
        }
    }
    else {
        $repoRoot = Get-RepoRoot
        if (-not $repoRoot) { throw 'Not inside a Git repository.' }
        $files = New-Object System.Collections.ArrayList
        if ($mode -eq 'Paths') {
            foreach ($p in $Paths) {
                $resolved = Resolve-Path -LiteralPath $p -ErrorAction Stop
                foreach ($item in $resolved) {
                    if (Test-Path -LiteralPath $item.Path -PathType Container) {
                        Get-ChildItem -LiteralPath $item.Path -Recurse -File | ForEach-Object {
                            $rel = $_.FullName.Substring($repoRoot.TrimEnd('\').Length).TrimStart('\')
                            [void]$files.Add($rel)
                        }
                    }
                    else {
                        $rel = $item.Path.Substring($repoRoot.TrimEnd('\').Length).TrimStart('\')
                        [void]$files.Add($rel)
                    }
                }
            }
        }
        elseif ($mode -eq 'Staged') {
            $files = Get-StagedFiles -RepoRoot $repoRoot
        }
        elseif ($mode -eq 'Tracked') {
            $files = Get-TrackedFiles -RepoRoot $repoRoot
        }
        else {
            $files = Get-WorktreeFiles -RepoRoot $repoRoot
        }

        $uniqueFiles = @($files | Select-Object -Unique)
        $total = $uniqueFiles.Count
        $index = 0
        foreach ($file in $uniqueFiles) {
            $index++
            if (Test-ExcludedPath -RelativePath $file -RepoRoot $repoRoot) { continue }
            if (-not $Json -and $total -gt 200 -and ($index % 200 -eq 0)) {
                Write-Host "  progress: $index/$total files" -ForegroundColor DarkGray
            }
            Test-SensitiveFileName -Path $file
            if ($mode -eq 'Staged') { Scan-StagedFile -RelativePath $file -RepoRoot $repoRoot }
            else { Scan-WorktreeFile -RelativePath $file -RepoRoot $repoRoot }
        }
    }

    $high = @($script:findings | Where-Object { $_.Severity -eq 'HIGH' })
    $medium = @($script:findings | Where-Object { $_.Severity -eq 'MEDIUM' })
    $exitCode = if ($high.Count -gt 0) { 2 } elseif ($medium.Count -gt 0) { 3 } else { 0 }
    $verdict = if ($high.Count -gt 0) { 'BLOCK' } elseif ($medium.Count -gt 0) { 'REVIEW' } else { 'CLEAN' }

    if ($Json) {
        [pscustomobject]@{
            ok          = ($exitCode -eq 0)
            verdict     = $verdict
            mode        = $mode
            filesScanned = $script:scannedFiles
            skipped     = @($script:skippedFiles | ForEach-Object { Redact-Text $_ })
            counts      = [pscustomobject]@{ high = $high.Count; medium = $medium.Count }
            findings    = @($script:findings)
        } | ConvertTo-Json -Depth 6
    }
    else {
        Write-Host "Secret scan ($mode): $($script:scannedFiles) file(s) scanned" -ForegroundColor Cyan
        if ($script:skippedFiles.Count -gt 0) {
            Write-Host "Skipped: $($script:skippedFiles.Count) binary/large file(s)" -ForegroundColor DarkGray
        }
        foreach ($f in $script:findings) {
            $color = if ($f.Severity -eq 'HIGH') { 'Red' } else { 'Yellow' }
            Write-Host "[$($f.Severity)] $($f.Rule) at $($f.Path):$($f.Line)" -ForegroundColor $color
            Write-Host "  -> $($f.Advice)" -ForegroundColor DarkGray
        }
        Write-Host ''
        Write-Host "RESULT: $verdict ($($high.Count) HIGH, $($medium.Count) MEDIUM)" -ForegroundColor $(if ($exitCode -eq 0) { 'Green' } else { 'Red' })
        if ($exitCode -ne 0) {
            Write-Host 'Do not stage or commit until every finding is resolved or explicitly approved by the user.' -ForegroundColor Yellow
        }
    }
    exit $exitCode
}
catch {
    $message = Redact-Text $_.Exception.Message
    if ($Json) {
        [pscustomobject]@{ ok = $false; verdict = 'ERROR'; error = $message } | ConvertTo-Json -Depth 4
    }
    else {
        Write-Host "SCANNER ERROR: $message" -ForegroundColor Red
    }
    exit 1
}
