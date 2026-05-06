param(
  [Parameter(Mandatory=$true)][string]$TargetRepo
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$TargetRepo = (Resolve-Path -LiteralPath $TargetRepo).Path
$PieRoot = Join-Path $TargetRepo ".pie"

$Required = @(
  ".pie",
  ".pie\profile.json",
  ".pie\memory",
  ".pie\memory\active.ndjson",
  ".pie\memory\project.ndjson",
  ".pie\rules",
  ".pie\receipts",
  ".pie\conversations"
)

foreach($rel in $Required){
  $p = Join-Path $TargetRepo $rel
  if(-not (Test-Path -LiteralPath $p)){
    throw ("PIE_INIT_VERIFY_MISSING: " + $rel)
  }
}

Write-Host ("PIE_INIT_VERIFY_OK: " + $PieRoot) -ForegroundColor Green