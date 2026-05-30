param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$SessionId = "pie_orchestrate_selftest"
$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)
$Enc = New-Object System.Text.UTF8Encoding($false)

function Write-Utf8NoBomLf {
  param([string]$Path,[string]$Text)

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

New-Item -ItemType Directory -Force -Path $RunRoot | Out-Null
Write-Utf8NoBomLf -Path (Join-Path $RunRoot "project_repo.txt") -Text $RepoRoot

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_orchestrate_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -ChainId "repo.health.basic" `
  -AutoConfirmAllowed | Out-Host

if($LASTEXITCODE -ne 0){
  throw "PIE_ORCH_SELFTEST_CHILD_FAIL"
}

$Plans = @(Get-ChildItem -LiteralPath (Join-Path $RunRoot "orchestration") -File -Filter "orchestration_plan_*.json" -ErrorAction SilentlyContinue)
if(@($Plans).Count -lt 1){
  throw "PIE_ORCH_SELFTEST_PLAN_MISSING"
}

$Receipt = Join-Path $RunRoot "execution\execution_receipts.ndjson"
if(-not (Test-Path -LiteralPath $Receipt -PathType Leaf)){
  throw "PIE_ORCH_SELFTEST_RECEIPT_MISSING"
}

$ReceiptText = Get-Content -LiteralPath $Receipt -Raw
if($ReceiptText -notmatch "git status"){
  throw "PIE_ORCH_SELFTEST_STATUS_RECEIPT_MISSING"
}
if($ReceiptText -notmatch "git diff"){
  throw "PIE_ORCH_SELFTEST_DIFF_RECEIPT_MISSING"
}

Write-Host "PIE_ORCH_SELFTEST_OK" -ForegroundColor Green
