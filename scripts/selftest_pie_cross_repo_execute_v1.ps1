param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$SessionId = "pie_cross_repo_execute_selftest"
$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)

if(Test-Path -LiteralPath $RunRoot -PathType Container){
  Remove-Item -LiteralPath $RunRoot -Recurse -Force
}

# Seed edge.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_graph_record_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SourceRepo $RepoRoot `
  -TargetRepo $RepoRoot `
  -Relation "related_to" `
  -Purpose "cross repo confirmed execution selftest relation" `
  -Evidence "selftest seed" | Out-Host

if($LASTEXITCODE -ne 0){
  throw "PIE_CROSS_REPO_EXECUTE_EDGE_SEED_FAIL"
}

# Seed repo template with low-risk read-only capabilities.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_repo_template_record_v1.ps1") `
  -RepoRoot $RepoRoot `
  -TargetRepo $RepoRoot `
  -TemplateId "pie.cross.repo.execute.selftest.v1" `
  -SequenceCsv "repo.status,repo.diff" `
  -Purpose "cross repo confirmed execution selftest template" `
  -Evidence "selftest seed" | Out-Host

if($LASTEXITCODE -ne 0){
  throw "PIE_CROSS_REPO_EXECUTE_TEMPLATE_SEED_FAIL"
}

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_exec_plan_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -SourceRepo $RepoRoot `
  -Goal "Confirm cross repo execution safely" `
  -Relation "related_to" | Out-Host

if($LASTEXITCODE -ne 0){
  throw "PIE_CROSS_REPO_EXECUTE_PLAN_FAIL"
}

$PlanPath = Join-Path $RunRoot "cross_repo_exec_plans\latest_cross_repo_exec_plan.json"

if(-not (Test-Path -LiteralPath $PlanPath -PathType Leaf)){
  throw "PIE_CROSS_REPO_EXECUTE_PLAN_MISSING"
}

# First prove no silent execution.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_execute_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -PlanPath $PlanPath | Out-Host

if($LASTEXITCODE -ne 0){
  throw "PIE_CROSS_REPO_EXECUTE_PROPOSAL_FAIL"
}

$SummaryPath = Join-Path $RunRoot "cross_repo_execution\latest_cross_repo_execution_summary.json"

if(Test-Path -LiteralPath $SummaryPath -PathType Leaf){
  throw "PIE_CROSS_REPO_EXECUTE_SILENT_EXECUTION_BAD"
}

# Now explicitly confirm execution.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_execute_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -PlanPath $PlanPath `
  -Confirm | Out-Host

if($LASTEXITCODE -ne 0){
  throw "PIE_CROSS_REPO_EXECUTE_CONFIRM_FAIL"
}

if(-not (Test-Path -LiteralPath $SummaryPath -PathType Leaf)){
  throw "PIE_CROSS_REPO_EXECUTE_SUMMARY_MISSING"
}

$Summary = Get-Content -LiteralPath $SummaryPath -Raw | ConvertFrom-Json

if($Summary.schema -ne "pie.cross.repo.execution.summary.v1"){
  throw "PIE_CROSS_REPO_EXECUTE_SUMMARY_SCHEMA_BAD"
}

if([int]$Summary.step_count -lt 1){
  throw "PIE_CROSS_REPO_EXECUTE_STEP_COUNT_BAD"
}

$ReceiptPath = Join-Path $RunRoot "cross_repo_execution\cross_repo_execution_receipts.ndjson"

if(-not (Test-Path -LiteralPath $ReceiptPath -PathType Leaf)){
  throw "PIE_CROSS_REPO_EXECUTE_RECEIPTS_MISSING"
}

Write-Host "PIE_CROSS_REPO_EXECUTE_SELFTEST_OK" -ForegroundColor Green
