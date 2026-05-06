param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$ConversationHash,
  [Parameter(Mandatory=$true)][string]$Text,
  [Parameter(Mandatory=$false)][string]$Lane = "active",
  [Parameter(Mandatory=$false)][string]$Project = "",
  [Parameter(Mandatory=$false)][string]$ProjectRepo = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$SaveRoot = Join-Path $RepoRoot ("saved_conversations\" + $ConversationHash)

if(-not (Test-Path -LiteralPath $SaveRoot -PathType Container)){
  throw ("PIE_SAVED_CONVERSATION_MISSING: " + $ConversationHash)
}

$Enc = New-Object System.Text.UTF8Encoding($false)
$Now = [DateTime]::UtcNow.ToString("o")
$ProposalPath = Join-Path $SaveRoot "memory_proposals.ndjson"

$SafeText = $Text.Replace("\","\\").Replace('"','\"')
$SafeProject = $Project.Replace("\","\\").Replace('"','\"')
$SafeProjectRepo = $ProjectRepo.Replace("\","\\").Replace('"','\"')

$Line = '{"ts":"' + $Now + '","status":"proposed","lane":"' + $Lane + '","project":"' + $SafeProject + '","project_repo":"' + $SafeProjectRepo + '","text":"' + $SafeText + '"}' + "`n"
[System.IO.File]::AppendAllText($ProposalPath,$Line,$Enc)

Write-Host ("PIE_MEMORY_PROPOSE_OK: " + $ProposalPath) -ForegroundColor Green