param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$Goal,
  [Parameter(Mandatory=$false)][string]$Status = "open",
  [Parameter(Mandatory=$false)][string]$SessionId = "",
  [Parameter(Mandatory=$false)][string]$Repo = "",
  [Parameter(Mandatory=$false)][string]$Notes = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$IntentRoot = Join-Path $RepoRoot "memory\intent"
$IntentLog = Join-Path $IntentRoot "intent.ndjson"
$Enc = New-Object System.Text.UTF8Encoding($false)

if($Status -notin @("open","paused","blocked","closed")){
  throw ("PIE_INTENT_BAD_STATUS: " + $Status)
}

New-Item -ItemType Directory -Force -Path $IntentRoot | Out-Null

$IntentIdSource = $Goal + "|" + $Repo + "|" + $SessionId
$Bytes = [System.Text.Encoding]::UTF8.GetBytes($IntentIdSource)
$Sha = [System.Security.Cryptography.SHA256]::Create()
$IntentId = ([BitConverter]::ToString($Sha.ComputeHash($Bytes)).Replace("-","").ToLowerInvariant()).Substring(0,24)

$Entry = [ordered]@{
  schema = "pie.intent.entry.v1"
  intent_id = $IntentId
  goal = $Goal
  status = $Status
  session_id = $SessionId
  repo = $Repo
  notes = $Notes
  created_utc = [DateTime]::UtcNow.ToString("o")
}

[System.IO.File]::AppendAllText($IntentLog,(($Entry | ConvertTo-Json -Depth 20 -Compress) + "`n"),$Enc)

Write-Host ("PIE_INTENT_RECORD_OK: " + $IntentId) -ForegroundColor Green
