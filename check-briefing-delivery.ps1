param(
    [string]$TokenFile = "",
    [string]$StateDir = "",
    [string]$LogFile = ""
)

$ErrorActionPreference = "Stop"

$workspaceRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($StateDir)) {
    $StateDir = Join-Path $workspaceRoot ".codex-automation-state"
}
if ([string]::IsNullOrWhiteSpace($TokenFile)) {
    $TokenFile = Join-Path $StateDir "pushplus-token.txt"
}
if ([string]::IsNullOrWhiteSpace($LogFile)) {
    $LogFile = Join-Path $StateDir "briefing-watchdog.log"
}

function Get-ShanghaiDate {
    $tz = [System.TimeZoneInfo]::FindSystemTimeZoneById("China Standard Time")
    return [System.TimeZoneInfo]::ConvertTimeFromUtc((Get-Date).ToUniversalTime(), $tz).ToString("yyyy-MM-dd")
}

function Read-StateDate {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }
    return ((Get-Content -LiteralPath $Path -Raw -Encoding UTF8) -split "\r?\n")[0].Trim()
}

function Write-Log {
    param([string]$Message)
    $dir = Split-Path -Parent $LogFile
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss K"
    Add-Content -LiteralPath $LogFile -Value "[$stamp] $Message" -Encoding UTF8
}

function Send-PushPlus {
    param(
        [string]$Token,
        [string]$Content
    )
    $body = [ordered]@{
        token = $Token
        title = "Daily briefing delivery watchdog"
        content = $Content
        template = "markdown"
    } | ConvertTo-Json -Depth 5

    return Invoke-RestMethod `
        -Uri "https://www.pushplus.plus/send" `
        -Method Post `
        -ContentType "application/json; charset=utf-8" `
        -Body ([System.Text.Encoding]::UTF8.GetBytes($body))
}

$today = Get-ShanghaiDate
$generalPath = Join-Path $StateDir "general-news-last-push.txt"
$mineralsPath = Join-Path $StateDir "critical-minerals-last-push.txt"

$generalDate = Read-StateDate -Path $generalPath
$mineralsDate = Read-StateDate -Path $mineralsPath

$missing = @()
if ($generalDate -ne $today) {
    $missing += "General news: state is '$generalDate', expected $today"
}
if ($mineralsDate -ne $today) {
    $missing += "Critical minerals: state is '$mineralsDate', expected $today"
}

if ($missing.Count -eq 0) {
    Write-Log "OK: both briefings delivered for $today."
    exit 0
}

if (-not (Test-Path -LiteralPath $TokenFile)) {
    Write-Log "ALERT_NOT_SENT: missing token file. Missing briefings: $($missing -join '; ')"
    exit 2
}

$token = (Get-Content -LiteralPath $TokenFile -Raw -Encoding UTF8).Trim()
if ([string]::IsNullOrWhiteSpace($token)) {
    Write-Log "ALERT_NOT_SENT: empty token file. Missing briefings: $($missing -join '; ')"
    exit 2
}

$missingLines = ($missing | ForEach-Object { "- $_" }) -join "`n"
$content = @"
# Daily briefing delivery watchdog

Check date: $today

The following briefing state files are not marked as delivered today:

$missingLines

Meaning: the Codex automation likely did not finish successfully, or the state file was not updated after PushPlus success. Please open Codex and ask it to resend the missing briefing.
"@

$response = Send-PushPlus -Token $token -Content $content
$json = $response | ConvertTo-Json -Depth 10 -Compress
if ($response.code -eq 200) {
    Write-Log "ALERT_SENT: $json"
    exit 0
}

Write-Log "ALERT_FAILED: $json"
exit 3
