param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$SessionId,
  [Parameter(Mandatory=$true)][string]$UserMessage
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)
$Enc = New-Object System.Text.UTF8Encoding($false)

function Write-Utf8NoBomLf {
  param(
    [Parameter(Mandatory=$true)][string]$Path,
    [Parameter(Mandatory=$true)][string]$Text
  )

  $Dir = Split-Path -Parent $Path

  if(-not (Test-Path -LiteralPath $Dir -PathType Container)){
    New-Item -ItemType Directory -Force -Path $Dir | Out-Null
  }

  $Clean = $Text.Replace("`r`n","`n").Replace("`r","`n")

  if(-not $Clean.EndsWith("`n")){
    $Clean += "`n"
  }

  [System.IO.File]::WriteAllText($Path,$Clean,$Enc)
}

function Read-TextIfExists {
  param([Parameter(Mandatory=$true)][string]$Path)

  if(Test-Path -LiteralPath $Path -PathType Leaf){
    return (Get-Content -LiteralPath $Path -Raw).Trim()
  }

  return ""
}

function Get-LatestRepoScanText {
  param([Parameter(Mandatory=$true)][string]$TargetRepo)

  $ArtifactRoot = Join-Path $TargetRepo ".pie\scan\artifacts"

  if(-not (Test-Path -LiteralPath $ArtifactRoot -PathType Container)){
    return ""
  }

  $Latest = Get-ChildItem -LiteralPath $ArtifactRoot -Directory -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending |
    Select-Object -First 1

  if($null -eq $Latest){
    return ""
  }

  $Desc = Join-Path $Latest.FullName "ai_repo_description.md"

  if(Test-Path -LiteralPath $Desc -PathType Leaf){
    $Text = Get-Content -LiteralPath $Desc -Raw

    if($Text.Length -gt 9000){
      $Text = $Text.Substring(0,9000) + "`n`n[repo scan truncated]"
    }

    return $Text.Trim()
  }

  return ""
}

function Get-RepoMemoryText {
  param([Parameter(Mandatory=$true)][string]$TargetRepo)

  $MemoryPath = Join-Path $TargetRepo ".pie\memory\memory.ndjson"

  if(Test-Path -LiteralPath $MemoryPath -PathType Leaf){
    $Lines = @(Get-Content -LiteralPath $MemoryPath -ErrorAction SilentlyContinue | Select-Object -Last 25)
    return ($Lines -join "`n").Trim()
  }

  return ""
}

$Goal = Read-TextIfExists -Path (Join-Path $RunRoot "goal.txt")
$Language = Read-TextIfExists -Path (Join-Path $RunRoot "language.txt")
$LanguageVersion = Read-TextIfExists -Path (Join-Path $RunRoot "language_version.txt")
$ProjectRepo = Read-TextIfExists -Path (Join-Path $RunRoot "project_repo.txt")

$RepoScan = ""
$RepoMemory = ""

if(-not [string]::IsNullOrWhiteSpace($ProjectRepo)){
  if(Test-Path -LiteralPath $ProjectRepo -PathType Container){
    $ProjectRepo = (Resolve-Path -LiteralPath $ProjectRepo).Path
    $RepoScan = Get-LatestRepoScanText -TargetRepo $ProjectRepo
    $RepoMemory = Get-RepoMemoryText -TargetRepo $ProjectRepo
  }
}

$ContextRoot = Join-Path $RunRoot "context_packets"
$Stamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
$PacketPath = Join-Path $ContextRoot ("context_packet_" + $Stamp + ".json")
$PromptPath = Join-Path $ContextRoot ("context_prompt_" + $Stamp + ".txt")

$Packet = [ordered]@{
  schema = "pie.context.packet.v1"
  session_id = $SessionId
  goal = $Goal
  language = $Language
  language_version = $LanguageVersion
  project_repo = $ProjectRepo
  has_repo_scan = -not [string]::IsNullOrWhiteSpace($RepoScan)
  has_repo_memory = -not [string]::IsNullOrWhiteSpace($RepoMemory)
  user_message = $UserMessage
  created_utc = [DateTime]::UtcNow.ToString("o")
}

$Prompt = @"
PIE GOVERNED CONTEXT PACKET

ROLE:
You are PIE, a local-first governed AI runtime.
You are assistant-only, not executor.
You must use deterministic repo facts before model guesses.
Do not invent repo identity, files, WBS docs, specs, schemas, or commands.
If repo scan facts say what the repo is, that identity is authoritative.
If facts are missing, say what is missing.

SESSION GOAL:
$Goal

LANGUAGE / RUNTIME:
$Language
$LanguageVersion

PROJECT REPO:
$ProjectRepo

REPO MEMORY:
$RepoMemory

LATEST REPO SCAN ARTIFACT:
$RepoScan

USER MESSAGE:
$UserMessage
"@

Write-Utf8NoBomLf -Path $PacketPath -Text ($Packet | ConvertTo-Json -Depth 12)
Write-Utf8NoBomLf -Path $PromptPath -Text $Prompt

Write-Host ("PIE_CONTEXT_BUILD_OK: " + $PromptPath) -ForegroundColor Green
