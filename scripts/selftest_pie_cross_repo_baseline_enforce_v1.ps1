param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$SessionId = "pie_cross_repo_baseline_enforce_selftest"
$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)
$NegativeRoot = Join-Path $RunRoot "negative_vectors"
$BaselineId = "selftest.cross_repo.enforce.baseline.v1"
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
  -Purpose "cross repo baseline enforce selftest relation" `
  -Evidence "baseline enforce selftest seed" | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_BASELINE_ENFORCE_EDGE_SEED_FAIL" }

# Seed template.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_repo_template_record_v1.ps1") `
  -RepoRoot $RepoRoot `
  -TargetRepo $RepoRoot `
  -TemplateId "pie.cross.repo.baseline.enforce.selftest.v1" `
  -SequenceCsv "repo.status,repo.diff" `
  -Purpose "cross repo baseline enforce selftest template" `
  -Evidence "baseline enforce selftest seed" | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_BASELINE_ENFORCE_TEMPLATE_SEED_FAIL" }

# Build plan.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_exec_plan_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -SourceRepo $RepoRoot `
  -Goal "Enforce trusted cross repo baseline" `
  -Relation "related_to" | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_BASELINE_ENFORCE_PLAN_FAIL" }

$PlanPath = Join-Path $RunRoot "cross_repo_exec_plans\latest_cross_repo_exec_plan.json"

if(-not (Test-Path -LiteralPath $PlanPath -PathType Leaf)){
  throw "PIE_BASELINE_ENFORCE_PLAN_MISSING"
}

# Execute.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_execute_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -PlanPath $PlanPath `
  -Confirm | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_BASELINE_ENFORCE_EXEC_FAIL" }

# Aggregate.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_replay_aggregate_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_BASELINE_ENFORCE_AGG_FAIL" }

$Aggregate = Join-Path $RunRoot "cross_repo_replay\latest_cross_repo_replay_aggregate.json"

if(-not (Test-Path -LiteralPath $Aggregate -PathType Leaf)){
  throw "PIE_BASELINE_ENFORCE_AGG_MISSING"
}

# Positive regression self-compare.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_regression_replay_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -BaselineAggregate $Aggregate `
  -CandidateAggregate $Aggregate | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_BASELINE_ENFORCE_POS_REG_FAIL" }

$Regression = Join-Path $RunRoot "cross_repo_regression\latest_cross_repo_regression_replay.json"

# Promote verified baseline.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_baseline_promote_v1.ps1") `
  -RepoRoot $RepoRoot `
  -AggregatePath $Aggregate `
  -RegressionPath $Regression `
  -BaselineId $BaselineId `
  -Notes "baseline enforce selftest promotion" | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_BASELINE_ENFORCE_PROMOTE_FAIL" }

# Enforcement positive: same aggregate should allow.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_baseline_enforce_v1.ps1") `
  -RepoRoot $RepoRoot `
  -BaselineId $BaselineId `
  -CandidateAggregate $Aggregate `
  -SessionId $SessionId | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_BASELINE_ENFORCE_ALLOW_CHILD_FAIL" }

$LatestEnforce = Join-Path $RunRoot "cross_repo_baseline_enforcement\latest_baseline_enforcement.json"

if(-not (Test-Path -LiteralPath $LatestEnforce -PathType Leaf)){
  throw "PIE_BASELINE_ENFORCE_ALLOW_MISSING"
}

$Allow = Get-Content -LiteralPath $LatestEnforce -Raw | ConvertFrom-Json

if($Allow.decision -ne "allow"){
  throw "PIE_BASELINE_ENFORCE_EXPECT_ALLOW"
}

# Enforcement negative: mutate candidate and require block.
$Candidate = Join-Path $NegativeRoot "candidate_mutated_stdout_hash.json"
$Obj = Get-Content -LiteralPath $Aggregate -Raw | ConvertFrom-Json

if(@($Obj.children).Count -lt 1){
  throw "PIE_BASELINE_ENFORCE_NO_CHILDREN"
}

$Obj.children[0].stdout_sha256 = "1111111111111111111111111111111111111111111111111111111111111111"
Write-Utf8NoBomLf -Path $Candidate -Text ($Obj | ConvertTo-Json -Depth 80)

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_baseline_enforce_v1.ps1") `
  -RepoRoot $RepoRoot `
  -BaselineId $BaselineId `
  -CandidateAggregate $Candidate `
  -SessionId $SessionId | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_BASELINE_ENFORCE_BLOCK_CHILD_FAIL" }

$Block = Get-Content -LiteralPath $LatestEnforce -Raw | ConvertFrom-Json

if($Block.decision -ne "block"){
  throw "PIE_BASELINE_ENFORCE_EXPECT_BLOCK"
}

if($Block.regression_status -ne "drift"){
  throw "PIE_BASELINE_ENFORCE_EXPECT_DRIFT"
}

Write-Host "PIE_CROSS_REPO_BASELINE_ENFORCE_SELFTEST_OK" -ForegroundColor Green
