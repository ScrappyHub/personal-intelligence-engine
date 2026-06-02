param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$SessionId = "pie_goal_lineage_selftest"
$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)

if(Test-Path -LiteralPath $RunRoot -PathType Container){
  Remove-Item -LiteralPath $RunRoot -Recurse -Force
}

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_intent_record_v1.ps1") `
  -RepoRoot $RepoRoot `
  -Goal "Build goal lineage safely" `
  -Status "open" `
  -SessionId $SessionId `
  -Repo $RepoRoot `
  -Notes "goal lineage selftest seed" | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_GOAL_LINEAGE_INTENT_RECORD_FAIL" }

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_intent_resume_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -GoalContains "goal lineage" | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_GOAL_LINEAGE_INTENT_RESUME_FAIL" }

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_orchestrate_select_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -Goal "Build goal lineage safely" `
  -DefaultChainId "repo.health.basic" `
  -AutoConfirmAllowed | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_GOAL_LINEAGE_ORCH_SELECT_FAIL" }

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_execution_replay_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_GOAL_LINEAGE_REPLAY_FAIL" }

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_reason_trace_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -Goal "Build goal lineage safely" `
  -SelectedCommand "git status" `
  -WorkingDirectory $RepoRoot | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_GOAL_LINEAGE_REASON_TRACE_FAIL" }

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_experience_record_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -Goal "Build goal lineage safely" `
  -Outcome "success" `
  -ChainId "repo.health.basic" `
  -Notes "goal lineage selftest success" | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_GOAL_LINEAGE_EXPERIENCE_FAIL" }

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_goal_lineage_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -Goal "Build goal lineage safely" | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_GOAL_LINEAGE_CHILD_FAIL" }

$Latest = Join-Path $RunRoot "goal_lineage\latest_goal_lineage.json"

if(-not (Test-Path -LiteralPath $Latest -PathType Leaf)){
  throw "PIE_GOAL_LINEAGE_LATEST_MISSING"
}

$Obj = Get-Content -LiteralPath $Latest -Raw | ConvertFrom-Json

if($Obj.schema -ne "pie.goal.lineage.v1"){
  throw "PIE_GOAL_LINEAGE_SCHEMA_BAD"
}

if(@($Obj.artifacts).Count -lt 3){
  throw "PIE_GOAL_LINEAGE_ARTIFACTS_TOO_FEW"
}

$Kinds = @($Obj.artifacts | ForEach-Object { [string]$_.kind })

if(-not ($Kinds -contains "intent_resume")){
  throw "PIE_GOAL_LINEAGE_MISSING_INTENT_RESUME"
}

if(-not ($Kinds -contains "execution_replay")){
  throw "PIE_GOAL_LINEAGE_MISSING_REPLAY"
}

if(-not ($Kinds -contains "reason_trace")){
  throw "PIE_GOAL_LINEAGE_MISSING_REASON_TRACE"
}

Write-Host "PIE_GOAL_LINEAGE_SELFTEST_OK" -ForegroundColor Green
