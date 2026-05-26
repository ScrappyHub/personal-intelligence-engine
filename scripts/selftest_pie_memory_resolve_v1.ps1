param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$SessionId = "pie_memory_resolve_selftest"
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
Write-Utf8NoBomLf -Path (Join-Path $RunRoot "goal.txt") -Text "memory resolution selftest"
Write-Utf8NoBomLf -Path (Join-Path $RunRoot "language.txt") -Text "PowerShell"
Write-Utf8NoBomLf -Path (Join-Path $RunRoot "language_version.txt") -Text "5.1"
Write-Utf8NoBomLf -Path (Join-Path $RunRoot "project_repo.txt") -Text $RepoRoot
Write-Utf8NoBomLf -Path (Join-Path $RunRoot "conversation.ndjson") -Text '{"schema":"test","message":"remember deterministic repo context"}'

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_memory_resolve_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -Query "what are we working on?" | Out-Host

if($LASTEXITCODE -ne 0){ throw "MEMORY_RESOLVE_CHILD_FAIL" }

$Latest = Join-Path $RunRoot "memory_resolve\latest_memory_resolution.md"
if(-not (Test-Path -LiteralPath $Latest -PathType Leaf)){ throw "MEMORY_RESOLVE_LATEST_MISSING" }

$Text = Get-Content -LiteralPath $Latest -Raw
if($Text -notmatch "memory resolution selftest"){ throw "MEMORY_RESOLVE_GOAL_MISSING" }
if($Text -notmatch "deterministic repo context"){ throw "MEMORY_RESOLVE_CONVERSATION_MISSING" }

Write-Host "PIE_MEMORY_RESOLVE_SELFTEST_OK" -ForegroundColor Green
