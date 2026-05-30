param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$SessionId = "pie_orch_select_selftest"
$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)
$ExperienceRoot = Join-Path $RepoRoot "memory\experience"
$ExperienceLog = Join-Path $ExperienceRoot "experience.ndjson"
$Enc = New-Object System.Text.UTF8Encoding($false)

function Write-Utf8NoBomLf {
  param(
    [Parameter(Mandatory=$true)][string]$Path,
    [Parameter(Mandatory=$true)][AllowEmptyString()][string]$Text
  )

  $Dir = Split-Path -Parent $Path
  if(-not (Test-Path -LiteralPath $Dir -PathType Container)){
    New-Item -ItemType Directory -Force -Path $Dir | Out-Null
  }

  $Clean = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $Clean.EndsWith("`n")){ $Clean += "`n" }

  [System.IO.File]::WriteAllText($Path,$Clean,$Enc)
}

if(Test-Path -LiteralPath $RunRoot -PathType Container){
  Remove-Item -LiteralPath $RunRoot -Recurse -Force
}

New-Item -ItemType Directory -Force -Path $RunRoot | Out-Null
New-Item -ItemType Directory -Force -Path $ExperienceRoot | Out-Null

Write-Utf8NoBomLf -Path (Join-Path $RunRoot "project_repo.txt") -Text $RepoRoot

$Seed = [ordered]@{
  schema = "pie.experience.entry.v1"
  session_id = "seed"
  goal = "seed successful repo health experience"
  chain_id = "repo.health.basic"
  outcome = "success"
  notes = "seed for orchestration selector selftest"
  execution_receipts = ""
  execution_receipts_sha256 = ""
  replay = ""
  replay_sha256 = "seed_replay_sha"
  reason_trace = ""
  reason_trace_sha256 = "seed_reason_sha"
  freeze = ""
  freeze_hash = ""
  created_utc = [DateTime]::UtcNow.ToString("o")
}

[System.IO.File]::AppendAllText($ExperienceLog,(($Seed | ConvertTo-Json -Depth 20 -Compress) + "`n"),$Enc)

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_orchestrate_select_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -Goal "Use experience-informed repo health chain." `
  -DefaultChainId "repo.health.basic" `
  -AutoConfirmAllowed | Out-Host

if($LASTEXITCODE -ne 0){
  throw "PIE_ORCH_SELECT_SELFTEST_CHILD_FAIL"
}

$Decision = Join-Path $RunRoot "orchestration_decisions\latest_orchestration_decision.json"

if(-not (Test-Path -LiteralPath $Decision -PathType Leaf)){
  throw "PIE_ORCH_SELECT_DECISION_MISSING"
}

$Obj = Get-Content -LiteralPath $Decision -Raw | ConvertFrom-Json

if($Obj.selected_chain_id -ne "repo.health.basic"){
  throw "PIE_ORCH_SELECT_WRONG_CHAIN"
}

if([int]$Obj.selected_score -lt 1){
  throw "PIE_ORCH_SELECT_SCORE_BAD"
}

$Receipt = Join-Path $RunRoot "execution\execution_receipts.ndjson"
if(-not (Test-Path -LiteralPath $Receipt -PathType Leaf)){
  throw "PIE_ORCH_SELECT_RECEIPT_MISSING"
}

Write-Host "PIE_ORCH_SELECT_SELFTEST_OK" -ForegroundColor Green
