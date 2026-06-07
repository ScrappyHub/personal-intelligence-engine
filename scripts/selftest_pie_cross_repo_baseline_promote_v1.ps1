param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$SessionId = "pie_cross_repo_baseline_promote_selftest"
$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)

if(Test-Path -LiteralPath $RunRoot -PathType Container){
  Remove-Item -LiteralPath $RunRoot -Recurse -Force
}

# Seed relation.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_graph_record_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SourceRepo $RepoRoot `
  -TargetRepo $RepoRoot `
  -Relation "related_to" `
  -Purpose "cross repo baseline promote selftest relation" `
  -Evidence "baseline promote selftest seed" | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_BASELINE_PROMOTE_EDGE_SEED_FAIL" }

# Seed template.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_repo_template_record_v1.ps1") `
  -RepoRoot $RepoRoot `
  -TargetRepo $RepoRoot `
  -TemplateId "pie.cross.repo.baseline.promote.selftest.v1" `
  -SequenceCsv "repo.status,repo.diff" `
  -Purpose "cross repo baseline promote selftest template" `
  -Evidence "baseline promote selftest seed" | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_BASELINE_PROMOTE_TEMPLATE_SEED_FAIL" }

# Build plan.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_exec_plan_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -SourceRepo $RepoRoot `
  -Goal "Promote verified cross repo replay baseline" `
  -Relation "related_to" | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_BASELINE_PROMOTE_PLAN_FAIL" }

$PlanPath = Join-Path $RunRoot "cross_repo_exec_plans\latest_cross_repo_exec_plan.json"

if(-not (Test-Path -LiteralPath $PlanPath -PathType Leaf)){
  throw "PIE_BASELINE_PROMOTE_PLAN_MISSING"
}

# Execute.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_execute_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -PlanPath $PlanPath `
  -Confirm | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_BASELINE_PROMOTE_EXEC_FAIL" }

# Aggregate.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_replay_aggregate_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_BASELINE_PROMOTE_AGG_FAIL" }

$Aggregate = Join-Path $RunRoot "cross_repo_replay\latest_cross_repo_replay_aggregate.json"

if(-not (Test-Path -LiteralPath $Aggregate -PathType Leaf)){
  throw "PIE_BASELINE_PROMOTE_AGG_MISSING"
}

# Positive regression: aggregate against itself.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_regression_replay_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -BaselineAggregate $Aggregate `
  -CandidateAggregate $Aggregate | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_BASELINE_PROMOTE_REGRESSION_FAIL" }

$Regression = Join-Path $RunRoot "cross_repo_regression\latest_cross_repo_regression_replay.json"

if(-not (Test-Path -LiteralPath $Regression -PathType Leaf)){
  throw "PIE_BASELINE_PROMOTE_REGRESSION_MISSING"
}

$BaselineId = "selftest.cross_repo.baseline.v1"

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_baseline_promote_v1.ps1") `
  -RepoRoot $RepoRoot `
  -AggregatePath $Aggregate `
  -RegressionPath $Regression `
  -BaselineId $BaselineId `
  -Notes "selftest verified baseline promotion" | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_BASELINE_PROMOTE_CHILD_FAIL" }

$Promotion = Join-Path $RepoRoot ("memory\baselines\cross_repo\" + $BaselineId + ".promotion.json")
$Baseline = Join-Path $RepoRoot ("memory\baselines\cross_repo\" + $BaselineId + ".aggregate.json")
$Log = Join-Path $RepoRoot "memory\baselines\cross_repo\baseline_promotions.ndjson"

if(-not (Test-Path -LiteralPath $Promotion -PathType Leaf)){
  throw "PIE_BASELINE_PROMOTE_PROMOTION_MISSING"
}

if(-not (Test-Path -LiteralPath $Baseline -PathType Leaf)){
  throw "PIE_BASELINE_PROMOTE_BASELINE_MISSING"
}

if(-not (Test-Path -LiteralPath $Log -PathType Leaf)){
  throw "PIE_BASELINE_PROMOTE_LOG_MISSING"
}

$Obj = Get-Content -LiteralPath $Promotion -Raw | ConvertFrom-Json

if($Obj.schema -ne "pie.cross.repo.baseline.promotion.v1"){
  throw "PIE_BASELINE_PROMOTE_SCHEMA_BAD"
}

if($Obj.regression_status -ne "match"){
  throw "PIE_BASELINE_PROMOTE_REGRESSION_STATUS_BAD"
}

if([int]$Obj.regression_finding_count -ne 0){
  throw "PIE_BASELINE_PROMOTE_FINDINGS_BAD"
}

Write-Host "PIE_CROSS_REPO_BASELINE_PROMOTE_SELFTEST_OK" -ForegroundColor Green
