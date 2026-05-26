param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$SessionId = "pie_exec_selftest"
$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)
$Enc = New-Object System.Text.UTF8Encoding($false)

function Write-Utf8NoBomLf {
  param([string]$Path,[string]$Text)
  $Dir = Split-Path -Parent $Path
  if(-not (Test-Path -LiteralPath $Dir -PathType Container)){ New-Item -ItemType Directory -Force -Path $Dir | Out-Null }
  $Clean = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $Clean.EndsWith("`n")){ $Clean += "`n" }
  [System.IO.File]::WriteAllText($Path,$Clean,$Enc)
}

New-Item -ItemType Directory -Force -Path $RunRoot | Out-Null
Write-Utf8NoBomLf -Path (Join-Path $RunRoot "project_repo.txt") -Text $RepoRoot

$Exec = Join-Path $RepoRoot "scripts\pie_exec_v1.ps1"

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File $Exec `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -Command "Write-Output PIE_EXEC_VECTOR_OK" | Out-Host

if($LASTEXITCODE -ne 0){
  throw "PIE_EXEC_PROPOSAL_VECTOR_FAIL"
}

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File $Exec `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -Command "Write-Output PIE_EXEC_VECTOR_OK" `
  -Confirm | Out-Host

if($LASTEXITCODE -ne 0){
  throw "PIE_EXEC_CONFIRM_VECTOR_FAIL"
}

$Receipt = Join-Path $RunRoot "execution\execution_receipts.ndjson"

if(-not (Test-Path -LiteralPath $Receipt -PathType Leaf)){
  throw "PIE_EXEC_RECEIPT_MISSING"
}

$ReceiptText = Get-Content -LiteralPath $Receipt -Raw

if($ReceiptText -notmatch "PIE_EXEC_VECTOR_OK"){
  throw "PIE_EXEC_RECEIPT_COMMAND_MISSING"
}

Write-Host "PIE_EXEC_SELFTEST_OK" -ForegroundColor Green
