param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$SessionId = "pie_execution_replay_selftest"
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

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_exec_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -Command "Write-Output PIE_REPLAY_VECTOR_OK" `
  -Confirm | Out-Host

if($LASTEXITCODE -ne 0){
  throw "PIE_REPLAY_EXEC_VECTOR_FAIL"
}

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_execution_replay_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId | Out-Host

if($LASTEXITCODE -ne 0){
  throw "PIE_REPLAY_CHILD_FAIL"
}

$Latest = Join-Path $RunRoot "replay\latest_execution_replay.json"

if(-not (Test-Path -LiteralPath $Latest -PathType Leaf)){
  throw "PIE_REPLAY_LATEST_MISSING"
}

$Replay = Get-Content -LiteralPath $Latest -Raw | ConvertFrom-Json

if($Replay.status -ne "PIE_EXECUTION_REPLAY_OK"){
  throw "PIE_REPLAY_STATUS_NOT_OK"
}

if($Replay.receipt_count -lt 1){
  throw "PIE_REPLAY_RECEIPT_COUNT_ZERO"
}

Write-Host "PIE_EXECUTION_REPLAY_SELFTEST_OK" -ForegroundColor Green
