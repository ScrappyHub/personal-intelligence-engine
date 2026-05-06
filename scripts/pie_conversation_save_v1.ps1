param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$SessionId,
  [Parameter(Mandatory=$false)][string]$ProjectRepo = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)
$Conversation = Join-Path $RunRoot "conversation.ndjson"

if(-not (Test-Path -LiteralPath $Conversation -PathType Leaf)){
  throw ("PIE_CONVERSATION_MISSING: " + $Conversation)
}

$Hash = (Get-FileHash -LiteralPath $Conversation -Algorithm SHA256).Hash.ToLowerInvariant()
$SaveRoot = Join-Path $RepoRoot ("saved_conversations\" + $Hash)
New-Item -ItemType Directory -Force -Path $SaveRoot | Out-Null

Copy-Item -LiteralPath $Conversation -Destination (Join-Path $SaveRoot "conversation.ndjson") -Force

$Manifest = @"
{
  "schema": "pie.saved.conversation.v1",
  "session_id": "$SessionId",
  "conversation_hash": "$Hash",
  "saved_utc": "$([DateTime]::UtcNow.ToString("o"))"
}
"@

$Enc = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $SaveRoot "manifest.json"), ($Manifest.Replace("`r`n","`n") + "`n"), $Enc)
[System.IO.File]::WriteAllText((Join-Path $RunRoot "conversation.hash.txt"), ($Hash + "`n"), $Enc)

if(-not [string]::IsNullOrWhiteSpace($ProjectRepo)){
  $ProjectRepo = (Resolve-Path -LiteralPath $ProjectRepo).Path
  $ProjectSave = Join-Path $ProjectRepo (".pie\conversations\" + $Hash)
  New-Item -ItemType Directory -Force -Path $ProjectSave | Out-Null
  Copy-Item -LiteralPath (Join-Path $SaveRoot "conversation.ndjson") -Destination (Join-Path $ProjectSave "conversation.ndjson") -Force
  Copy-Item -LiteralPath (Join-Path $SaveRoot "manifest.json") -Destination (Join-Path $ProjectSave "manifest.json") -Force
}

Write-Host ("PIE_CONVERSATION_SAVE_OK: " + $Hash) -ForegroundColor Green