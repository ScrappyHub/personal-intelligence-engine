param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$SessionId = "pie_cross_repo_exec_plan_selftest"
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
  -Purpose "cross repo exec plan selftest relation" `
  -Evidence "selftest seed" | Out-Host

if($LASTEXITCODE -ne 0){
  throw "PIE_CROSS_REPO_EXEC_PLAN_RECORD_EDGE_FAIL"
}

# Seed repo template.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_repo_template_record_v1.ps1") `
  -RepoRoot $RepoRoot `
  -TargetRepo $RepoRoot `
  -TemplateId "pie.cross.repo.exec.plan.selftest.v1" `
  -SequenceCsv "repo.status,repo.diff" `
  -Purpose "cross repo exec plan selftest template" `
  -Evidence "selftest seed" | Out-Host

if($LASTEXITCODE -ne 0){
  throw "PIE_CROSS_REPO_EXEC_PLAN_TEMPLATE_SEED_FAIL"
}

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_exec_plan_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -SourceRepo $RepoRoot `
  -Goal "Build user-confirmable cross repo execution plan" `
  -Relation "related_to" | Out-Host

if($LASTEXITCODE -ne 0){
  throw "PIE_CROSS_REPO_EXEC_PLAN_CHILD_FAIL"
}

$Latest = Join-Path $RunRoot "cross_repo_exec_plans\latest_cross_repo_exec_plan.json"

if(-not (Test-Path -LiteralPath $Latest -PathType Leaf)){
  throw "PIE_CROSS_REPO_EXEC_PLAN_LATEST_MISSING"
}

$Obj = Get-Content -LiteralPath $Latest -Raw | ConvertFrom-Json

if($Obj.schema -ne "pie.cross.repo.exec.plan.v1"){
  throw "PIE_CROSS_REPO_EXEC_PLAN_SCHEMA_BAD"
}

if([int]$Obj.repo_plan_count -lt 1){
  throw "PIE_CROSS_REPO_EXEC_PLAN_COUNT_BAD"
}

if([bool]$Obj.execution_allowed -ne $false){
  throw "PIE_CROSS_REPO_EXEC_PLAN_EXECUTION_SHOULD_BE_FALSE"
}

$Hit = $false
foreach($P in @($Obj.repo_plans)){
  if(@($P.sequence) -contains "repo.status"){
    $Hit = $true
  }
}

if(-not $Hit){
  throw "PIE_CROSS_REPO_EXEC_PLAN_SEQUENCE_MISSING_STATUS"
}

Write-Host "PIE_CROSS_REPO_EXEC_PLAN_SELFTEST_OK" -ForegroundColor Green
