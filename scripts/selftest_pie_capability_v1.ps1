param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$SessionId = "pie_capability_selftest"
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

if(Test-Path -LiteralPath $RunRoot -PathType Container){
  Remove-Item -LiteralPath $RunRoot -Recurse -Force
}

New-Item -ItemType Directory -Force -Path $RunRoot | Out-Null
Write-Utf8NoBomLf -Path (Join-Path $RunRoot "project_repo.txt") -Text $RepoRoot

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_capability_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -CapabilityId "repo.status" `
  -AutoConfirmAllowed | Out-Host

if($LASTEXITCODE -ne 0){
  throw "PIE_CAPABILITY_SELFTEST_STATUS_FAIL"
}

$Receipt = Join-Path $RunRoot "execution\execution_receipts.ndjson"
if(-not (Test-Path -LiteralPath $Receipt -PathType Leaf)){
  throw "PIE_CAPABILITY_SELFTEST_RECEIPT_MISSING"
}

$Text = Get-Content -LiteralPath $Receipt -Raw
if($Text -notmatch "git status"){
  throw "PIE_CAPABILITY_SELFTEST_RECEIPT_BAD"
}

Write-Host "PIE_CAPABILITY_SELFTEST_OK" -ForegroundColor Green
