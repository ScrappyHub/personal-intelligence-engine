param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$MemoryId,
  [Parameter(Mandatory=$false)][string]$MemoryRoot = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $RepoRoot "scripts\_lib_pie_memory_v1.ps1")

# Read-only provenance view of a single memory: where it came from (source file + line), when it was
# recorded, its lane/project scope, and the stored text. B7 (user memory controls: inspect/provenance).

$Records = @(PIE_MemoryRecords -RepoRoot $RepoRoot -MemoryRoot $MemoryRoot -Project "" -Query "" -Lane "all" -IncludeAllProjects:$true -Limit 200)
$Match = @($Records | Where-Object { $_.memory_id -eq $MemoryId })
if($Match.Count -eq 0){ throw ("PIE_MEMORY_NOT_FOUND: " + $MemoryId) }
$R = $Match[0]

Write-Output ("memory_id:    " + [string]$R.memory_id)
Write-Output ("lane:         " + [string]$R.lane)
if(-not [string]::IsNullOrWhiteSpace([string]$R.project)){ Write-Output ("project:      " + [string]$R.project) }
if(-not [string]::IsNullOrWhiteSpace([string]$R.project_repo)){ Write-Output ("project_repo: " + [string]$R.project_repo) }
Write-Output ("provenance:   " + [string]$R.source_path + ":" + [string]$R.source_line)
Write-Output ("created_utc:  " + [string]$R.created_utc)
Write-Output ("text:         " + [string]$R.text)
Write-Host ("PIE_MEMORY_INSPECT_OK: " + $MemoryId) -ForegroundColor Green
