param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$ConversationHash,
  [Parameter(Mandatory=$false)][string]$SessionId = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$SaveRoot = Join-Path $RepoRoot ("saved_conversations\" + $ConversationHash)
$Conversation = Join-Path $SaveRoot "conversation.ndjson"

if(-not (Test-Path -LiteralPath $Conversation -PathType Leaf)){
  throw ("PIE_SAVED_CONVERSATION_NOT_FOUND: " + $ConversationHash)
}

if([string]::IsNullOrWhiteSpace($SessionId)){
  $SessionId = "reopen_" + $ConversationHash.Substring(0,12)
}

$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)
New-Item -ItemType Directory -Force -Path $RunRoot | Out-Null

Copy-Item -LiteralPath $Conversation -Destination (Join-Path $RunRoot "conversation.ndjson") -Force

Write-Host ("PIE_CONVERSATION_OPEN_OK: " + $SessionId) -ForegroundColor Green
Write-Host ("HASH: " + $ConversationHash) -ForegroundColor Green
Write-Host ("RUN: " + $RunRoot) -ForegroundColor Green