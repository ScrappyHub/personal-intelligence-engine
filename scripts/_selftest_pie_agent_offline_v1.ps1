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

function New-SessionId([string]$Suffix){
  return ("selftest_" + $Suffix)
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

Write-Host "PIE_AGENT_OFFLINE_SELFTEST_START" -ForegroundColor DarkCyan

$session1 = New-SessionId "A"
$session2 = New-SessionId "B"

$session1Root = Join-Path (Join-Path $RepoRoot "runs") $session1
$session2Root = Join-Path (Join-Path $RepoRoot "runs") $session2

if(Test-Path -LiteralPath $session1Root -PathType Container){
  Remove-Item -LiteralPath $session1Root -Recurse -Force
}
if(Test-Path -LiteralPath $session2Root -PathType Container){
  Remove-Item -LiteralPath $session2Root -Recurse -Force
}

& (Join-Path $RepoRoot "scripts\pie_agent_start_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $session1 `
  -ModelId "selftest-model" `
  -BackendMode "mock" | Out-Host

$r1 = ((& (Join-Path $RepoRoot "scripts\pie_agent_send_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $session1 `
  -Prompt "hello one") | Out-String).Trim()

$r2 = ((& (Join-Path $RepoRoot "scripts\pie_agent_send_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $session1 `
  -Prompt "hello two") | Out-String).Trim()

if([string]::IsNullOrWhiteSpace($r1)){
  Die "SELFTEST_EMPTY_RESPONSE_1"
}
if([string]::IsNullOrWhiteSpace($r2)){
  Die "SELFTEST_EMPTY_RESPONSE_2"
}

& (Join-Path $RepoRoot "scripts\pie_agent_stop_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $session1 | Out-Host

& (Join-Path $RepoRoot "scripts\pie_agent_start_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $session2 `
  -ModelId "selftest-model" `
  -BackendMode "mock" | Out-Host

$r3 = ((& (Join-Path $RepoRoot "scripts\pie_agent_send_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $session2 `
  -Prompt "fresh session") | Out-String).Trim()

if([string]::IsNullOrWhiteSpace($r3)){
  Die "SELFTEST_EMPTY_RESPONSE_3"
}

& (Join-Path $RepoRoot "scripts\pie_agent_stop_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $session2 | Out-Host

$t1 = Read-Utf8NoBom (Join-Path $session1Root "transcript.ndjson")
$t2 = Read-Utf8NoBom (Join-Path $session2Root "transcript.ndjson")

if($t1 -notmatch 'hello one'){
  Die "SELFTEST_TRANSCRIPT_1_MISSING"
}
if($t1 -notmatch 'hello two'){
  Die "SELFTEST_TRANSCRIPT_2_MISSING"
}
if($t2 -notmatch 'fresh session'){
  Die "SELFTEST_TRANSCRIPT_3_MISSING"
}
if($t2 -match 'hello one'){
  Die "SELFTEST_SESSION_ISOLATION_FAIL"
}

Write-Host "PIE_AGENT_OFFLINE_SELFTEST_OK" -ForegroundColor Green