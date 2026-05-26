param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$SessionId = "pie_plan_selftest"
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
Write-Utf8NoBomLf -Path (Join-Path $RunRoot "goal.txt") -Text "planner selftest"

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_plan_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -Goal "Build deterministic planner lane." | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_PLAN_CHILD_FAIL" }

$Queue = Join-Path $RunRoot "execution_queue.ndjson"
if(-not (Test-Path -LiteralPath $Queue -PathType Leaf)){ throw "PIE_PLAN_QUEUE_MISSING" }

$QueueText = Get-Content -LiteralPath $Queue -Raw
if($QueueText -notmatch "01_resolve_memory"){ throw "PIE_PLAN_QUEUE_MEMORY_STEP_MISSING" }
if($QueueText -notmatch "05_execute_receipted"){ throw "PIE_PLAN_QUEUE_EXEC_STEP_MISSING" }
if($QueueText -notmatch "requires_confirmation"){ throw "PIE_PLAN_QUEUE_CONFIRMATION_MISSING" }

Write-Host "PIE_PLAN_SELFTEST_OK" -ForegroundColor Green
