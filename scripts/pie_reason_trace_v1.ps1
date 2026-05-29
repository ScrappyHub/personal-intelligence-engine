param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$SessionId,
  [Parameter(Mandatory=$true)][string]$Goal,
  [Parameter(Mandatory=$false)][string]$SelectedCommand = "",
  [Parameter(Mandatory=$false)][string]$WorkingDirectory = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)
$TraceRoot = Join-Path $RunRoot "reason_traces"
$Enc = New-Object System.Text.UTF8Encoding($false)

function Write-Utf8NoBomLf {
  param([string]$Path,[string]$Text)
  $Dir = Split-Path -Parent $Path
  if(-not (Test-Path -LiteralPath $Dir -PathType Container)){ New-Item -ItemType Directory -Force -Path $Dir | Out-Null }
  $Clean = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $Clean.EndsWith("`n")){ $Clean += "`n" }
  [System.IO.File]::WriteAllText($Path,$Clean,$Enc)
}

function Read-IfExists {
  param([string]$Path)
  if(Test-Path -LiteralPath $Path -PathType Leaf){
    return (Get-Content -LiteralPath $Path -Raw).Trim()
  }
  return ""
}

if(-not (Test-Path -LiteralPath $RunRoot -PathType Container)){
  throw ("PIE_REASON_TRACE_SESSION_NOT_FOUND: " + $SessionId)
}

$ProjectRepo = Read-IfExists (Join-Path $RunRoot "project_repo.txt")
if([string]::IsNullOrWhiteSpace($WorkingDirectory)){
  $WorkingDirectory = $ProjectRepo
}
if([string]::IsNullOrWhiteSpace($WorkingDirectory)){
  $WorkingDirectory = $RepoRoot
}

$ContextLatest = Join-Path $RunRoot "context_packets"
$MemoryLatest = Join-Path $RunRoot "memory_resolve\latest_memory_resolution.md"
$RankLatest = Join-Path $RunRoot "context_rank\latest_context_rank.json"

$ContextRefs = New-Object System.Collections.Generic.List[string]
if(Test-Path -LiteralPath $ContextLatest -PathType Container){
  $LatestContext = Get-ChildItem -LiteralPath $ContextLatest -File -Filter "context_prompt_*.txt" -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending |
    Select-Object -First 1
  if($null -ne $LatestContext){ [void]$ContextRefs.Add($LatestContext.FullName) }
}

$MemoryRefs = New-Object System.Collections.Generic.List[string]
if(Test-Path -LiteralPath $MemoryLatest -PathType Leaf){ [void]$MemoryRefs.Add($MemoryLatest) }
if(Test-Path -LiteralPath $RankLatest -PathType Leaf){ [void]$MemoryRefs.Add($RankLatest) }

$Constraints = @(
  "models suggest; runtime decides",
  "do not execute without policy evaluation",
  "mutating actions require confirmation unless policy auto-confirm allows low-risk class",
  "respect session repo boundary",
  "write deterministic receipts for execution-capable decisions",
  "never treat LLM response as authority"
)

$CandidateActions = New-Object System.Collections.Generic.List[object]

[void]$CandidateActions.Add([pscustomobject][ordered]@{
  action_id = "answer_only"
  kind = "response"
  command = ""
  risk = "none"
  reason = "No execution required."
})

if(-not [string]::IsNullOrWhiteSpace($SelectedCommand)){
  [void]$CandidateActions.Add([pscustomobject][ordered]@{
    action_id = "execute_selected_command"
    kind = "execution"
    command = $SelectedCommand
    risk = "policy_evaluated"
    reason = "User/runtime provided a selected command for governed execution."
  })
}

$SelectedAction = [ordered]@{
  action_id = "answer_only"
  kind = "response"
  command = ""
  requires_execution = $false
}

$RejectedActions = New-Object System.Collections.Generic.List[object]
$PolicyObj = [ordered]@{
  schema = "pie.exec.policy.decision.inline.v1"
  decision = "NOT_APPLICABLE"
  reason_code = "NO_COMMAND_SELECTED"
}

if(-not [string]::IsNullOrWhiteSpace($SelectedCommand)){
  $PolicyScript = Join-Path $RepoRoot "scripts\pie_exec_policy_v1.ps1"

  if(-not (Test-Path -LiteralPath $PolicyScript -PathType Leaf)){
    throw ("PIE_REASON_TRACE_POLICY_SCRIPT_MISSING: " + $PolicyScript)
  }

  $PolicyJson = @(
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
      -File $PolicyScript `
      -RepoRoot $RepoRoot `
      -Command $SelectedCommand `
      -WorkingDirectory $WorkingDirectory `
      -SessionProjectRepo $ProjectRepo
  ) -join "`n"

  if($LASTEXITCODE -ne 0){
    throw "PIE_REASON_TRACE_POLICY_EVAL_FAIL"
  }

  $PolicyObj = $PolicyJson | ConvertFrom-Json

  if([string]$PolicyObj.decision -eq "DENY"){
    $SelectedAction = [ordered]@{
      action_id = "deny_selected_command"
      kind = "deny"
      command = $SelectedCommand
      requires_execution = $false
    }
  }
  else {
    $SelectedAction = [ordered]@{
      action_id = "execute_selected_command"
      kind = "execution"
      command = $SelectedCommand
      requires_execution = $true
      requires_confirmation = $([string]$PolicyObj.decision -eq "ASK_CONFIRMATION")
      auto_confirm_allowed = [bool]$PolicyObj.auto_confirm_allowed
    }
  }

  [void]$RejectedActions.Add([pscustomobject][ordered]@{
    action_id = "execute_without_policy"
    kind = "execution"
    command = $SelectedCommand
    rejected_reason = "Execution without policy evaluation is forbidden."
  })
}

$Trace = [ordered]@{
  schema = "pie.reason.trace.v1"
  session_id = $SessionId
  goal = $Goal
  context_refs = $ContextRefs.ToArray()
  memory_refs = $MemoryRefs.ToArray()
  constraints = $Constraints
  candidate_actions = $CandidateActions.ToArray()
  selected_action = $SelectedAction
  rejected_actions = $RejectedActions.ToArray()
  policy_result = $PolicyObj
  created_utc = [DateTime]::UtcNow.ToString("o")
}

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
$OutPath = Join-Path $TraceRoot ("reason_trace_" + $Stamp + ".json")
$LatestPath = Join-Path $TraceRoot "latest_reason_trace.json"

$Json = $Trace | ConvertTo-Json -Depth 40
Write-Utf8NoBomLf -Path $OutPath -Text $Json
Write-Utf8NoBomLf -Path $LatestPath -Text $Json

Write-Host ("PIE_REASON_TRACE_OK: " + $OutPath) -ForegroundColor Green
