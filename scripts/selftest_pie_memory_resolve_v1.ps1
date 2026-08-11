param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$SessionId = "pie_memory_resolve_selftest"
$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)
$FixtureMemory = Join-Path $RunRoot "fixture_memory"
$Enc = New-Object System.Text.UTF8Encoding($false)
. (Join-Path $RepoRoot "scripts\_lib_pie_memory_v1.ps1")

function Write-Utf8NoBomLf {
  param([string]$Path,[string]$Text)
  $Dir = Split-Path -Parent $Path
  if(-not (Test-Path -LiteralPath $Dir -PathType Container)){ New-Item -ItemType Directory -Force -Path $Dir | Out-Null }
  $Clean = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $Clean.EndsWith("`n")){ $Clean += "`n" }
  [System.IO.File]::WriteAllText($Path,$Clean,$Enc)
}

if(Test-Path -LiteralPath $RunRoot -PathType Container){ Remove-Item -LiteralPath $RunRoot -Recurse -Force }
& (Join-Path $RepoRoot "scripts\pie_agent_start_v1.ps1") -RepoRoot $RepoRoot -SessionId $SessionId -Backend mock -Model memory-mock -ProjectRepo $RepoRoot -Goal "memory resolution selftest" | Out-Null
Write-Utf8NoBomLf -Path (Join-Path $RunRoot "goal.txt") -Text "memory resolution selftest"
Write-Utf8NoBomLf -Path (Join-Path $RunRoot "language.txt") -Text "PowerShell"
Write-Utf8NoBomLf -Path (Join-Path $RunRoot "language_version.txt") -Text "5.1"
Write-Utf8NoBomLf -Path (Join-Path $RunRoot "project_repo.txt") -Text $RepoRoot

$ActiveId = PIE_MemoryId -Lane "active" -Project "" -ProjectRepo "" -Text "Prefer concise answers unless detail is requested."
$CodingId = PIE_MemoryId -Lane "coding" -Project "" -ProjectRepo "" -Text "Use PowerShell formatting for Windows examples."
$ProjectId = PIE_MemoryId -Lane "project" -Project "pie" -ProjectRepo $RepoRoot -Text "PIE memory must remain local and deterministic."
$HiddenId = PIE_MemoryId -Lane "active" -Project "" -ProjectRepo "" -Text "This forgotten memory must stay hidden."
Write-Utf8NoBomLf -Path (Join-Path $FixtureMemory "active\memory.ndjson") -Text ((@(
  (@{schema="pie.memory.record.v1";memory_id=$ActiveId;lane="active";project="";project_repo="";text="Prefer concise answers unless detail is requested.";created_utc="2026-01-01T00:00:00Z"} | ConvertTo-Json -Compress),
  (@{schema="pie.memory.record.v1";memory_id=$HiddenId;lane="active";project="";project_repo="";text="This forgotten memory must stay hidden.";created_utc="2026-01-02T00:00:00Z"} | ConvertTo-Json -Compress),
  (@{schema="pie.memory.tombstone.v1";target_memory_id=$HiddenId;created_utc="2026-01-03T00:00:00Z"} | ConvertTo-Json -Compress)
) -join "`n"))
Write-Utf8NoBomLf -Path (Join-Path $FixtureMemory "coding\memory.ndjson") -Text (@{schema="pie.memory.record.v1";memory_id=$CodingId;lane="coding";project="";project_repo="";text="Use PowerShell formatting for Windows examples.";created_utc="2026-01-02T00:00:00Z"} | ConvertTo-Json -Compress)
Write-Utf8NoBomLf -Path (Join-Path $FixtureMemory "projects\pie\memory.ndjson") -Text (@{schema="pie.memory.record.v1";memory_id=$ProjectId;lane="project";project="pie";project_repo=$RepoRoot;text="PIE memory must remain local and deterministic.";created_utc="2026-01-03T00:00:00Z"} | ConvertTo-Json -Compress)

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_memory_resolve_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -Query "PowerShell deterministic memory" `
  -MemoryRoot $FixtureMemory | Out-Host

if($LASTEXITCODE -ne 0){ throw "MEMORY_RESOLVE_CHILD_FAIL" }

$Latest = Join-Path $RunRoot "memory_resolve\latest_memory_resolution.md"
if(-not (Test-Path -LiteralPath $Latest -PathType Leaf)){ throw "MEMORY_RESOLVE_LATEST_MISSING" }

$Text = Get-Content -LiteralPath $Latest -Raw
if($Text -notmatch "memory resolution selftest"){ throw "MEMORY_RESOLVE_GOAL_MISSING" }
if($Text -match "deterministic repo context"){ throw "MEMORY_RESOLVE_CONVERSATION_LEAK" }
if($Text -notmatch "Use PowerShell formatting"){ throw "MEMORY_RESOLVE_CODING_MEMORY_MISSING" }
if($Text -notmatch "PIE memory must remain local and deterministic"){ throw "MEMORY_RESOLVE_PROJECT_MEMORY_MISSING" }
if($Text -match "forgotten memory must stay hidden"){ throw "MEMORY_RESOLVE_TOMBSTONE_IGNORED" }
if($Text -match "Prefer concise answers"){ throw "MEMORY_RESOLVE_ACTIVE_MEMORY_PROJECT_LEAK" }

Write-Host "PIE_MEMORY_RESOLVE_SELFTEST_OK" -ForegroundColor Green
