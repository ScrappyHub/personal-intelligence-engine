param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$false)][string]$Query = "",
  [Parameter(Mandatory=$false)][ValidateSet("all","active","coding","project")][string]$Lane = "all",
  [Parameter(Mandatory=$false)][string]$Project = "",
  [Parameter(Mandatory=$false)][int]$Limit = 25,
  [Parameter(Mandatory=$false)][string]$MemoryRoot = "",
  [Parameter(Mandatory=$false)][string]$PolicyPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $RepoRoot "scripts\_lib_pie_memory_v1.ps1")

$Policy = PIE_MemoryPolicy -RepoRoot $RepoRoot -PolicyPath $PolicyPath
Write-Host ("PIE MEMORY mode=" + [string]$Policy.mode) -ForegroundColor Cyan
if([string]$Policy.mode -eq "off"){
  Write-Host "Memory is disabled."
  return
}

$Records = @(PIE_MemoryRecords -RepoRoot $RepoRoot -MemoryRoot $MemoryRoot -Project $Project -Query $Query -Lane $Lane -IncludeAllProjects:($Lane -in @("all","project")) -Limit $Limit)
$Records = @($Records | Where-Object {
  -not ($_.lane -eq "coding" -and -not [bool]$Policy.coding_memory_enabled) -and
  -not ($_.lane -eq "project" -and -not [bool]$Policy.project_memory_enabled)
})
if(-not [string]::IsNullOrWhiteSpace($Query)){ $Records = @($Records | Where-Object { $_.score -gt 0 }) }

if($Records.Count -eq 0){
  Write-Host "No matching memories."
  return
}

foreach($Record in $Records){
  $ProjectText = if([string]::IsNullOrWhiteSpace($Record.project)){ "" } else { " project=" + $Record.project }
  Write-Output ("[" + $Record.memory_id + "] lane=" + $Record.lane + $ProjectText + " score=" + [string]$Record.score)
  Write-Output ("  " + $Record.text)
}
Write-Host ("PIE_MEMORY_QUERY_OK: " + [string]$Records.Count) -ForegroundColor Green
