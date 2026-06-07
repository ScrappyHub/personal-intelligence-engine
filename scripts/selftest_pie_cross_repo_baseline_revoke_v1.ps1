param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$SessionId = "pie_cross_repo_baseline_revoke_selftest"
$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)
$BaselineId = "selftest.cross_repo.revoke.baseline.v1"

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
  -Purpose "cross repo baseline revoke selftest relation" `
  -Evidence "baseline revoke selftest seed" | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_BASELINE_REVOKE_EDGE_SEED_FAIL" }

# Seed template.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_repo_template_record_v1.ps1") `
  -RepoRoot $RepoRoot `
  -TargetRepo $RepoRoot `
  -TemplateId "pie.cross.repo.baseline.revoke.selftest.v1" `
  -SequenceCsv "repo.status,repo.diff" `
  -Purpose "cross repo baseline revoke selftest template" `
  -Evidence "baseline revoke selftest seed" | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_BASELINE_REVOKE_TEMPLATE_SEED_FAIL" }

# Build plan.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_exec_plan_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -SourceRepo $RepoRoot `
  -Goal "Revoke trusted cross repo baseline" `
  -Relation "related_to" | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_BASELINE_REVOKE_PLAN_FAIL" }

$PlanPath = Join-Path $RunRoot "cross_repo_exec_plans\latest_cross_repo_exec_plan.json"

if(-not (Test-Path -LiteralPath $PlanPath -PathType Leaf)){
  throw "PIE_BASELINE_REVOKE_PLAN_MISSING"
}

# Execute.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_execute_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -PlanPath $PlanPath `
  -Confirm | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_BASELINE_REVOKE_EXEC_FAIL" }

# Aggregate.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_replay_aggregate_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_BASELINE_REVOKE_AGG_FAIL" }

$Aggregate = Join-Path $RunRoot "cross_repo_replay\latest_cross_repo_replay_aggregate.json"

# Positive regression self-compare.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_regression_replay_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -BaselineAggregate $Aggregate `
  -CandidateAggregate $Aggregate | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_BASELINE_REVOKE_REGRESSION_FAIL" }

$Regression = Join-Path $RunRoot "cross_repo_regression\latest_cross_repo_regression_replay.json"

# Promote baseline.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_baseline_promote_v1.ps1") `
  -RepoRoot $RepoRoot `
  -AggregatePath $Aggregate `
  -RegressionPath $Regression `
  -BaselineId $BaselineId `
  -Notes "baseline revoke selftest promotion" | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_BASELINE_REVOKE_PROMOTE_FAIL" }

# Enforce before revoke: must allow.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_baseline_enforce_v1.ps1") `
  -RepoRoot $RepoRoot `
  -BaselineId $BaselineId `
  -CandidateAggregate $Aggregate `
  -SessionId $SessionId | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_BASELINE_REVOKE_PRE_ENFORCE_FAIL" }

$LatestEnforce = Join-Path $RunRoot "cross_repo_baseline_enforcement\latest_baseline_enforcement.json"
$Pre = Get-Content -LiteralPath $LatestEnforce -Raw | ConvertFrom-Json

if($Pre.decision -ne "allow"){
  throw "PIE_BASELINE_REVOKE_PRE_EXPECT_ALLOW"
}

# Revoke baseline.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_baseline_revoke_v1.ps1") `
  -RepoRoot $RepoRoot `
  -BaselineId $BaselineId `
  -ReasonCode "SELFTEST_REVOKED" `
  -Notes "selftest revocation" | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_BASELINE_REVOKE_CHILD_FAIL" }

$Revocation = Join-Path $RepoRoot ("memory\baselines\cross_repo\" + $BaselineId + ".revocation.json")

if(-not (Test-Path -LiteralPath $Revocation -PathType Leaf)){
  throw "PIE_BASELINE_REVOKE_RECORD_MISSING"
}

# Enforce after revoke: must block even same aggregate.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_baseline_enforce_v1.ps1") `
  -RepoRoot $RepoRoot `
  -BaselineId $BaselineId `
  -CandidateAggregate $Aggregate `
  -SessionId $SessionId | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_BASELINE_REVOKE_POST_ENFORCE_FAIL" }

$Post = Get-Content -LiteralPath $LatestEnforce -Raw | ConvertFrom-Json

if($Post.decision -ne "block"){
  throw "PIE_BASELINE_REVOKE_POST_EXPECT_BLOCK"
}

if($Post.reason_code -ne "BASELINE_REVOKED"){
  throw "PIE_BASELINE_REVOKE_POST_REASON_BAD"
}

Write-Host "PIE_CROSS_REPO_BASELINE_REVOKE_SELFTEST_OK" -ForegroundColor Green
