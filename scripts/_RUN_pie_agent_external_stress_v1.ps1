param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$false)][int]$Iterations = 25
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$Message){
  throw $Message
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$backendCmd = Join-Path $RepoRoot "scripts\pie_backend_local_mock_or_model_v1.ps1"
if(-not (Test-Path -LiteralPath $backendCmd -PathType Leaf)){
  Die ("MISSING_BACKEND_CMD: " + $backendCmd)
}

[Environment]::SetEnvironmentVariable("PIE_LOCAL_BACKEND_CMD",("powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"" + $backendCmd + "`""),"Process")
[Environment]::SetEnvironmentVariable("MODEL_BACKEND_MODE","mock","Process")

$pass = 0
$fail = 0

Write-Host "PIE_AGENT_EXTERNAL_STRESS_START" -ForegroundColor DarkCyan

for($i=1; $i -le $Iterations; $i++){
  $sid = ("external_stress_" + $i)
  try {
    & (Join-Path $RepoRoot "scripts\pie_agent_start_v1.ps1") `
      -RepoRoot $RepoRoot `
      -SessionId $sid `
      -ModelId "external-stress-model" `
      -BackendMode "external" | Out-Host

    $r = ((& (Join-Path $RepoRoot "scripts\pie_agent_send_v1.ps1") `
      -RepoRoot $RepoRoot `
      -SessionId $sid `
      -Prompt ("hello from " + $sid)) | Out-String).Trim()

    if([string]::IsNullOrWhiteSpace($r)){
      throw "EMPTY_RESPONSE"
    }

    & (Join-Path $RepoRoot "scripts\pie_agent_stop_v1.ps1") `
      -RepoRoot $RepoRoot `
      -SessionId $sid | Out-Host

    $pass++
    Write-Host ("PASS: " + $sid) -ForegroundColor Green
  } catch {
    $fail++
    Write-Host ("FAIL: " + $sid + " :: " + $_.Exception.Message) -ForegroundColor Red
  }
}

if($fail -ne 0){
  Die ("PIE_AGENT_EXTERNAL_STRESS_FAIL pass=" + $pass + " fail=" + $fail)
}

Write-Host ("PIE_AGENT_EXTERNAL_STRESS_OK pass=" + $pass + " fail=" + $fail) -ForegroundColor Green