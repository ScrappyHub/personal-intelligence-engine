param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$SessionId,
  [Parameter(Mandatory=$false)][string]$Query = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)
$MemoryRoot = Join-Path $RunRoot "memory_resolve"
$Enc = New-Object System.Text.UTF8Encoding($false)

function Write-Utf8NoBomLf {
  param([string]$Path,[string]$Text)
  $Dir = Split-Path -Parent $Path
  if(-not (Test-Path -LiteralPath $Dir -PathType Container)){
    New-Item -ItemType Directory -Force -Path $Dir | Out-Null
  }
  $Clean = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $Clean.EndsWith("`n")){ $Clean += "`n" }
  [System.IO.File]::WriteAllText($Path,$Clean,$Enc)
}

function Read-TextIfExists {
  param([string]$Path)
  if(Test-Path -LiteralPath $Path -PathType Leaf){
    return (Get-Content -LiteralPath $Path -Raw).Trim()
  }
  return ""
}

function Add-Section {
  param(
    [System.Collections.Generic.List[string]]$Lines,
    [string]$Title,
    [string]$Body
  )

  if([string]::IsNullOrWhiteSpace($Body)){ return }

  [void]$Lines.Add("")
  [void]$Lines.Add("## " + $Title)
  [void]$Lines.Add("")
  [void]$Lines.Add($Body.Trim())
}

if(-not (Test-Path -LiteralPath $RunRoot -PathType Container)){
  throw ("PIE_MEMORY_RESOLVE_SESSION_NOT_FOUND: " + $SessionId)
}

$Goal = Read-TextIfExists (Join-Path $RunRoot "goal.txt")
$Language = Read-TextIfExists (Join-Path $RunRoot "language.txt")
$LanguageVersion = Read-TextIfExists (Join-Path $RunRoot "language_version.txt")
$ProjectRepo = Read-TextIfExists (Join-Path $RunRoot "project_repo.txt")
$Conversation = Read-TextIfExists (Join-Path $RunRoot "conversation.ndjson")
$RepoLinks = Read-TextIfExists (Join-Path $RunRoot "repo_links.ndjson")
$ExecReceipts = Read-TextIfExists (Join-Path $RunRoot "execution\execution_receipts.ndjson")
$RankLatest = Read-TextIfExists (Join-Path $RunRoot "context_rank\latest_context_rank.json")

$RepoMemory = ""
if(-not [string]::IsNullOrWhiteSpace($ProjectRepo) -and (Test-Path -LiteralPath $ProjectRepo -PathType Container)){
  $RepoMemoryPath = Join-Path $ProjectRepo ".pie\memory\memory.ndjson"
  $RepoMemory = Read-TextIfExists $RepoMemoryPath
}

if($Conversation.Length -gt 8000){
  $Conversation = $Conversation.Substring($Conversation.Length - 8000)
}

if($ExecReceipts.Length -gt 8000){
  $ExecReceipts = $ExecReceipts.Substring($ExecReceipts.Length - 8000)
}

$Lines = New-Object System.Collections.Generic.List[string]

[void]$Lines.Add("# PIE Memory Resolution Packet")
[void]$Lines.Add("")
[void]$Lines.Add("- schema: pie.memory.resolution.v1")
[void]$Lines.Add("- session_id: " + $SessionId)
[void]$Lines.Add("- query: " + $Query)
[void]$Lines.Add("- created_utc: " + [DateTime]::UtcNow.ToString("o"))

Add-Section -Lines $Lines -Title "Session Goal" -Body $Goal
Add-Section -Lines $Lines -Title "Language Runtime" -Body ($Language + " " + $LanguageVersion).Trim()
Add-Section -Lines $Lines -Title "Primary Repo" -Body $ProjectRepo
Add-Section -Lines $Lines -Title "Repo Memory" -Body $RepoMemory
Add-Section -Lines $Lines -Title "Repo Links" -Body $RepoLinks
Add-Section -Lines $Lines -Title "Context Rank" -Body $RankLatest
Add-Section -Lines $Lines -Title "Recent Conversation" -Body $Conversation
Add-Section -Lines $Lines -Title "Execution Receipts" -Body $ExecReceipts

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
$OutPath = Join-Path $MemoryRoot ("memory_resolution_" + $Stamp + ".md")
$LatestPath = Join-Path $MemoryRoot "latest_memory_resolution.md"

$Text = $Lines.ToArray() -join "`n"
Write-Utf8NoBomLf -Path $OutPath -Text $Text
Write-Utf8NoBomLf -Path $LatestPath -Text $Text

Write-Host ("PIE_MEMORY_RESOLVE_OK: " + $OutPath) -ForegroundColor Green
