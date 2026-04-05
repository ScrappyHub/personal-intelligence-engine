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
$backend  = Join-Path $RepoRoot "scripts\pie_backend_local_mock_v1.ps1"
if(-not (Test-Path -LiteralPath $backend -PathType Leaf)){
  Die ("MISSING_BACKEND_ADAPTER: " + $backend)
}

[Environment]::SetEnvironmentVariable("PIE_LOCAL_BACKEND_CMD", ("powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File """ + $backend + """"), "Process")

$sessionId   = "external_selftest_A"
$sessionRoot = Join-Path (Join-Path $RepoRoot "runs") $sessionId

if(Test-Path -LiteralPath $sessionRoot -PathType Container){
  Remove-Item -LiteralPath $sessionRoot -Recurse -Force
}

Write-Host "PIE_AGENT_EXTERNAL_BACKEND_SELFTEST_START" -ForegroundColor DarkCyan

& (Join-Path $RepoRoot "scripts\pie_agent_start_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $sessionId `
  -ModelId "external-selftest-model" `
  -BackendMode "external" | Out-Host

$r1 = ((& (Join-Path $RepoRoot "scripts\pie_agent_send_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $sessionId `
  -Prompt "offline external one") | Out-String).Trim()

$r2 = ((& (Join-Path $RepoRoot "scripts\pie_agent_send_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $sessionId `
  -Prompt "offline external two") | Out-String).Trim()

if([string]::IsNullOrWhiteSpace($r1)){ Die "EXTERNAL_EMPTY_RESPONSE_1" }
if([string]::IsNullOrWhiteSpace($r2)){ Die "EXTERNAL_EMPTY_RESPONSE_2" }

if($r1 -notmatch '\[local-mock\]'){ Die "EXTERNAL_RESPONSE_1_BAD_SHAPE" }
if($r2 -notmatch '\[local-mock\]'){ Die "EXTERNAL_RESPONSE_2_BAD_SHAPE" }

$reqPath = Join-Path $sessionRoot "state\backend_request.json"
if(-not (Test-Path -LiteralPath $reqPath -PathType Leaf)){
  Die ("EXTERNAL_REQUEST_NOT_WRITTEN: " + $reqPath)
}

$respPath = Join-Path $sessionRoot "state\backend_response.txt"
if(-not (Test-Path -LiteralPath $respPath -PathType Leaf)){
  Die ("EXTERNAL_RESPONSE_FILE_NOT_WRITTEN: " + $respPath)
}

$transcript = Read-Utf8NoBom (Join-Path $sessionRoot "transcript.ndjson")
if($transcript -notmatch 'offline external one'){ Die "EXTERNAL_TRANSCRIPT_MISSING_1" }
if($transcript -notmatch 'offline external two'){ Die "EXTERNAL_TRANSCRIPT_MISSING_2" }

& (Join-Path $RepoRoot "scripts\pie_agent_stop_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $sessionId | Out-Host

Write-Host "PIE_AGENT_EXTERNAL_BACKEND_SELFTEST_OK" -ForegroundColor Green