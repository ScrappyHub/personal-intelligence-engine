param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$SessionId = "pie_cross_repo_baseline_replace_selftest"
$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)
$OldBaselineId = "selftest.cross_repo.replace.old.v1"
$NewBaselineId = "selftest.cross_repo.replace.new.v1"

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
  -Purpose "cross repo baseline replace selftest relation" `
  -Evidence "baseline replace selftest seed" | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_BASELINE_REPLACE_EDGE_SEED_FAIL" }

# Seed template.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_repo_template_record_v1.ps1") `
  -RepoRoot $RepoRoot `
  -TargetRepo $RepoRoot `
  -TemplateId "pie.cross.repo.baseline.replace.selftest.v1" `
  -SequenceCsv "repo.status,repo.diff" `
  -Purpose "cross repo baseline replace selftest template" `
  -Evidence "baseline replace selftest seed" | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_BASELINE_REPLACE_TEMPLATE_SEED_FAIL" }

# Build plan.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_exec_plan_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -SourceRepo $RepoRoot `
  -Goal "Replace trusted cross repo baseline" `
  -Relation "related_to" | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_BASELINE_REPLACE_PLAN_FAIL" }

$PlanPath = Join-Path $RunRoot "cross_repo_exec_plans\latest_cross_repo_exec_plan.json"

if(-not (Test-Path -LiteralPath $PlanPath -PathType Leaf)){
  throw "PIE_BASELINE_REPLACE_PLAN_MISSING"
}

# Execute.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_execute_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -PlanPath $PlanPath `
  -Confirm | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_BASELINE_REPLACE_EXEC_FAIL" }

# Aggregate.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_replay_aggregate_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_BASELINE_REPLACE_AGG_FAIL" }

$Aggregate = Join-Path $RunRoot "cross_repo_replay\latest_cross_repo_replay_aggregate.json"

# Positive regression self-compare.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_regression_replay_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -BaselineAggregate $Aggregate `
  -CandidateAggregate $Aggregate | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_BASELINE_REPLACE_REGRESSION_FAIL" }

$Regression = Join-Path $RunRoot "cross_repo_regression\latest_cross_repo_regression_replay.json"

# Promote old baseline.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_baseline_promote_v1.ps1") `
  -RepoRoot $RepoRoot `
  -AggregatePath $Aggregate `
  -RegressionPath $Regression `
  -BaselineId $OldBaselineId `
  -Notes "baseline replace selftest old promotion" | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_BASELINE_REPLACE_OLD_PROMOTE_FAIL" }

# Prove replacement refuses when old baseline has not been revoked.
$FailedAsExpected = $false
try {
  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File (Join-Path $RepoRoot "scripts\pie_cross_repo_baseline_replace_v1.ps1") `
    -RepoRoot $RepoRoot `
    -OldBaselineId $OldBaselineId `
    -NewBaselineId $NewBaselineId `
    -AggregatePath $Aggregate `
    -RegressionPath $Regression `
    -RequireOldRevoked `
    -Notes "should fail before revoke" | Out-Host

  if($LASTEXITCODE -ne 0){
    $FailedAsExpected = $true
  }
}
catch {
  $FailedAsExpected = $true
}

if(-not $FailedAsExpected){
  throw "PIE_BASELINE_REPLACE_EXPECT_PRE_REVOKE_FAIL"
}

Write-Host "PIE_CROSS_REPO_BASELINE_REPLACE_PRE_REVOKE_DENY_OK" -ForegroundColor Green

# Revoke old baseline.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_baseline_revoke_v1.ps1") `
  -RepoRoot $RepoRoot `
  -BaselineId $OldBaselineId `
  -ReasonCode "SUPERSEDED_BY_SELFTEST" `
  -Notes "baseline replacement selftest revocation" | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_BASELINE_REPLACE_REVOKE_FAIL" }

# Replace with new baseline.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_baseline_replace_v1.ps1") `
  -RepoRoot $RepoRoot `
  -OldBaselineId $OldBaselineId `
  -NewBaselineId $NewBaselineId `
  -AggregatePath $Aggregate `
  -RegressionPath $Regression `
  -RequireOldRevoked `
  -Notes "selftest baseline replacement" | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_BASELINE_REPLACE_CHILD_FAIL" }

$Replacement = Join-Path $RepoRoot ("memory\baselines\cross_repo\" + $NewBaselineId + ".replacement.json")
$NewPromotion = Join-Path $RepoRoot ("memory\baselines\cross_repo\" + $NewBaselineId + ".promotion.json")
$NewAggregate = Join-Path $RepoRoot ("memory\baselines\cross_repo\" + $NewBaselineId + ".aggregate.json")

if(-not (Test-Path -LiteralPath $Replacement -PathType Leaf)){
  throw "PIE_BASELINE_REPLACE_RECORD_MISSING"
}

if(-not (Test-Path -LiteralPath $NewPromotion -PathType Leaf)){
  throw "PIE_BASELINE_REPLACE_NEW_PROMOTION_MISSING"
}

if(-not (Test-Path -LiteralPath $NewAggregate -PathType Leaf)){
  throw "PIE_BASELINE_REPLACE_NEW_AGGREGATE_MISSING"
}

$Obj = Get-Content -LiteralPath $Replacement -Raw | ConvertFrom-Json

if($Obj.schema -ne "pie.cross.repo.baseline.replacement.v1"){
  throw "PIE_BASELINE_REPLACE_SCHEMA_BAD"
}

if($Obj.old_baseline_id -ne $OldBaselineId){
  throw "PIE_BASELINE_REPLACE_OLD_ID_BAD_RESULT"
}

if($Obj.new_baseline_id -ne $NewBaselineId){
  throw "PIE_BASELINE_REPLACE_NEW_ID_BAD_RESULT"
}

if([bool]$Obj.old_revoked -ne $true){
  throw "PIE_BASELINE_REPLACE_EXPECT_OLD_REVOKED"
}

# Enforce old should block due revocation.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_baseline_enforce_v1.ps1") `
  -RepoRoot $RepoRoot `
  -BaselineId $OldBaselineId `
  -CandidateAggregate $Aggregate `
  -SessionId $SessionId | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_BASELINE_REPLACE_OLD_ENFORCE_FAIL" }

$LatestEnforce = Join-Path $RunRoot "cross_repo_baseline_enforcement\latest_baseline_enforcement.json"
$OldEnforce = Get-Content -LiteralPath $LatestEnforce -Raw | ConvertFrom-Json

if($OldEnforce.decision -ne "block"){
  throw "PIE_BASELINE_REPLACE_OLD_EXPECT_BLOCK"
}

if($OldEnforce.reason_code -ne "BASELINE_REVOKED"){
  throw "PIE_BASELINE_REPLACE_OLD_REASON_BAD"
}

# Enforce new should allow.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_baseline_enforce_v1.ps1") `
  -RepoRoot $RepoRoot `
  -BaselineId $NewBaselineId `
  -CandidateAggregate $Aggregate `
  -SessionId $SessionId | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_BASELINE_REPLACE_NEW_ENFORCE_FAIL" }

$NewEnforce = Get-Content -LiteralPath $LatestEnforce -Raw | ConvertFrom-Json

if($NewEnforce.decision -ne "allow"){
  throw "PIE_BASELINE_REPLACE_NEW_EXPECT_ALLOW"
}

Write-Host "PIE_CROSS_REPO_BASELINE_REPLACE_SELFTEST_OK" -ForegroundColor Green
