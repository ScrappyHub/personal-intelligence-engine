param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$SessionId = "pie_cross_repo_graph_selftest"
$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)

if(Test-Path -LiteralPath $RunRoot -PathType Container){
  Remove-Item -LiteralPath $RunRoot -Recurse -Force
}

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_graph_record_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SourceRepo $RepoRoot `
  -TargetRepo $RepoRoot `
  -Relation "related_to" `
  -Purpose "selftest cross repo route relation" `
  -Evidence "selftest seed" | Out-Host

if($LASTEXITCODE -ne 0){
  throw "PIE_CROSS_REPO_RECORD_CHILD_FAIL"
}

$QueryJson = @(
  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File (Join-Path $RepoRoot "scripts\pie_cross_repo_graph_query_v1.ps1") `
    -RepoRoot $RepoRoot `
    -SourceRepo $RepoRoot `
    -Relation "related_to"
) -join "`n"

if($LASTEXITCODE -ne 0){
  throw "PIE_CROSS_REPO_QUERY_CHILD_FAIL"
}

$Query = $QueryJson | ConvertFrom-Json

if($Query.count -lt 1){
  throw "PIE_CROSS_REPO_QUERY_EMPTY"
}

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_route_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -SourceRepo $RepoRoot `
  -Goal "Build safe cross-repo route" `
  -Relation "related_to" | Out-Host

if($LASTEXITCODE -ne 0){
  throw "PIE_CROSS_REPO_ROUTE_CHILD_FAIL"
}

$Latest = Join-Path $RunRoot "cross_repo_routes\latest_cross_repo_route.json"

if(-not (Test-Path -LiteralPath $Latest -PathType Leaf)){
  throw "PIE_CROSS_REPO_ROUTE_LATEST_MISSING"
}

$Obj = Get-Content -LiteralPath $Latest -Raw | ConvertFrom-Json

if($Obj.schema -ne "pie.cross.repo.route.v1"){
  throw "PIE_CROSS_REPO_ROUTE_SCHEMA_BAD"
}

if([int]$Obj.edge_count -lt 1){
  throw "PIE_CROSS_REPO_ROUTE_EDGE_COUNT_BAD"
}

if([bool]$Obj.execution_allowed -ne $false){
  throw "PIE_CROSS_REPO_ROUTE_EXECUTION_SHOULD_BE_FALSE"
}

Write-Host "PIE_CROSS_REPO_GRAPH_SELFTEST_OK" -ForegroundColor Green
