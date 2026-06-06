param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$SessionId = "pie_cross_repo_regression_negative_selftest"
$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)
$NegativeRoot = Join-Path $RunRoot "negative_vectors"
$Enc = New-Object System.Text.UTF8Encoding($false)

function Write-Utf8NoBomLf {
  param(
    [Parameter(Mandatory=$true)][string]$Path,
    [Parameter(Mandatory=$true)][AllowEmptyString()][string]$Text
  )

  $Dir = Split-Path -Parent $Path
  if(-not (Test-Path -LiteralPath $Dir -PathType Container)){
    New-Item -ItemType Directory -Force -Path $Dir | Out-Null
  }

  $Clean = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $Clean.EndsWith("`n")){ $Clean += "`n" }

  [System.IO.File]::WriteAllText($Path,$Clean,$Enc)
}

if(Test-Path -LiteralPath $RunRoot -PathType Container){
  Remove-Item -LiteralPath $RunRoot -Recurse -Force
}

New-Item -ItemType Directory -Force -Path $NegativeRoot | Out-Null

# Seed relation.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_graph_record_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SourceRepo $RepoRoot `
  -TargetRepo $RepoRoot `
  -Relation "related_to" `
  -Purpose "cross repo regression negative selftest relation" `
  -Evidence "negative selftest seed" | Out-Host

if($LASTEXITCODE -ne 0){
  throw "PIE_CROSS_REPO_REGRESSION_NEG_EDGE_SEED_FAIL"
}

# Seed template.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_repo_template_record_v1.ps1") `
  -RepoRoot $RepoRoot `
  -TargetRepo $RepoRoot `
  -TemplateId "pie.cross.repo.regression.negative.selftest.v1" `
  -SequenceCsv "repo.status,repo.diff" `
  -Purpose "cross repo regression negative selftest template" `
  -Evidence "negative selftest seed" | Out-Host

if($LASTEXITCODE -ne 0){
  throw "PIE_CROSS_REPO_REGRESSION_NEG_TEMPLATE_SEED_FAIL"
}

# Build plan.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_exec_plan_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -SourceRepo $RepoRoot `
  -Goal "Prove negative cross repo regression drift detection" `
  -Relation "related_to" | Out-Host

if($LASTEXITCODE -ne 0){
  throw "PIE_CROSS_REPO_REGRESSION_NEG_PLAN_FAIL"
}

$PlanPath = Join-Path $RunRoot "cross_repo_exec_plans\latest_cross_repo_exec_plan.json"

if(-not (Test-Path -LiteralPath $PlanPath -PathType Leaf)){
  throw "PIE_CROSS_REPO_REGRESSION_NEG_PLAN_MISSING"
}

# Confirm execution.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_execute_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -PlanPath $PlanPath `
  -Confirm | Out-Host

if($LASTEXITCODE -ne 0){
  throw "PIE_CROSS_REPO_REGRESSION_NEG_EXEC_FAIL"
}

# Aggregate baseline.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_replay_aggregate_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId | Out-Host

if($LASTEXITCODE -ne 0){
  throw "PIE_CROSS_REPO_REGRESSION_NEG_AGG_FAIL"
}

$Baseline = Join-Path $RunRoot "cross_repo_replay\latest_cross_repo_replay_aggregate.json"

if(-not (Test-Path -LiteralPath $Baseline -PathType Leaf)){
  throw "PIE_CROSS_REPO_REGRESSION_NEG_BASELINE_MISSING"
}

# Copy and mutate candidate aggregate.
$Candidate = Join-Path $NegativeRoot "candidate_mutated_stdout_hash.json"
$Obj = Get-Content -LiteralPath $Baseline -Raw | ConvertFrom-Json

if(@($Obj.children).Count -lt 1){
  throw "PIE_CROSS_REPO_REGRESSION_NEG_NO_CHILDREN"
}

$Obj.children[0].stdout_sha256 = "0000000000000000000000000000000000000000000000000000000000000000"

Write-Utf8NoBomLf -Path $Candidate -Text ($Obj | ConvertTo-Json -Depth 80)

# Compare baseline vs mutated candidate. This script should return success, but status must be drift.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_regression_replay_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -BaselineAggregate $Baseline `
  -CandidateAggregate $Candidate | Out-Host

if($LASTEXITCODE -ne 0){
  throw "PIE_CROSS_REPO_REGRESSION_NEG_COMPARE_FAIL"
}

$Latest = Join-Path $RunRoot "cross_repo_regression\latest_cross_repo_regression_replay.json"

if(-not (Test-Path -LiteralPath $Latest -PathType Leaf)){
  throw "PIE_CROSS_REPO_REGRESSION_NEG_LATEST_MISSING"
}

$Result = Get-Content -LiteralPath $Latest -Raw | ConvertFrom-Json

if($Result.schema -ne "pie.cross.repo.regression.replay.v1"){
  throw "PIE_CROSS_REPO_REGRESSION_NEG_SCHEMA_BAD"
}

if($Result.status -ne "drift"){
  throw "PIE_CROSS_REPO_REGRESSION_NEG_EXPECT_DRIFT"
}

if([int]$Result.finding_count -lt 1){
  throw "PIE_CROSS_REPO_REGRESSION_NEG_FINDINGS_MISSING"
}

$Found = $false
foreach($F in @($Result.findings)){
  if([string]$F.code -eq "stdout_hash_changed"){
    $Found = $true
  }
}

if(-not $Found){
  throw "PIE_CROSS_REPO_REGRESSION_NEG_STDOUT_DRIFT_NOT_FOUND"
}

Write-Host "PIE_CROSS_REPO_REGRESSION_NEGATIVE_SELFTEST_OK" -ForegroundColor Green
