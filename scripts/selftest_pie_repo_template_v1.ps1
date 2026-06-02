param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$SessionId = "pie_repo_template_selftest"
$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)

if(Test-Path -LiteralPath $RunRoot -PathType Container){
  Remove-Item -LiteralPath $RunRoot -Recurse -Force
}

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_repo_template_record_v1.ps1") `
  -RepoRoot $RepoRoot `
  -TargetRepo $RepoRoot `
  -TemplateId "pie.repo.health.v1" `
  -SequenceCsv "repo.status,repo.diff" `
  -Purpose "repo health for PIE itself" `
  -Evidence "repo template selftest seed" | Out-Host

if($LASTEXITCODE -ne 0){
  throw "PIE_REPO_TEMPLATE_RECORD_CHILD_FAIL"
}

$QueryJson = @(
  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File (Join-Path $RepoRoot "scripts\pie_repo_template_query_v1.ps1") `
    -RepoRoot $RepoRoot `
    -TargetRepo $RepoRoot `
    -TemplateId "pie.repo.health.v1"
) -join "`n"

if($LASTEXITCODE -ne 0){
  throw "PIE_REPO_TEMPLATE_QUERY_CHILD_FAIL"
}

$Query = $QueryJson | ConvertFrom-Json

if($Query.count -lt 1){
  throw "PIE_REPO_TEMPLATE_QUERY_EMPTY"
}

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_repo_plan_template_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -TargetRepo $RepoRoot `
  -Goal "Use PIE-specific repo health template" `
  -PurposeContains "repo health" | Out-Host

if($LASTEXITCODE -ne 0){
  throw "PIE_REPO_TEMPLATE_PLAN_CHILD_FAIL"
}

$Latest = Join-Path $RunRoot "repo_template_plans\latest_repo_template_plan.json"

if(-not (Test-Path -LiteralPath $Latest -PathType Leaf)){
  throw "PIE_REPO_TEMPLATE_PLAN_MISSING"
}

$Plan = Get-Content -LiteralPath $Latest -Raw | ConvertFrom-Json

if($Plan.selected_template_id -ne "pie.repo.health.v1"){
  throw "PIE_REPO_TEMPLATE_SELECTED_BAD"
}

if(-not (@($Plan.sequence) -contains "repo.status")){
  throw "PIE_REPO_TEMPLATE_SEQUENCE_MISSING_STATUS"
}

if(-not (@($Plan.sequence) -contains "repo.diff")){
  throw "PIE_REPO_TEMPLATE_SEQUENCE_MISSING_DIFF"
}

Write-Host "PIE_REPO_TEMPLATE_SELFTEST_OK" -ForegroundColor Green
