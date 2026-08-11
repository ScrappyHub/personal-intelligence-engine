param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$SessionId,
  [Parameter(Mandatory=$false)][string]$UserMessage = "",
  [Parameter(Mandatory=$false)][string]$UserMessagePath = "",
  [Parameter(Mandatory=$false)][string]$MemoryRoot = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $RepoRoot "scripts\_lib_pie_agent_session_v1.ps1")
$Session = PIE_GetAgentSession -RepoRoot $RepoRoot -SessionId $SessionId -RequireRunning -RequireIntegrity
$RunRoot = $Session.run_root
$Enc = New-Object System.Text.UTF8Encoding($false)

if(-not [string]::IsNullOrWhiteSpace($UserMessagePath)){
  if(-not (Test-Path -LiteralPath $UserMessagePath -PathType Leaf)){ throw ("PIE_CONTEXT_USER_MESSAGE_PATH_NOT_FOUND: " + $UserMessagePath) }
  $UserMessage = [System.IO.File]::ReadAllText($UserMessagePath,$Enc)
}
if([string]::IsNullOrWhiteSpace($UserMessage)){ throw "PIE_CONTEXT_USER_MESSAGE_REQUIRED" }

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
    return (PIE_ReadUtf8Text -Path $Path).Trim()
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

function Limit-ContextText {
  param(
    [AllowEmptyString()][string]$Text,
    [Parameter(Mandatory=$true)][int]$Limit
  )
  if($null -eq $Text){ return "" }
  if($Text.Length -le $Limit){ return $Text.Trim() }
  return ($Text.Substring(0,$Limit).Trim() + "`n[truncated]")
}

function Get-DeterministicRepoFacts {
  param([Parameter(Mandatory=$true)][string]$TargetRepo)

  $Facts = New-Object System.Collections.Generic.List[string]
  [void]$Facts.Add("repo=" + $TargetRepo)
  $ProjectId = ""

  $ContractPath = Join-Path $TargetRepo "project.contract.json"
  if(Test-Path -LiteralPath $ContractPath -PathType Leaf){
    try { $ProjectId = [string]((Get-Content -LiteralPath $ContractPath -Raw | ConvertFrom-Json).project_id) } catch { throw ("PIE_CONTEXT_PROJECT_CONTRACT_INVALID: " + $ContractPath) }
    [void]$Facts.Add("`nPROJECT CONTRACT:")
    [void]$Facts.Add((Limit-ContextText -Text (Get-Content -LiteralPath $ContractPath -Raw) -Limit 1600))
  }

  foreach($CanonicalName in @("IDENTITY.md","CURRENT_STATE.md","SPEC.md")){
    $CanonicalPath = Join-Path $TargetRepo ("docs\canonical\" + $CanonicalName)
    if(Test-Path -LiteralPath $CanonicalPath -PathType Leaf){
      [void]$Facts.Add("`nCANONICAL " + $CanonicalName + " EXCERPT:")
      [void]$Facts.Add((Limit-ContextText -Text (Get-Content -LiteralPath $CanonicalPath -Raw) -Limit 2200))
    }
  }

  $ReadmePath = Join-Path $TargetRepo "README.md"
  if(Test-Path -LiteralPath $ReadmePath -PathType Leaf){
    [void]$Facts.Add("`nREADME EXCERPT:")
    [void]$Facts.Add((Limit-ContextText -Text (Get-Content -LiteralPath $ReadmePath -Raw) -Limit 2200))
  }

  [void]$Facts.Add("`nTOP-LEVEL INVENTORY:")
  foreach($Item in @(Get-ChildItem -LiteralPath $TargetRepo -Force -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -notin @(".git","runs","proofs") } |
      Sort-Object Name |
      Select-Object -First 80)){
    $Kind = $(if($Item.PSIsContainer){ "dir" } else { "file" })
    [void]$Facts.Add("[" + $Kind + "] " + $Item.Name)
  }

  $ScriptsPath = Join-Path $TargetRepo "scripts"
  if(Test-Path -LiteralPath $ScriptsPath -PathType Container){
    if($ProjectId -eq "pie"){
      [void]$Facts.Add("`nIMPLEMENTED PIE CAPABILITY EVIDENCE:")
      $CapabilityGroups = [ordered]@{
        memory = @("pie_memory_accept_v1.ps1","pie_memory_forget_v1.ps1","pie_memory_policy_v1.ps1","pie_memory_query_v1.ps1","pie_memory_resolve_v1.ps1","selftest_pie_memory_lifecycle_v1.ps1","selftest_pie_memory_negative_v1.ps1","selftest_pie_memory_resolve_v1.ps1")
        local_models = @("pie_models_v1.ps1","pie_runtime_v1.ps1","pie_backend_ollama_cmd_v1.ps1","selftest_pie_local_models_v1.ps1")
        governed_agent = @("pie_agent_start_v1.ps1","pie_agent_send_v1.ps1","pie_exec_policy_v1.ps1","pie_exec_with_snapshot_v1.ps1","selftest_pie_agent_workflow_v1.ps1")
        cloud_integrations = @("pie_integrations_v1.ps1","selftest_pie_integrations_v1.ps1")
        governance_audit = @("GOVERNANCE_GREEN_RUNNER_PIE_v1.ps1","pie_green_audit_v1.ps1","pie_policy_decide_v1.ps1","pie_reason_trace_v1.ps1","pie_execution_replay_v1.ps1")
        traceability = @("pie_exec_with_snapshot_v1.ps1","pie_state_snapshot_v1.ps1","pie_green_terminal_receipt_v1.ps1","pie_run_packet_sign_v1.ps1")
      }
      foreach($CapabilityName in $CapabilityGroups.Keys){
        $Present = @($CapabilityGroups[$CapabilityName] | Where-Object { Test-Path -LiteralPath (Join-Path $ScriptsPath $_) -PathType Leaf })
        $State = $(if($Present.Count -eq $CapabilityGroups[$CapabilityName].Count){ "implemented" } else { "partial" })
        [void]$Facts.Add($CapabilityName + "=" + $State + " evidence=" + ($Present -join ","))
      }
    }

    [void]$Facts.Add("`nSCRIPT INVENTORY:")
    foreach($ScriptFile in @(Get-ChildItem -LiteralPath $ScriptsPath -File -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -First 60)){
      [void]$Facts.Add($ScriptFile.Name)
    }
  }

  if($null -ne (Get-Command git -ErrorAction SilentlyContinue)){
    $PreviousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
      $GitStatus = @(& git -C $TargetRepo status --short --branch 2>$null) -join "`n"
      if($LASTEXITCODE -eq 0){
        [void]$Facts.Add("`nGIT STATUS:")
        [void]$Facts.Add((Limit-ContextText -Text $GitStatus -Limit 2200))
      }
      $GitDiffStat = @(& git -C $TargetRepo diff --stat 2>$null) -join "`n"
      if($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($GitDiffStat)){
        [void]$Facts.Add("`nGIT DIFF STAT:")
        [void]$Facts.Add((Limit-ContextText -Text $GitDiffStat -Limit 1800))
      }
    }
    finally { $ErrorActionPreference = $PreviousErrorActionPreference }
  }

  return (Limit-ContextText -Text ($Facts.ToArray() -join "`n") -Limit 9000)
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

$Goal = $Session.goal
$Language = Read-TextIfExists -Path (Join-Path $RunRoot "language.txt")
$LanguageVersion = Read-TextIfExists -Path (Join-Path $RunRoot "language_version.txt")
$ProjectRepo = $Session.project_repo
$LinksPath = Join-Path $RunRoot "repo_links.ndjson"

$RepoScan = ""
$RepoMemory = ""
$RepoFacts = ""

if(-not [string]::IsNullOrWhiteSpace($ProjectRepo)){
  if(Test-Path -LiteralPath $ProjectRepo -PathType Container){
    $ProjectRepo = (Resolve-Path -LiteralPath $ProjectRepo).Path
    $RepoScan = Get-LatestRepoScanText -TargetRepo $ProjectRepo
    $RepoMemory = Get-RepoMemoryText -TargetRepo $ProjectRepo
    $RepoFacts = Get-DeterministicRepoFacts -TargetRepo $ProjectRepo
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
    catch { throw ("PIE_CONTEXT_REPO_LINK_INVALID: " + $LinksPath + " :: " + $_.Exception.Message) }
  }
}

$PolicySummary = Get-PolicySummary -RepoRoot $RepoRoot
$MemoryResolution = ""

$MemoryResolveScript = Join-Path $RepoRoot "scripts\pie_memory_resolve_v1.ps1"
if(Test-Path -LiteralPath $MemoryResolveScript -PathType Leaf){
  try {
    $MemoryQueryPath = $UserMessagePath
    if([string]::IsNullOrWhiteSpace($MemoryQueryPath)){
      $MemoryQueryPath = Join-Path $RunRoot ("context_inputs\query_" + (Get-Date -Format "yyyyMMdd_HHmmss_fff") + ".txt")
      Write-Utf8NoBomLf -Path $MemoryQueryPath -Text $UserMessage
    }
    $ResolveArgs = @(
      "-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass",
      "-File",$MemoryResolveScript,
      "-RepoRoot",$RepoRoot,
      "-SessionId",$SessionId,
      "-QueryPath",$MemoryQueryPath
    )
    if(-not [string]::IsNullOrWhiteSpace($MemoryRoot)){ $ResolveArgs += @("-MemoryRoot",$MemoryRoot) }
    $ResolveOut = @(& powershell.exe @ResolveArgs) -join "`n"
    if($LASTEXITCODE -ne 0){ throw ("PIE_MEMORY_RESOLVER_EXIT_" + [string]$LASTEXITCODE + " :: " + $ResolveOut) }

    $MemoryLatest = Join-Path $RunRoot "memory_resolve\latest_memory_resolution.md"
    if(Test-Path -LiteralPath $MemoryLatest -PathType Leaf){
      $MemoryResolution = Get-Content -LiteralPath $MemoryLatest -Raw
      if($MemoryResolution.Length -gt 10000){
        $MemoryResolution = $MemoryResolution.Substring(0,10000) + "`n`n[memory resolution truncated]"
      }
    }
  }
  catch {
    throw ("PIE_CONTEXT_MEMORY_RESOLUTION_FAIL: " + $_.Exception.Message)
  }
} else {
  throw "PIE_CONTEXT_MEMORY_RESOLVER_MISSING"
}

$ContextRoot = Join-Path $RunRoot "context_packets"
$Stamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
$PacketPath = Join-Path $ContextRoot ("context_packet_" + $Stamp + ".json")
$PromptPath = Join-Path $ContextRoot ("context_prompt_" + $Stamp + ".txt")
$HasResolvedMemory = $MemoryResolution -match '(?m)^## Resolved Personal Memory$'

$Packet = [ordered]@{
  schema = "pie.context.packet.v2"
  session_id = $SessionId
  goal = $Goal
  language = $Language
  language_version = $LanguageVersion
  project_repo = $ProjectRepo
  has_repo_scan = -not [string]::IsNullOrWhiteSpace($RepoScan)
  has_repo_facts = -not [string]::IsNullOrWhiteSpace($RepoFacts)
  has_repo_memory = -not [string]::IsNullOrWhiteSpace($RepoMemory)
  has_resolved_memory = $HasResolvedMemory
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
Never claim to be Qwen, GPT, OpenAI, Alibaba, Claude, Grok, or an external hosted assistant. The underlying language model is local; PIE is the runtime, memory, and verification layer around it.
Do only what the user asked. Do not add features, files, scaffolding, or scope the user did not request; if something extra seems worthwhile, offer it briefly and let the user decide.
Behave identically whether PIE is self-hosted locally or served from a hosted API gateway. Hosting must not change your identity, honesty, or scope discipline.
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

RESOLVED PERSONAL MEMORY:
$MemoryResolution

PRIMARY REPO SCAN ARTIFACT:
$RepoScan

LINKED REPO CONTEXT:
$LinkedReposJoined

CURRENT DETERMINISTIC REPOSITORY FACTS (AUTHORITATIVE FOR THIS ANSWER):
$RepoFacts

USER MESSAGE:
$UserMessage

ANSWER GROUNDING RULES:
- Current deterministic repository facts outrank prior conversation and model assumptions.
- For repository questions, cite concrete filenames, scripts, or contract fields from those facts.
- Do not repeat recommendations from prior answers unless current facts support them.
- When asked for a priority gap, choose from VERIFIED CURRENT GAPS and cite its evidence.
- If facts are insufficient, state exactly which fact is missing instead of giving generic advice.
"@

Write-Utf8NoBomLf -Path $PacketPath -Text ($Packet | ConvertTo-Json -Depth 12)
Write-Utf8NoBomLf -Path $PromptPath -Text $Prompt

Write-Host ("PIE_CONTEXT_BUILD_OK: " + $PromptPath) -ForegroundColor Green
