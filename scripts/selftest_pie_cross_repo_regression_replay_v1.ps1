param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$SessionId = "pie_cross_repo_regression_replay_selftest"
$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)

if(Test-Path -LiteralPath $RunRoot -PathType Container){
  Remove-Item -LiteralPath $RunRoot -Recurse -Force
}

# Seed relation and template.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_graph_record_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SourceRepo $RepoRoot `
  -TargetRepo $RepoRoot `
  -Relation "related_to" `
  -Purpose "cross repo regression replay selftest relation" `
  -Evidence "selftest seed" | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_CROSS_REPO_REGRESSION_EDGE_SEED_FAIL" }

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_repo_template_record_v1.ps1") `
  -RepoRoot $RepoRoot `
  -TargetRepo $RepoRoot `
  -TemplateId "pie.cross.repo.regression.replay.selftest.v1" `
  -SequenceCsv "repo.status,repo.diff" `
  -Purpose "cross repo regression replay selftest template" `
  -Evidence "selftest seed" | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_CROSS_REPO_REGRESSION_TEMPLATE_SEED_FAIL" }

# Build plan.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_exec_plan_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -SourceRepo $RepoRoot `
  -Goal "Regression replay cross repo execution" `
  -Relation "related_to" | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_CROSS_REPO_REGRESSION_PLAN_FAIL" }

$PlanPath = Join-Path $RunRoot "cross_repo_exec_plans\latest_cross_repo_exec_plan.json"

if(-not (Test-Path -LiteralPath $PlanPath -PathType Leaf)){
  throw "PIE_CROSS_REPO_REGRESSION_PLAN_MISSING"
}

# Execute and aggregate baseline.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_execute_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -PlanPath $PlanPath `
  -Confirm | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_CROSS_REPO_REGRESSION_EXEC_BASE_FAIL" }

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_replay_aggregate_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_CROSS_REPO_REGRESSION_AGG_BASE_FAIL" }

$Baseline = Join-Path $RunRoot "cross_repo_replay\latest_cross_repo_replay_aggregate.json"

if(-not (Test-Path -LiteralPath $Baseline -PathType Leaf)){
  throw "PIE_CROSS_REPO_REGRESSION_BASELINE_MISSING"
}

# For deterministic selftest, compare aggregate against itself.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_regression_replay_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -BaselineAggregate $Baseline `
  -CandidateAggregate $Baseline | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_CROSS_REPO_REGRESSION_COMPARE_FAIL" }

$Latest = Join-Path $RunRoot "cross_repo_regression\latest_cross_repo_regression_replay.json"

if(-not (Test-Path -LiteralPath $Latest -PathType Leaf)){
  throw "PIE_CROSS_REPO_REGRESSION_LATEST_MISSING"
}

$Obj = Get-Content -LiteralPath $Latest -Raw | ConvertFrom-Json

if($Obj.schema -ne "pie.cross.repo.regression.replay.v1"){
  throw "PIE_CROSS_REPO_REGRESSION_SCHEMA_BAD"
}

if($Obj.status -ne "match"){
  throw "PIE_CROSS_REPO_REGRESSION_EXPECT_MATCH"
}

if([int]$Obj.finding_count -ne 0){
  throw "PIE_CROSS_REPO_REGRESSION_FINDINGS_EXPECT_ZERO"
}

Write-Host "PIE_CROSS_REPO_REGRESSION_REPLAY_SELFTEST_OK" -ForegroundColor Green
