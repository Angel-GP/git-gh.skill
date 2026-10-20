#requires -Version 5.1
<#
.SYNOPSIS
  Build detailed Markdown release notes from Conventional Commits.
.DESCRIPTION
  Read-only: inspects git history and writes a local Markdown file. It never
  creates tags, pushes, or calls GitHub. Review and confirm the notes before
  running git tag / git push / gh release create.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Version,
    [Parameter(Mandatory = $true)][string]$FromTag,
    [string]$ToRef = 'HEAD',
    [string]$RepoUrl,
    [string]$OutputPath,
    [string]$RepoPath = (Get-Location).Path,
    [switch]$NoLinks
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_common.ps1')

function Fail([string]$Message) {
    Write-Host "ERROR: $Message" -ForegroundColor Red
    exit 1
}

if ($Version -notmatch '^v\d+\.\d+\.\d+$') {
    Fail "Version must use the vX.Y.Z form (SemVer), got '$Version'."
}
if ($FromTag -notmatch '^v?\d+\.\d+\.\d+$') {
    Fail "FromTag must be an existing tag such as v1.2.3, got '$FromTag'."
}

if (-not (Test-Path -LiteralPath $RepoPath -PathType Container)) { Fail "Repository path not found: $RepoPath" }
Set-Location -LiteralPath $RepoPath
$repoRoot = Get-RepoRoot
if (-not $repoRoot) { Fail 'Not inside a Git repository.' }

$tagCheck = Invoke-GitCapture -Arguments @('rev-parse', '-q', '--verify', "refs/tags/$Version") -WorkingDirectory $repoRoot
if ($tagCheck.ExitCode -eq 0) { Fail "Tag $Version already exists. Choose the next version." }

$fromCheck = Invoke-GitCapture -Arguments @('rev-parse', '-q', '--verify', "refs/tags/$FromTag") -WorkingDirectory $repoRoot
if ($fromCheck.ExitCode -ne 0) { Fail "Base tag '$FromTag' was not found. Fetch tags first (git fetch --tags)." }

$range = "$FromTag..$ToRef"
$log = Invoke-GitCapture -Arguments @(
    'log', '--no-merges', '--date=short',
    '--format=%H%x1f%ad%x1f%s%x1f%b%x1e', $range
) -WorkingDirectory $repoRoot
if ($log.ExitCode -ne 0) { Fail "git log failed for range $range." }

$raw = ($log.Output -join "`n")
$records = @($raw -split [char]0x1e | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
if ($records.Count -eq 0) { Fail "No commits found in $range." }

$allowedTypes = @('feat', 'fix', 'docs', 'style', 'refactor', 'perf', 'test', 'build', 'ci', 'chore', 'revert')
$groupTitles = [ordered]@{
    feat     = '新增'
    fix      = '修复'
    perf     = '性能'
    refactor = '重构'
    docs     = '文档'
    test     = '测试'
    build    = '构建'
    ci       = 'CI'
    style    = '样式'
    chore    = '杂项'
    revert   = '回滚'
    other    = '其他变更'
}
$groups = @{}
foreach ($key in $groupTitles.Keys) { $groups[$key] = New-Object System.Collections.ArrayList }
$breaking = New-Object System.Collections.ArrayList

if ($RepoUrl) {
    $repoInfo = ConvertTo-RepoInfo $RepoUrl
}
else {
    $remote = Get-RemoteUrl
    $repoInfo = if ($remote) { ConvertTo-RepoInfo $remote } else { $null }
}

function Get-CommitUrl([string]$Sha) {
    if ($NoLinks -or -not $repoInfo -or -not $repoInfo.WebUrl -or $repoInfo.Host -ne 'github.com') { return $null }
    return "$($repoInfo.WebUrl)/commit/$Sha"
}

foreach ($record in $records) {
    $parts = $record.Split(@([char]0x1f), 4)
    if ($parts.Count -lt 3) { continue }
    $sha = $parts[0].Trim()
    $date = $parts[1].Trim()
    $subject = Redact-Text ($parts[2].Trim())
    $body = if ($parts.Count -ge 4) { Redact-Text $parts[3] } else { '' }

    $type = 'other'
    $scope = ''
    $description = $subject
    $isBreaking = $false

    $m = [regex]::Match($subject, '^(?<type>[A-Za-z]+)(?:\((?<scope>[^)]*)\))?(?<bang>!)?:\s*(?<desc>.+)$')
    if ($m.Success -and $allowedTypes -contains $m.Groups['type'].Value.ToLowerInvariant()) {
        $type = $m.Groups['type'].Value.ToLowerInvariant()
        $scope = $m.Groups['scope'].Value
        $description = $m.Groups['desc'].Value
        $isBreaking = $m.Groups['bang'].Value -eq '!'
    }

    $breakNotes = @()
    foreach ($bm in [regex]::Matches($body, '(?im)^BREAKING[ -]CHANGE:\s*(?<note>.+)$')) {
        $breakNotes += $bm.Groups['note'].Value.Trim()
    }
    if ($breakNotes.Count -gt 0) { $isBreaking = $true }

    $short = $sha.Substring(0, [Math]::Min(7, $sha.Length))
    $url = Get-CommitUrl $sha
    $link = if ($url) { " ([$short]($url))" } else { " ($short)" }
    $scopeText = if ($scope) { "**$scope**: " } else { '' }
    $item = "- $scopeText$description$link"

    if ($isBreaking) {
        $notesText = if ($breakNotes.Count -gt 0) { $breakNotes -join ' ' } else { '该提交标记为破坏性变更（!），请查看提交详情。' }
        [void]$breaking.Add([pscustomobject]@{ Item = $item; Note = $notesText; Date = $date })
    }
    if ($groups.ContainsKey($type)) { [void]$groups[$type].Add($item) }
    else { [void]$groups['other'].Add($item) }
}

$total = $records.Count
$featCount = $groups['feat'].Count
$fixCount = $groups['fix'].Count
$otherCount = $total - $featCount - $fixCount

$fromDisplay = if ($FromTag.StartsWith('v')) { $FromTag } else { "v$FromTag" }
$compareUrl = $null
if (-not $NoLinks -and $repoInfo -and $repoInfo.Host -eq 'github.com' -and $repoInfo.WebUrl) {
    $compareUrl = "$($repoInfo.WebUrl)/compare/$fromDisplay...$Version"
}

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("## 版本摘要")
[void]$sb.AppendLine()
[void]$sb.AppendLine("本版本共包含 **$total** 个提交：**$featCount** 项新增、**$fixCount** 项修复、**$otherCount** 项其他变更。")
if ($breaking.Count -gt 0) {
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('> [!WARNING]')
    [void]$sb.AppendLine("> **本版本包含 $($breaking.Count) 项破坏性变更**，升级前请先阅读下方说明并完成迁移。")
}
[void]$sb.AppendLine()

if ($breaking.Count -gt 0) {
    [void]$sb.AppendLine('## 破坏性变更')
    [void]$sb.AppendLine()
    foreach ($b in $breaking) {
        [void]$sb.AppendLine($b.Item)
        [void]$sb.AppendLine("  - $($b.Note)")
    }
    [void]$sb.AppendLine()
}

foreach ($key in $groupTitles.Keys) {
    if ($key -eq 'other' -or $groups[$key].Count -eq 0) { continue }
    [void]$sb.AppendLine("## $($groupTitles[$key])")
    [void]$sb.AppendLine()
    foreach ($item in $groups[$key]) { [void]$sb.AppendLine($item) }
    [void]$sb.AppendLine()
}
if ($groups['other'].Count -gt 0) {
    [void]$sb.AppendLine('## 其他变更')
    [void]$sb.AppendLine()
    foreach ($item in $groups['other']) { [void]$sb.AppendLine($item) }
    [void]$sb.AppendLine()
}

[void]$sb.AppendLine('## 升级步骤')
[void]$sb.AppendLine()
[void]$sb.AppendLine("1. 备份当前部署与配置。")
[void]$sb.AppendLine("2. 获取新版本：``git fetch --tags origin && git checkout $Version``。")
[void]$sb.AppendLine("3. 按项目说明重新安装依赖，并执行必要的数据迁移。")
[void]$sb.AppendLine("4. 运行冒烟测试，确认关键路径正常。")
if ($breaking.Count -gt 0) {
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('> 破坏性变更需要额外迁移步骤，请先处理上方“破坏性变更”中的说明。')
}
[void]$sb.AppendLine()

[void]$sb.AppendLine('## 完整变更')
[void]$sb.AppendLine()
[void]$sb.AppendLine("- 提交范围：``$fromDisplay...$Version``（$total 个提交）")
if ($compareUrl) {
    [void]$sb.AppendLine("- 完整对比：$compareUrl")
}
else {
    [void]$sb.AppendLine('- 完整对比：请在此处补充仓库的 compare 链接。')
}
[void]$sb.AppendLine()

$text = $sb.ToString().TrimEnd() + "`n"

Write-Host $text
if ($OutputPath) {
    $full = [System.IO.Path]::GetFullPath($OutputPath)
    $dir = Split-Path -Parent $full
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($full, $text, $utf8)
    Write-Host "Wrote: $full" -ForegroundColor Green
}
exit 0
