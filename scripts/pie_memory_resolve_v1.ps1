param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$SessionId,
  [Parameter(Mandatory=$false)][string]$Query = "",
  [Parameter(Mandatory=$false)][string]$QueryPath = "",
  [Parameter(Mandatory=$false)][string]$MemoryRoot = "",
  [Parameter(Mandatory=$false)][string]$PolicyPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $RepoRoot "scripts\_lib_pie_memory_v1.ps1")
. (Join-Path $RepoRoot "scripts\_lib_pie_agent_session_v1.ps1")
$Session = PIE_GetAgentSession -RepoRoot $RepoRoot -SessionId $SessionId -RequireIntegrity
$RunRoot = $Session.run_root
$MemoryResolveRoot = Join-Path $RunRoot "memory_resolve"
$Enc = New-Object System.Text.UTF8Encoding($false)

if(-not [string]::IsNullOrWhiteSpace($QueryPath)){
  if(-not (Test-Path -LiteralPath $QueryPath -PathType Leaf)){ throw ("PIE_MEMORY_QUERY_PATH_NOT_FOUND: " + $QueryPath) }
  $Query = [System.IO.File]::ReadAllText($QueryPath,$Enc)
}

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

$Goal = $Session.goal
$Language = Read-TextIfExists (Join-Path $RunRoot "language.txt")
$LanguageVersion = Read-TextIfExists (Join-Path $RunRoot "language_version.txt")
$ProjectRepo = $Session.project_repo
$RepoLinks = Read-TextIfExists (Join-Path $RunRoot "repo_links.ndjson")
$ExecReceipts = Read-TextIfExists (Join-Path $RunRoot "execution\execution_receipts.ndjson")
$RankLatest = Read-TextIfExists (Join-Path $RunRoot "context_rank\latest_context_rank.json")

$Project = ""
if(-not [string]::IsNullOrWhiteSpace($ProjectRepo)){
  $ProfilePath = Join-Path $ProjectRepo ".pie\profile.json"
  if(Test-Path -LiteralPath $ProfilePath -PathType Leaf){
    try { $Project = [string]((Get-Content -LiteralPath $ProfilePath -Raw | ConvertFrom-Json).project) }
    catch { throw ("PIE_MEMORY_PROJECT_PROFILE_INVALID: " + $ProfilePath + " :: " + $_.Exception.Message) }
  }
  if([string]::IsNullOrWhiteSpace($Project)){ $Project = Split-Path -Leaf $ProjectRepo }
}

$ResolvedMemory = ""
$MemoryPolicy = PIE_MemoryPolicy -RepoRoot $RepoRoot -PolicyPath $PolicyPath
if([string]$MemoryPolicy.mode -ne "off"){
  $Records = @(PIE_MemoryRecords -RepoRoot $RepoRoot -MemoryRoot $MemoryRoot -Project $Project -ProjectRepo $ProjectRepo -ProjectIdentityHash $Session.project_identity_sha256 -Query $Query -Lane "all" -Limit 25)
  $Records = @($Records | Where-Object {
    -not ($_.lane -eq "coding" -and -not [bool]$MemoryPolicy.coding_memory_enabled) -and
    -not ($_.lane -eq "project" -and -not [bool]$MemoryPolicy.project_memory_enabled)
  })
  $MemoryLines = New-Object System.Collections.Generic.List[string]
  foreach($Record in $Records){
    [void]$MemoryLines.Add(("- [" + $Record.memory_id + "][" + $Record.lane + "][score=" + [string]$Record.score + "] " + $Record.text))
  }
  $ResolvedMemory = $MemoryLines.ToArray() -join "`n"
}
$RepoMemory = ""
if([string]$MemoryPolicy.mode -ne "off" -and [bool]$MemoryPolicy.repo_memory_enabled -and `
   -not [string]::IsNullOrWhiteSpace($ProjectRepo) -and (Test-Path -LiteralPath $ProjectRepo -PathType Container)){
  $RepoMemoryPath = Join-Path $ProjectRepo ".pie\memory\memory.ndjson"
  if(Test-Path -LiteralPath $RepoMemoryPath -PathType Leaf){
    $RepoMemoryLines = New-Object System.Collections.Generic.List[string]
    $RepoMemoryLineNumber = 0
    foreach($RepoMemoryLine in @(Get-Content -LiteralPath $RepoMemoryPath)){
      $RepoMemoryLineNumber++
      if([string]::IsNullOrWhiteSpace($RepoMemoryLine)){ continue }
      try { $RepoMemoryRecord = $RepoMemoryLine | ConvertFrom-Json }
      catch { throw ("PIE_REPO_MEMORY_NDJSON_INVALID: " + $RepoMemoryPath + ":" + $RepoMemoryLineNumber) }
      if([string]$RepoMemoryRecord.schema -ne "pie.memory.record.v1" -or [string]$RepoMemoryRecord.lane -ne "project"){
        throw ("PIE_REPO_MEMORY_SCHEMA_BAD: " + $RepoMemoryPath + ":" + $RepoMemoryLineNumber)
      }
      $RecordRepo = PIE_NormalizeMemoryRepo -Path ([string]$RepoMemoryRecord.project_repo)
      if($RecordRepo -ine (PIE_NormalizeMemoryRepo -Path $ProjectRepo)){
        throw ("PIE_REPO_MEMORY_BINDING_MISMATCH: " + $RepoMemoryPath + ":" + $RepoMemoryLineNumber)
      }
      $RecordIdentity = [string]$RepoMemoryRecord.project_identity_sha256
      if(-not [string]::IsNullOrWhiteSpace($RecordIdentity) -and $RecordIdentity -ne $Session.project_identity_sha256){
        throw ("PIE_REPO_MEMORY_IDENTITY_DRIFT: " + $RepoMemoryPath + ":" + $RepoMemoryLineNumber)
      }
      if([string]::IsNullOrWhiteSpace([string]$RepoMemoryRecord.text)){ throw ("PIE_REPO_MEMORY_TEXT_MISSING: " + $RepoMemoryPath + ":" + $RepoMemoryLineNumber) }
      [void]$RepoMemoryLines.Add([string]$RepoMemoryRecord.text)
    }
    $RepoMemory = $RepoMemoryLines.ToArray() -join "`n"
  }
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
Add-Section -Lines $Lines -Title "Resolved Personal Memory" -Body $ResolvedMemory
Add-Section -Lines $Lines -Title "Repo Memory" -Body $RepoMemory
Add-Section -Lines $Lines -Title "Repo Links" -Body $RepoLinks
Add-Section -Lines $Lines -Title "Context Rank" -Body $RankLatest
Add-Section -Lines $Lines -Title "Execution Receipts" -Body $ExecReceipts

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
$OutPath = Join-Path $MemoryResolveRoot ("memory_resolution_" + $Stamp + ".md")
$LatestPath = Join-Path $MemoryResolveRoot "latest_memory_resolution.md"

$Text = $Lines.ToArray() -join "`n"
Write-Utf8NoBomLf -Path $OutPath -Text $Text
Write-Utf8NoBomLf -Path $LatestPath -Text $Text

Write-Host ("PIE_MEMORY_RESOLVE_OK: " + $OutPath) -ForegroundColor Green
