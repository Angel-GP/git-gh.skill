# Shared helpers for the git-gh skill. PowerShell 5.1 compatible.
Set-StrictMode -Version 2.0

function Get-GitSkillRoot {
    if ($env:GITSKILL_ROOT) { return $env:GITSKILL_ROOT.TrimEnd('\') }
    return (Split-Path -Parent $PSScriptRoot)
}

function Get-GitSkillHome {
    if ($env:GITSKILL_HOME) { return $env:GITSKILL_HOME }
    return (Join-Path (Get-GitSkillRoot) 'home')
}

function Invoke-GitCapture {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [string]$WorkingDirectory = (Get-Location).Path
    )
    $old = Get-Location
    $oldEap = $ErrorActionPreference
    try {
        Set-Location -LiteralPath $WorkingDirectory
        # Native stderr becomes an ErrorRecord under PowerShell 5.1; keep it
        # non-terminating so callers can inspect ExitCode instead of catching.
        $ErrorActionPreference = 'Continue'
        $output = & git @Arguments 2>&1
        $code = $LASTEXITCODE
        return [pscustomobject]@{
            ExitCode = $code
            Output   = @($output | ForEach-Object { [string]$_ })
        }
    }
    finally {
        $ErrorActionPreference = $oldEap
        Set-Location -LiteralPath $old
    }
}

function Get-RepoRoot {
    $r = Invoke-GitCapture -Arguments @('rev-parse', '--show-toplevel')
    if ($r.ExitCode -ne 0 -or -not $r.Output) { return $null }
    $first = ($r.Output | Select-Object -First 1).Trim()
    if ($first -match '(?i)^fatal:') { return $null }
    return $first
}

function Get-RemoteUrl {
    param([string]$Remote = 'origin')
    $r = Invoke-GitCapture -Arguments @('remote', 'get-url', $Remote)
    if ($r.ExitCode -ne 0 -or -not $r.Output) { return $null }
    return ($r.Output | Select-Object -First 1).Trim()
}

function ConvertTo-RepoInfo {
    param([Parameter(Mandatory = $true)][string]$Url)

    $safe = $Url
    # Strip userinfo (may contain a token) before parsing or displaying.
    $safe = [regex]::Replace($safe, '^(?<scheme>https?://)[^/@]+@', '${scheme}')

    $hostName = $null
    $path = $null
    $protocol = $null

    $m = [regex]::Match($safe, '^(?<scheme>https?|ssh)://(?:[^@/]+@)?(?<host>[^/:]+)(?::\d+)?/(?<path>.+)$')
    if ($m.Success) {
        $protocol = $m.Groups['scheme'].Value
        $hostName = $m.Groups['host'].Value
        $path = $m.Groups['path'].Value
    }
    else {
        $m = [regex]::Match($safe, '^(?<user>[^@]+)@(?<host>[^:]+):(?<path>.+)$')
        if ($m.Success) {
            $protocol = 'ssh'
            $hostName = $m.Groups['host'].Value
            $path = $m.Groups['path'].Value
        }
    }

    if (-not $hostName -or -not $path) {
        return [pscustomobject]@{
            RawUrl = $safe; Host = $null; Owner = $null; Repo = $null
            Slug = $null; WebUrl = $null; Protocol = $null
        }
    }

    $path = $path.Trim('/')
    if ($path.EndsWith('.git')) { $path = $path.Substring(0, $path.Length - 4) }
    $parts = @($path -split '/' | Where-Object { $_ -ne '' })
    $repo = $parts[-1]
    $owner = if ($parts.Count -gt 1) { ($parts[0..($parts.Count - 2)] -join '/') } else { '' }

    return [pscustomobject]@{
        RawUrl   = $safe
        Host     = $hostName
        Owner    = $owner
        Repo     = $repo
        Slug     = if ($owner) { "$owner/$repo" } else { $repo }
        WebUrl   = "https://$hostName/$owner/$repo"
        Protocol = $protocol
    }
}

function Redact-Text {
    param([AllowNull()][string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return $Text }

    $result = $Text
    $result = [regex]::Replace($result, '(?is)-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----.*?-----END [A-Z0-9 ]*PRIVATE KEY-----', '***PRIVATE KEY REDACTED***')
    $result = [regex]::Replace($result, '(?i)(https?://)[^/\s:@]+:[^/\s@]+@', '${1}***:***@')
    $result = [regex]::Replace($result, '(?i)\bgh[pousr]_[A-Za-z0-9]{20,}\b', '***GITHUB_TOKEN***')
    $result = [regex]::Replace($result, '(?i)\bgithub_pat_[A-Za-z0-9_]{20,}\b', '***GITHUB_TOKEN***')
    $result = [regex]::Replace($result, '(?i)\bglpat-[A-Za-z0-9_-]{20,}\b', '***GITLAB_TOKEN***')
    $result = [regex]::Replace($result, '(?i)\bsk-[A-Za-z0-9_-]{20,}\b', '***API_KEY***')
    $result = [regex]::Replace($result, '(?i)\bAKIA[0-9A-Z]{16}\b', '***AWS_KEY***')
    $result = [regex]::Replace($result, '(?i)\bxox[baprs]-[A-Za-z0-9-]{10,}\b', '***SLACK_TOKEN***')
    $result = [regex]::Replace($result, '(?i)(Authorization:\s*Bearer\s+)\S+', '${1}***')
    return $result
}

function Write-Section {
    param([string]$Title)
    Write-Host ''
    Write-Host "== $Title ==" -ForegroundColor Cyan
}
