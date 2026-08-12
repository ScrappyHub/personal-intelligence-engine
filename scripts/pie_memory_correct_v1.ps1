param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$MemoryId,
  [Parameter(Mandatory=$true)][string]$Text,
  [switch]$Yes
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $RepoRoot "scripts\_lib_pie_memory_v1.ps1")

# Correct a memory by superseding it: record the new fact in the SAME lane/project scope, then forget
# the old one. Accept-then-forget order is deliberate — if the new record fails, the old is preserved
# (never a window with neither). B7 (user memory controls: correction).

$Records = @(PIE_MemoryRecords -RepoRoot $RepoRoot -Project "" -Query "" -Lane "all" -IncludeAllProjects:$true -Limit 1000000)
$Match = @($Records | Where-Object { $_.memory_id -eq $MemoryId })
if($Match.Count -eq 0){ throw ("PIE_MEMORY_NOT_FOUND: " + $MemoryId) }
$Old = $Match[0]

$Accept = Join-Path $RepoRoot "scripts\pie_memory_accept_v1.ps1"
$Forget = Join-Path $RepoRoot "scripts\pie_memory_forget_v1.ps1"

$AcceptArgs = @("-RepoRoot",$RepoRoot,"-Text",$Text,"-Lane",[string]$Old.lane)
if(-not [string]::IsNullOrWhiteSpace([string]$Old.project)){ $AcceptArgs += @("-Project",[string]$Old.project) }
if(-not [string]::IsNullOrWhiteSpace([string]$Old.project_repo)){ $AcceptArgs += @("-ProjectRepo",[string]$Old.project_repo) }
if($Yes){ $AcceptArgs += "-Yes" }

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Accept @AcceptArgs
if($LASTEXITCODE -ne 0){ throw ("PIE_MEMORY_CORRECT_ACCEPT_FAILED: " + $MemoryId) }

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Forget -RepoRoot $RepoRoot -MemoryId $MemoryId
if($LASTEXITCODE -ne 0){ throw ("PIE_MEMORY_CORRECT_FORGET_FAILED: " + $MemoryId) }

Write-Host ("PIE_MEMORY_CORRECT_OK: superseded " + $MemoryId + " in lane " + [string]$Old.lane) -ForegroundColor Green
