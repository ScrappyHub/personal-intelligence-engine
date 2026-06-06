param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$SessionId = "pie_cross_repo_replay_aggregate_selftest"
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
  -Purpose "cross repo replay aggregate selftest relation" `
  -Evidence "selftest seed" | Out-Host

if($LASTEXITCODE -ne 0){
  throw "PIE_CROSS_REPO_REPLAY_AGG_EDGE_SEED_FAIL"
}

# Seed repo template.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_repo_template_record_v1.ps1") `
  -RepoRoot $RepoRoot `
  -TargetRepo $RepoRoot `
  -TemplateId "pie.cross.repo.replay.aggregate.selftest.v1" `
  -SequenceCsv "repo.status,repo.diff" `
  -Purpose "cross repo replay aggregate selftest template" `
  -Evidence "selftest seed" | Out-Host

if($LASTEXITCODE -ne 0){
  throw "PIE_CROSS_REPO_REPLAY_AGG_TEMPLATE_SEED_FAIL"
}

# Build plan.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_exec_plan_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -SourceRepo $RepoRoot `
  -Goal "Aggregate cross repo replay evidence" `
  -Relation "related_to" | Out-Host

if($LASTEXITCODE -ne 0){
  throw "PIE_CROSS_REPO_REPLAY_AGG_PLAN_FAIL"
}

$PlanPath = Join-Path $RunRoot "cross_repo_exec_plans\latest_cross_repo_exec_plan.json"

if(-not (Test-Path -LiteralPath $PlanPath -PathType Leaf)){
  throw "PIE_CROSS_REPO_REPLAY_AGG_PLAN_MISSING"
}

# Confirm execution.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_execute_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -PlanPath $PlanPath `
  -Confirm | Out-Host

if($LASTEXITCODE -ne 0){
  throw "PIE_CROSS_REPO_REPLAY_AGG_EXEC_FAIL"
}

# Aggregate replay.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_replay_aggregate_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId | Out-Host

if($LASTEXITCODE -ne 0){
  throw "PIE_CROSS_REPO_REPLAY_AGG_CHILD_FAIL"
}

$Latest = Join-Path $RunRoot "cross_repo_replay\latest_cross_repo_replay_aggregate.json"

if(-not (Test-Path -LiteralPath $Latest -PathType Leaf)){
  throw "PIE_CROSS_REPO_REPLAY_AGG_LATEST_MISSING"
}

$Obj = Get-Content -LiteralPath $Latest -Raw | ConvertFrom-Json

if($Obj.schema -ne "pie.cross.repo.replay.aggregate.v1"){
  throw "PIE_CROSS_REPO_REPLAY_AGG_SCHEMA_BAD"
}

if($Obj.status -ne "ok"){
  throw "PIE_CROSS_REPO_REPLAY_AGG_STATUS_BAD"
}

if([int]$Obj.child_count -lt 1){
  throw "PIE_CROSS_REPO_REPLAY_AGG_CHILD_COUNT_BAD"
}

$MissingHash = $false
foreach($C in @($Obj.children)){
  if([string]::IsNullOrWhiteSpace([string]$C.stdout_sha256)){
    $MissingHash = $true
  }
  if([string]::IsNullOrWhiteSpace([string]$C.snapshot_diff_sha256)){
    $MissingHash = $true
  }
}

if($MissingHash){
  throw "PIE_CROSS_REPO_REPLAY_AGG_HASH_MISSING"
}

Write-Host "PIE_CROSS_REPO_REPLAY_AGGREGATE_SELFTEST_OK" -ForegroundColor Green
