param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$SessionId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$SessionLock = $null
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $RepoRoot "scripts\_lib_pie_agent_session_v1.ps1")
$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)
$SessionLock = PIE_AcquireSessionLock -RunRoot $RunRoot
trap {
  if($null -ne $SessionLock){ $SessionLock.Dispose(); $SessionLock = $null }
  throw $_
}
$Session = PIE_GetAgentSession -RepoRoot $RepoRoot -SessionId $SessionId -OperationLockHeld
$Enc = New-Object System.Text.UTF8Encoding($false)
$Utc = [DateTime]::UtcNow.ToString("o")

$Session.state.status = "stopped"
$Session.manifest.status = "stopped"
if($null -eq $Session.state.PSObject.Properties["stopped_utc"]){ $Session.state | Add-Member -NotePropertyName stopped_utc -NotePropertyValue $Utc }
else { $Session.state.stopped_utc = $Utc }
if($null -eq $Session.manifest.PSObject.Properties["stopped_utc"]){ $Session.manifest | Add-Member -NotePropertyName stopped_utc -NotePropertyValue $Utc }
else { $Session.manifest.stopped_utc = $Utc }
PIE_WriteSessionPair -RunRoot $RunRoot -SessionId $SessionId -State $Session.state -Manifest $Session.manifest -Event "session_stop"

$Receipt = [ordered]@{ schema="pie.session.receipt.v1"; event="session_stop"; session_id=$SessionId; binding_sha256=$Session.binding_sha256; utc=$Utc }
[System.IO.File]::AppendAllText((Join-Path $RunRoot "receipts.ndjson"),(($Receipt | ConvertTo-Json -Compress) + "`n"),$Enc)
[System.IO.File]::AppendAllText((Join-Path $RunRoot "stdout.log"),("SESSION_STOP: " + $SessionId + "`n"),$Enc)
$SessionLock.Dispose()
$SessionLock = $null

Write-Host ("PIE_AGENT_STOP_OK: " + $SessionId) -ForegroundColor Green
Write-Host $RunRoot
