param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$false)][int]$Iterations = 50
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$Message){
  throw $Message
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

if($Iterations -lt 1){
  Die "ITERATIONS_MUST_BE_GE_1"
}

$pass = 0
$fail = 0

for($i=1; $i -le $Iterations; $i++){
  $sessionId = ("stress_agent_" + $i)
  $sessionRoot = Join-Path (Join-Path $RepoRoot "runs") $sessionId

  if(Test-Path -LiteralPath $sessionRoot -PathType Container){
    Remove-Item -LiteralPath $sessionRoot -Recurse -Force
  }

  try {
    Write-Host ("AGENT_RUN " + $sessionId) -ForegroundColor DarkCyan

    & (Join-Path $RepoRoot "scripts\pie_agent_start_v1.ps1") `
      -RepoRoot $RepoRoot `
      -SessionId $sessionId `
      -ModelId "stress-model" `
      -BackendMode "mock" | Out-Host

    $r1 = ((& (Join-Path $RepoRoot "scripts\pie_agent_send_v1.ps1") `
      -RepoRoot $RepoRoot `
      -SessionId $sessionId `
      -Prompt ("hello from " + $sessionId)) | Out-String).Trim()

    $r2 = ((& (Join-Path $RepoRoot "scripts\pie_agent_send_v1.ps1") `
      -RepoRoot $RepoRoot `
      -SessionId $sessionId `
      -Prompt ("second turn for " + $sessionId)) | Out-String).Trim()

    if([string]::IsNullOrWhiteSpace($r1)){ Die ("EMPTY_RESPONSE_1: " + $sessionId) }
    if([string]::IsNullOrWhiteSpace($r2)){ Die ("EMPTY_RESPONSE_2: " + $sessionId) }

    & (Join-Path $RepoRoot "scripts\pie_agent_stop_v1.ps1") `
      -RepoRoot $RepoRoot `
      -SessionId $sessionId | Out-Host

    $pass++
  } catch {
    $fail++
    Write-Host ("AGENT_RUN_FAIL: " + $sessionId + " :: " + $_.Exception.Message) -ForegroundColor Yellow
  }
}

if($fail -ne 0){
  Die ("PIE_AGENT_STRESS_FAIL pass=" + $pass + " fail=" + $fail)
}

Write-Host ("PIE_AGENT_STRESS_OK pass=" + $pass + " fail=" + $fail) -ForegroundColor Green