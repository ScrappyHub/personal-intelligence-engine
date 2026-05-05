param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$Message){
  throw $Message
}

function Read-Utf8NoBom([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){
    Die ("MISSING_FILE: " + $Path)
  }
  $enc = New-Object System.Text.UTF8Encoding($false)
  return [System.IO.File]::ReadAllText($Path,$enc)
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$backendCmd = Join-Path $RepoRoot "scripts\pie_backend_ollama_cmd_v1.ps1"
if(-not (Test-Path -LiteralPath $backendCmd -PathType Leaf)){
  Die ("MISSING_BACKEND_CMD: " + $backendCmd)
}

[Environment]::SetEnvironmentVariable("PIE_LOCAL_BACKEND_CMD",("powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"" + $backendCmd + "`""),"Process")

Write-Host "PIE_AGENT_EXTERNAL_SELFTEST_START" -ForegroundColor DarkCyan

$sessionId = "external_selftest_A"
$sessionRoot = Join-Path (Join-Path $RepoRoot "runs") $sessionId
if(Test-Path -LiteralPath $sessionRoot -PathType Container){
  Remove-Item -LiteralPath $sessionRoot -Recurse -Force
}

& (Join-Path $RepoRoot "scripts\pie_agent_start_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $sessionId `
  -ModelId "ollama-local" `
  -BackendMode "external" | Out-Host

$r1 = ((& (Join-Path $RepoRoot "scripts\pie_agent_send_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $sessionId `
  -Prompt "Say: PIE external offline path is alive.") | Out-String).Trim()

if([string]::IsNullOrWhiteSpace($r1)){
  Die "EXTERNAL_SELFTEST_EMPTY_RESPONSE"
}

$transcript = Read-Utf8NoBom (Join-Path $sessionRoot "transcript.ndjson")
if($transcript -notmatch 'PIE external offline path is alive'){
  Die "EXTERNAL_SELFTEST_TRANSCRIPT_MISSING_USER"
}

& (Join-Path $RepoRoot "scripts\pie_agent_stop_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $sessionId | Out-Host

Write-Host "PIE_AGENT_EXTERNAL_SELFTEST_OK" -ForegroundColor Green