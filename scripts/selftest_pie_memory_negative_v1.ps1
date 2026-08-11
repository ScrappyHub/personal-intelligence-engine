param([Parameter(Mandatory=$true)][string]$RepoRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$SessionId = "pie_memory_negative_selftest"
$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)
$MemoryRoot = Join-Path $RunRoot "fixture_memory"
$Enc = New-Object System.Text.UTF8Encoding($false)
if(Test-Path -LiteralPath $RunRoot -PathType Container){ Remove-Item -LiteralPath $RunRoot -Recurse -Force }
& (Join-Path $RepoRoot "scripts\pie_agent_start_v1.ps1") -RepoRoot $RepoRoot -SessionId $SessionId -Backend mock -Model memory-negative-mock -ProjectRepo "" -Goal "memory negative selftest" | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $MemoryRoot "active") | Out-Null
[System.IO.File]::WriteAllText((Join-Path $MemoryRoot "active\memory.ndjson"),"{not-valid-json}`n",$Enc)

$FailedClosed = $false
try {
  & (Join-Path $RepoRoot "scripts\pie_memory_resolve_v1.ps1") -RepoRoot $RepoRoot -SessionId $SessionId -Query "test" -MemoryRoot $MemoryRoot | Out-Null
}
catch {
  if($_.Exception.Message -like "PIE_MEMORY_NDJSON_INVALID:*"){ $FailedClosed = $true }
}
if(-not $FailedClosed){ throw "PIE_MEMORY_MALFORMED_INPUT_NOT_REJECTED" }
Write-Host "PIE_MEMORY_NEGATIVE_SELFTEST_OK" -ForegroundColor Green
