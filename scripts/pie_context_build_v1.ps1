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
  if(-not $Clean.EndsWith("`n")){ $Clean += "`n" }

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

  if($null -eq $Latest){ return "" }

  $Desc = Join-Path $Latest.FullName "ai_repo_description.md"

  if(Test-Path -LiteralPath $Desc -PathType Leaf){
    $Text = Get-Content -LiteralPath $Desc -Raw
    if($Text.Length -gt 7000){
      $Text = $Text.Substring(0,7000) + "`n`n[repo scan truncated]"
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

function Get-PolicySummary {
  param([Parameter(Mandatory=$true)][string]$RepoRoot)

  $RulesPath = Join-Path $RepoRoot "policies\PIE_POLICY_RULES.v1.json"

  if(-not (Test-Path -LiteralPath $RulesPath -PathType Leaf)){
    return "No PIE policy rules file found."
  }

  $Raw = Get-Content -LiteralPath $RulesPath -Raw
  if($Raw.Length -gt 4000){ $Raw = $Raw.Substring(0,4000) + "`n[policy truncated]" }

  return $Raw.Trim()
}

$Goal = Read-TextIfExists -Path (Join-Path $RunRoot "goal.txt")
$Language = Read-TextIfExists -Path (Join-Path $RunRoot "language.txt")
$LanguageVersion = Read-TextIfExists -Path (Join-Path $RunRoot "language_version.txt")
$ProjectRepo = Read-TextIfExists -Path (Join-Path $RunRoot "project_repo.txt")
$LinksPath = Join-Path $RunRoot "repo_links.ndjson"

$RepoScan = ""
$RepoMemory = ""

if(-not [string]::IsNullOrWhiteSpace($ProjectRepo)){
  if(Test-Path -LiteralPath $ProjectRepo -PathType Container){
    $ProjectRepo = (Resolve-Path -LiteralPath $ProjectRepo).Path
    $RepoScan = Get-LatestRepoScanText -TargetRepo $ProjectRepo
    $RepoMemory = Get-RepoMemoryText -TargetRepo $ProjectRepo
  }
}

$LinkedRepoText = New-Object System.Collections.Generic.List[string]
$LinkedRepoCount = 0

if(Test-Path -LiteralPath $LinksPath -PathType Leaf){
  foreach($Line in @(Get-Content -LiteralPath $LinksPath -ErrorAction SilentlyContinue | Select-Object -Last 10)){
    if([string]::IsNullOrWhiteSpace($Line)){ continue }

    try {
      $Obj = $Line | ConvertFrom-Json
      $LinkedRepo = [string]$Obj.target_repo
      $Role = [string]$Obj.role

      if(Test-Path -LiteralPath $LinkedRepo -PathType Container){
        $LinkedRepoCount++
        [void]$LinkedRepoText.Add("## LINKED REPO role=" + $Role)
        [void]$LinkedRepoText.Add("repo=" + $LinkedRepo)
        [void]$LinkedRepoText.Add((Get-LatestRepoScanText -TargetRepo $LinkedRepo))
        [void]$LinkedRepoText.Add("")
      }
    }
    catch { }
  }
}

$PolicySummary = Get-PolicySummary -RepoRoot $RepoRoot
$MemoryResolution = ""

$MemoryResolveScript = Join-Path $RepoRoot "scripts\pie_memory_resolve_v1.ps1"
if(Test-Path -LiteralPath $MemoryResolveScript -PathType Leaf){
  try {
    $ResolveOut = @(
      & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
        -File $MemoryResolveScript `
        -RepoRoot $RepoRoot `
        -SessionId $SessionId `
        -Query $UserMessage
    ) -join "`n"

    $MemoryLatest = Join-Path $RunRoot "memory_resolve\latest_memory_resolution.md"
    if(Test-Path -LiteralPath $MemoryLatest -PathType Leaf){
      $MemoryResolution = Get-Content -LiteralPath $MemoryLatest -Raw
      if($MemoryResolution.Length -gt 10000){
        $MemoryResolution = $MemoryResolution.Substring(0,10000) + "`n`n[memory resolution truncated]"
      }
    }
  }
  catch {
    $MemoryResolution = "Memory resolution unavailable: " + $_.Exception.Message
  }
}

$ContextRoot = Join-Path $RunRoot "context_packets"
$Stamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
$PacketPath = Join-Path $ContextRoot ("context_packet_" + $Stamp + ".json")
$PromptPath = Join-Path $ContextRoot ("context_prompt_" + $Stamp + ".txt")

$Packet = [ordered]@{
  schema = "pie.context.packet.v2"
  session_id = $SessionId
  goal = $Goal
  language = $Language
  language_version = $LanguageVersion
  project_repo = $ProjectRepo
  has_repo_scan = -not [string]::IsNullOrWhiteSpace($RepoScan)
  has_repo_memory = -not [string]::IsNullOrWhiteSpace($RepoMemory)
  linked_repo_count = $LinkedRepoCount
  has_policy_summary = -not [string]::IsNullOrWhiteSpace($PolicySummary)
  user_message = $UserMessage
  created_utc = [DateTime]::UtcNow.ToString("o")
}

$LinkedReposJoined = $LinkedRepoText.ToArray() -join "`n"

$Prompt = @"
PIE GOVERNED CONTEXT PACKET v2

ROLE:
You are PIE, a local-first governed AI runtime.
You are assistant-only, not executor.
You must use deterministic repo facts before model guesses.
Do not invent repo identity, files, WBS docs, specs, schemas, or commands.
If repo scan facts say what the repo is, that identity is authoritative.
If facts are missing, say what is missing.
When multiple repos are present, keep their facts separated and label which repo each claim comes from.
IMPORTANT PATH RULE:
- Copy Windows paths exactly as provided.
- Never shorten, normalize, infer, or rewrite paths.
- If the context says C:\dev\nfl, you must write C:\dev\nfl exactly, not C:\dev\fl.
- If the user enters a shell command inside chat, explain that shell commands must be run in PowerShell, not treated as a normal chat request.

SESSION GOAL:
$Goal

LANGUAGE / RUNTIME:
$Language
$LanguageVersion

PRIMARY PROJECT REPO:
$ProjectRepo

PIE POLICY SUMMARY:
$PolicySummary

PRIMARY REPO MEMORY:
$RepoMemory

PRIMARY REPO SCAN ARTIFACT:
$RepoScan

LINKED REPO CONTEXT:
$LinkedReposJoined

USER MESSAGE:
$UserMessage
"@

Write-Utf8NoBomLf -Path $PacketPath -Text ($Packet | ConvertTo-Json -Depth 12)
Write-Utf8NoBomLf -Path $PromptPath -Text $Prompt

Write-Host ("PIE_CONTEXT_BUILD_OK: " + $PromptPath) -ForegroundColor Green


