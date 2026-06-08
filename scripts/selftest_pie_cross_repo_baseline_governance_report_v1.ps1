param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$SessionId = "pie_cross_repo_baseline_governance_report_selftest"
$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)
$OldBaselineId = "selftest.cross_repo.report.old.v1"
$NewBaselineId = "selftest.cross_repo.report.new.v1"

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
  -Purpose "cross repo baseline governance report selftest relation" `
  -Evidence "baseline governance report selftest seed" | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_BASELINE_REPORT_EDGE_SEED_FAIL" }

# Seed template.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_repo_template_record_v1.ps1") `
  -RepoRoot $RepoRoot `
  -TargetRepo $RepoRoot `
  -TemplateId "pie.cross.repo.baseline.governance.report.selftest.v1" `
  -SequenceCsv "repo.status,repo.diff" `
  -Purpose "cross repo baseline governance report selftest template" `
  -Evidence "baseline governance report selftest seed" | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_BASELINE_REPORT_TEMPLATE_SEED_FAIL" }

# Build plan.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_exec_plan_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -SourceRepo $RepoRoot `
  -Goal "Generate readable baseline governance report" `
  -Relation "related_to" | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_BASELINE_REPORT_PLAN_FAIL" }

$PlanPath = Join-Path $RunRoot "cross_repo_exec_plans\latest_cross_repo_exec_plan.json"

if(-not (Test-Path -LiteralPath $PlanPath -PathType Leaf)){
  throw "PIE_BASELINE_REPORT_PLAN_MISSING"
}

# Execute.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_execute_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -PlanPath $PlanPath `
  -Confirm | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_BASELINE_REPORT_EXEC_FAIL" }

# Aggregate.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_replay_aggregate_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_BASELINE_REPORT_AGG_FAIL" }

$Aggregate = Join-Path $RunRoot "cross_repo_replay\latest_cross_repo_replay_aggregate.json"

# Positive regression.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_regression_replay_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -BaselineAggregate $Aggregate `
  -CandidateAggregate $Aggregate | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_BASELINE_REPORT_REGRESSION_FAIL" }

$Regression = Join-Path $RunRoot "cross_repo_regression\latest_cross_repo_regression_replay.json"

# Promote old baseline.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_baseline_promote_v1.ps1") `
  -RepoRoot $RepoRoot `
  -AggregatePath $Aggregate `
  -RegressionPath $Regression `
  -BaselineId $OldBaselineId `
  -Notes "governance report old baseline" | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_BASELINE_REPORT_OLD_PROMOTE_FAIL" }

# Revoke old baseline.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_baseline_revoke_v1.ps1") `
  -RepoRoot $RepoRoot `
  -BaselineId $OldBaselineId `
  -ReasonCode "SUPERSEDED_BY_GOVERNANCE_REPORT" `
  -Notes "governance report selftest revocation" | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_BASELINE_REPORT_REVOKE_FAIL" }

# Replace with new baseline.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_baseline_replace_v1.ps1") `
  -RepoRoot $RepoRoot `
  -OldBaselineId $OldBaselineId `
  -NewBaselineId $NewBaselineId `
  -AggregatePath $Aggregate `
  -RegressionPath $Regression `
  -RequireOldRevoked `
  -Notes "governance report selftest replacement" | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_BASELINE_REPORT_REPLACE_FAIL" }

# Audit lineage.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_baseline_lineage_audit_v1.ps1") `
  -RepoRoot $RepoRoot `
  -RootBaselineId $OldBaselineId `
  -SessionId $SessionId | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_BASELINE_REPORT_AUDIT_FAIL" }

$AuditPath = Join-Path $RunRoot "cross_repo_baseline_lineage_audit\latest_baseline_lineage_audit.json"

if(-not (Test-Path -LiteralPath $AuditPath -PathType Leaf)){
  throw "PIE_BASELINE_REPORT_AUDIT_MISSING"
}

# Generate readable report.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_baseline_governance_report_v1.ps1") `
  -RepoRoot $RepoRoot `
  -AuditPath $AuditPath `
  -SessionId $SessionId | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_BASELINE_REPORT_CHILD_FAIL" }

$LatestMd = Join-Path $RunRoot "cross_repo_baseline_governance_report\latest_baseline_governance_report.md"
$LatestTxt = Join-Path $RunRoot "cross_repo_baseline_governance_report\latest_baseline_governance_report.txt"
$Manifest = Join-Path $RunRoot "cross_repo_baseline_governance_report\latest_baseline_governance_report.manifest.json"

if(-not (Test-Path -LiteralPath $LatestMd -PathType Leaf)){
  throw "PIE_BASELINE_REPORT_MD_MISSING"
}

if(-not (Test-Path -LiteralPath $LatestTxt -PathType Leaf)){
  throw "PIE_BASELINE_REPORT_TXT_MISSING"
}

if(-not (Test-Path -LiteralPath $Manifest -PathType Leaf)){
  throw "PIE_BASELINE_REPORT_MANIFEST_MISSING"
}

$Md = Get-Content -LiteralPath $LatestMd -Raw
$Man = Get-Content -LiteralPath $Manifest -Raw | ConvertFrom-Json

if($Man.schema -ne "pie.cross.repo.baseline.governance.report.v1"){
  throw "PIE_BASELINE_REPORT_MANIFEST_SCHEMA_BAD"
}

if($Man.audit_status -ne "ok"){
  throw "PIE_BASELINE_REPORT_AUDIT_STATUS_BAD"
}

if($Md -notlike "*PIE Cross-Repo Baseline Governance Report*"){
  throw "PIE_BASELINE_REPORT_TITLE_MISSING"
}

if($Md -notlike ("*" + $OldBaselineId + "*")){
  throw "PIE_BASELINE_REPORT_OLD_ID_MISSING"
}

if($Md -notlike ("*" + $NewBaselineId + "*")){
  throw "PIE_BASELINE_REPORT_NEW_ID_MISSING"
}

if($Md -notlike "*Audit status: ok*"){
  throw "PIE_BASELINE_REPORT_STATUS_MISSING"
}

if($Md -notlike "*No lineage problems were detected.*"){
  throw "PIE_BASELINE_REPORT_PROBLEMS_LINE_MISSING"
}

Write-Host "PIE_CROSS_REPO_BASELINE_GOVERNANCE_REPORT_SELFTEST_OK" -ForegroundColor Green
