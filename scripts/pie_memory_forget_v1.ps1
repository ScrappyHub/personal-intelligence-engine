param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$MemoryId,
  [Parameter(Mandatory=$false)][string]$Reason = "user_requested",
  [Parameter(Mandatory=$false)][string]$MemoryRoot = "",
  [Parameter(Mandatory=$false)][string]$ReceiptPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$MemoryLock = $null
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $RepoRoot "scripts\_lib_pie_memory_v1.ps1")

if($MemoryId -notmatch '^mem_[0-9a-f]{64}$'){ throw "PIE_MEMORY_ID_INVALID" }
if([string]::IsNullOrWhiteSpace($MemoryRoot)){ $MemoryRoot = Join-Path $RepoRoot "memory" }
$MemoryLock = PIE_AcquireMemoryLock -MemoryRoot $MemoryRoot
trap {
  if($null -ne $MemoryLock){ $MemoryLock.Dispose(); $MemoryLock = $null }
  throw $_
}
$Matches = @(PIE_MemoryRecords -RepoRoot $RepoRoot -MemoryRoot $MemoryRoot -Lane "all" -IncludeAllProjects -Limit 200 | Where-Object { $_.memory_id -eq $MemoryId })
if($Matches.Count -eq 0){ throw ("PIE_MEMORY_NOT_FOUND: " + $MemoryId) }
if($Matches.Count -gt 1){ throw ("PIE_MEMORY_ID_COLLISION: " + $MemoryId) }

$Record = $Matches[0]
$Tombstone = [ordered]@{
  schema = "pie.memory.tombstone.v1"
  target_memory_id = $MemoryId
  lane = $Record.lane
  project = $Record.project
  reason = $Reason
  created_utc = [DateTime]::UtcNow.ToString("o")
}
[System.IO.File]::AppendAllText($Record.source_path,(($Tombstone | ConvertTo-Json -Compress) + "`n"),(New-Object System.Text.UTF8Encoding($false)))
PIE_MemoryAppendReceipt -RepoRoot $RepoRoot -Event "forgotten" -MemoryId $MemoryId -Lane $Record.lane -Project $Record.project -ReceiptPath $ReceiptPath
$MemoryLock.Dispose()
$MemoryLock = $null

Write-Host ("PIE_MEMORY_FORGET_OK: " + $MemoryId) -ForegroundColor Green
