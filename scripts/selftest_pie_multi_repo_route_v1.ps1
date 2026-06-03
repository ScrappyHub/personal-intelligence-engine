param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$SessionId = "pie_multi_repo_route_selftest"
$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)

if(Test-Path -LiteralPath $RunRoot -PathType Container){
  Remove-Item -LiteralPath $RunRoot -Recurse -Force
}

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_repo_template_record_v1.ps1") `
  -RepoRoot $RepoRoot `
  -TargetRepo $RepoRoot `
  -TemplateId "pie.multi.repo.route.selftest.v1" `
  -SequenceCsv "repo.status,repo.diff" `
  -Purpose "multi repo routing selftest" `
  -Evidence "multi repo route selftest seed" | Out-Host

if($LASTEXITCODE -ne 0){
  throw "PIE_MULTI_REPO_ROUTE_TEMPLATE_RECORD_FAIL"
}

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_multi_repo_route_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -TargetRepo $RepoRoot `
  -Goal "Route repo-specific cognition for PIE" `
  -PurposeContains "multi repo routing" | Out-Host

if($LASTEXITCODE -ne 0){
  throw "PIE_MULTI_REPO_ROUTE_CHILD_FAIL"
}

$Latest = Join-Path $RunRoot "multi_repo_routes\latest_multi_repo_route.json"

if(-not (Test-Path -LiteralPath $Latest -PathType Leaf)){
  throw "PIE_MULTI_REPO_ROUTE_LATEST_MISSING"
}

$Obj = Get-Content -LiteralPath $Latest -Raw | ConvertFrom-Json

if($Obj.schema -ne "pie.multi.repo.route.v1"){
  throw "PIE_MULTI_REPO_ROUTE_SCHEMA_BAD"
}

if($Obj.selected_mode -ne "repo_template"){
  throw "PIE_MULTI_REPO_ROUTE_EXPECT_TEMPLATE"
}

if($Obj.selected_template_id -ne "pie.multi.repo.route.selftest.v1"){
  throw "PIE_MULTI_REPO_ROUTE_TEMPLATE_BAD"
}

if([bool]$Obj.execution_allowed -ne $false){
  throw "PIE_MULTI_REPO_ROUTE_EXECUTION_SHOULD_BE_FALSE"
}

if(-not (@($Obj.sequence) -contains "repo.status")){
  throw "PIE_MULTI_REPO_ROUTE_SEQUENCE_MISSING_STATUS"
}

Write-Host "PIE_MULTI_REPO_ROUTE_SELFTEST_OK" -ForegroundColor Green
