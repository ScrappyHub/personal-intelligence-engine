param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$IntentLog = Join-Path $RepoRoot "memory\intent\intent.ndjson"

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_intent_record_v1.ps1") `
  -RepoRoot $RepoRoot `
  -Goal "Finish persistent cognition intent layer" `
  -Status "open" `
  -SessionId "pie_intent_selftest" `
  -Repo $RepoRoot `
  -Notes "selftest seed" | Out-Host

if($LASTEXITCODE -ne 0){
  throw "PIE_INTENT_RECORD_CHILD_FAIL"
}

if(-not (Test-Path -LiteralPath $IntentLog -PathType Leaf)){
  throw "PIE_INTENT_LOG_MISSING"
}

$QueryJson = @(
  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File (Join-Path $RepoRoot "scripts\pie_intent_query_v1.ps1") `
    -RepoRoot $RepoRoot `
    -Status "open" `
    -GoalContains "persistent cognition"
) -join "`n"

if($LASTEXITCODE -ne 0){
  throw "PIE_INTENT_QUERY_CHILD_FAIL"
}

$Query = $QueryJson | ConvertFrom-Json

if($Query.count -lt 1){
  throw "PIE_INTENT_QUERY_EMPTY"
}

$Hit = $false
foreach($Item in @($Query.results)){
  if([string]$Item.status -eq "open" -and ([string]$Item.goal).IndexOf("persistent cognition",[System.StringComparison]::OrdinalIgnoreCase) -ge 0){
    $Hit = $true
  }
}

if(-not $Hit){
  throw "PIE_INTENT_QUERY_EXPECTED_ITEM_MISSING"
}

Write-Host "PIE_INTENT_SELFTEST_OK" -ForegroundColor Green
