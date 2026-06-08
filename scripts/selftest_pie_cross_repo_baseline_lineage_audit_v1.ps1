param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$SessionId = "pie_cross_repo_baseline_lineage_audit_selftest"
$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)
$OldBaselineId = "selftest.cross_repo.lineage.old.v1"
$NewBaselineId = "selftest.cross_repo.lineage.new.v1"

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
  -Purpose "cross repo baseline lineage audit selftest relation" `
  -Evidence "baseline lineage audit selftest seed" | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_BASELINE_LINEAGE_EDGE_SEED_FAIL" }

# Seed template.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_repo_template_record_v1.ps1") `
  -RepoRoot $RepoRoot `
  -TargetRepo $RepoRoot `
  -TemplateId "pie.cross.repo.baseline.lineage.audit.selftest.v1" `
  -SequenceCsv "repo.status,repo.diff" `
  -Purpose "cross repo baseline lineage audit selftest template" `
  -Evidence "baseline lineage audit selftest seed" | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_BASELINE_LINEAGE_TEMPLATE_SEED_FAIL" }

# Build plan.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_exec_plan_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -SourceRepo $RepoRoot `
  -Goal "Audit trusted cross repo baseline lineage" `
  -Relation "related_to" | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_BASELINE_LINEAGE_PLAN_FAIL" }

$PlanPath = Join-Path $RunRoot "cross_repo_exec_plans\latest_cross_repo_exec_plan.json"

if(-not (Test-Path -LiteralPath $PlanPath -PathType Leaf)){
  throw "PIE_BASELINE_LINEAGE_PLAN_MISSING"
}

# Execute.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_execute_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -PlanPath $PlanPath `
  -Confirm | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_BASELINE_LINEAGE_EXEC_FAIL" }

# Aggregate.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_replay_aggregate_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_BASELINE_LINEAGE_AGG_FAIL" }

$Aggregate = Join-Path $RunRoot "cross_repo_replay\latest_cross_repo_replay_aggregate.json"

# Positive regression.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_regression_replay_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -BaselineAggregate $Aggregate `
  -CandidateAggregate $Aggregate | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_BASELINE_LINEAGE_REGRESSION_FAIL" }

$Regression = Join-Path $RunRoot "cross_repo_regression\latest_cross_repo_regression_replay.json"

# Promote old baseline.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_baseline_promote_v1.ps1") `
  -RepoRoot $RepoRoot `
  -AggregatePath $Aggregate `
  -RegressionPath $Regression `
  -BaselineId $OldBaselineId `
  -Notes "lineage audit old baseline" | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_BASELINE_LINEAGE_OLD_PROMOTE_FAIL" }

# Revoke old baseline.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_baseline_revoke_v1.ps1") `
  -RepoRoot $RepoRoot `
  -BaselineId $OldBaselineId `
  -ReasonCode "SUPERSEDED_BY_LINEAGE_AUDIT" `
  -Notes "lineage audit selftest revocation" | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_BASELINE_LINEAGE_REVOKE_FAIL" }

# Replace with new baseline.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_baseline_replace_v1.ps1") `
  -RepoRoot $RepoRoot `
  -OldBaselineId $OldBaselineId `
  -NewBaselineId $NewBaselineId `
  -AggregatePath $Aggregate `
  -RegressionPath $Regression `
  -RequireOldRevoked `
  -Notes "lineage audit selftest replacement" | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_BASELINE_LINEAGE_REPLACE_FAIL" }

# Audit from old baseline id.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_baseline_lineage_audit_v1.ps1") `
  -RepoRoot $RepoRoot `
  -RootBaselineId $OldBaselineId `
  -SessionId $SessionId | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_BASELINE_LINEAGE_AUDIT_CHILD_FAIL" }

$Latest = Join-Path $RunRoot "cross_repo_baseline_lineage_audit\latest_baseline_lineage_audit.json"

if(-not (Test-Path -LiteralPath $Latest -PathType Leaf)){
  throw "PIE_BASELINE_LINEAGE_AUDIT_LATEST_MISSING"
}

$Obj = Get-Content -LiteralPath $Latest -Raw | ConvertFrom-Json

if($Obj.schema -ne "pie.cross.repo.baseline.lineage.audit.v1"){
  throw "PIE_BASELINE_LINEAGE_AUDIT_SCHEMA_BAD"
}

if($Obj.status -ne "ok"){
  throw "PIE_BASELINE_LINEAGE_AUDIT_STATUS_BAD"
}

if([int]$Obj.baseline_count -lt 2){
  throw "PIE_BASELINE_LINEAGE_AUDIT_BASELINE_COUNT_BAD"
}

if([int]$Obj.edge_count -lt 1){
  throw "PIE_BASELINE_LINEAGE_AUDIT_EDGE_COUNT_BAD"
}

$SawOld = $false
$SawNew = $false
$SawRevoked = $false

foreach($B in @($Obj.baselines)){
  if([string]$B.baseline_id -eq $OldBaselineId){
    $SawOld = $true
    if([string]$B.status -eq "revoked"){
      $SawRevoked = $true
    }
  }
  if([string]$B.baseline_id -eq $NewBaselineId){
    $SawNew = $true
  }
}

if(-not $SawOld){ throw "PIE_BASELINE_LINEAGE_AUDIT_OLD_MISSING" }
if(-not $SawNew){ throw "PIE_BASELINE_LINEAGE_AUDIT_NEW_MISSING" }
if(-not $SawRevoked){ throw "PIE_BASELINE_LINEAGE_AUDIT_OLD_NOT_REVOKED" }

Write-Host "PIE_CROSS_REPO_BASELINE_LINEAGE_AUDIT_SELFTEST_OK" -ForegroundColor Green
