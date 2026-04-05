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
  [System.IO.File]::ReadAllText($Path,$enc)
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$SessionId = "selftest_external_A"
$SessionRoot = Join-Path (Join-Path $RepoRoot "runs") $SessionId

if(Test-Path -LiteralPath $SessionRoot -PathType Container){
  Remove-Item -LiteralPath $SessionRoot -Recurse -Force
}

$backendCmd = (Get-Command powershell.exe -ErrorAction Stop).Source + ' -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + (Join-Path $RepoRoot 'scripts\pie_agent_backend_mock_v1.ps1') + '"'
[Environment]::SetEnvironmentVariable("PIE_LOCAL_BACKEND_CMD",$backendCmd,"Process")

Write-Host "PIE_AGENT_EXTERNAL_SELFTEST_START" -ForegroundColor DarkCyan

& (Join-Path $RepoRoot "scripts\pie_agent_start_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -ModelId "external-selftest-model" `
  -BackendMode "external" | Out-Host

$r1 = ((& (Join-Path $RepoRoot "scripts\pie_agent_send_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -Prompt "offline external hello") | Out-String).Trim()

if([string]::IsNullOrWhiteSpace($r1)){
  Die "EXTERNAL_SELFTEST_EMPTY_RESPONSE"
}
if($r1 -notmatch '\[external-mock\]'){
  Die ("EXTERNAL_SELFTEST_BAD_RESPONSE: " + $r1)
}

$requestPath = Join-Path $SessionRoot "state\backend_request.json"
$responsePath = Join-Path $SessionRoot "state\backend_response.txt"

if(-not (Test-Path -LiteralPath $requestPath -PathType Leaf)){
  Die ("EXTERNAL_SELFTEST_REQUEST_MISSING: " + $requestPath)
}
if(-not (Test-Path -LiteralPath $responsePath -PathType Leaf)){
  Die ("EXTERNAL_SELFTEST_RESPONSE_MISSING: " + $responsePath)
}

& (Join-Path $RepoRoot "scripts\pie_agent_stop_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId | Out-Host

Write-Host "PIE_AGENT_EXTERNAL_SELFTEST_OK" -ForegroundColor Green