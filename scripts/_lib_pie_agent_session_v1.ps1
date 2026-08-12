Set-StrictMode -Version Latest

function PIE_GetSessionProperty {
  param(
    [Parameter(Mandatory=$true)][object]$Object,
    [Parameter(Mandatory=$true)][string]$Name
  )

  $Property = $Object.PSObject.Properties[$Name]
  if($null -eq $Property){ return $null }
  return $Property.Value
}

function PIE_Sha256Text {
  param([Parameter(Mandatory=$true)][AllowEmptyString()][string]$Text)

  $Bytes = [System.Text.Encoding]::UTF8.GetBytes($Text.Replace("`r`n","`n").Replace("`r","`n"))
  $Sha = [System.Security.Cryptography.SHA256]::Create()
  try { $Hash = $Sha.ComputeHash($Bytes) } finally { $Sha.Dispose() }
  return (($Hash | ForEach-Object { $_.ToString("x2") }) -join "")
}

function PIE_ReadUtf8Text {
  param([Parameter(Mandatory=$true)][string]$Path)
  $Stream = $null
  $Reader = $null
  try {
    $Stream = [System.IO.File]::Open($Path,[System.IO.FileMode]::Open,[System.IO.FileAccess]::Read,[System.IO.FileShare]::ReadWrite)
    $Reader = New-Object System.IO.StreamReader($Stream,(New-Object System.Text.UTF8Encoding($false,$true)),$true)
    return $Reader.ReadToEnd()
  }
  catch { throw ("PIE_UTF8_READ_FAILED: " + $Path + " :: " + $_.Exception.Message) }
  finally {
    if($null -ne $Reader){ $Reader.Dispose() }
    elseif($null -ne $Stream){ $Stream.Dispose() }
  }
}

function PIE_SessionBindingHash {
  param(
    [Parameter(Mandatory=$true)][string]$SessionId,
    [Parameter(Mandatory=$true)][string]$Backend,
    [Parameter(Mandatory=$true)][string]$Model,
    [Parameter(Mandatory=$true)][AllowEmptyString()][string]$ProjectRepo,
    [Parameter(Mandatory=$true)][AllowEmptyString()][string]$Goal
  )

  $Canonical = @($SessionId,$Backend,$Model,$ProjectRepo,$Goal) | ForEach-Object {
    ([string]$_).Replace("`r`n","`n").Replace("`r","`n").Trim()
  }
  return PIE_Sha256Text -Text ($Canonical -join "`n")
}

function PIE_ProjectIdentityHash {
  param([Parameter(Mandatory=$true)][AllowEmptyString()][string]$ProjectRepo)
  if([string]::IsNullOrWhiteSpace($ProjectRepo)){ return PIE_Sha256Text -Text "unbound-project" }
  if(-not (Test-Path -LiteralPath $ProjectRepo -PathType Container)){ throw ("PIE_AGENT_PROJECT_REPO_MISSING: " + $ProjectRepo) }
  $Resolved = (Resolve-Path -LiteralPath $ProjectRepo).Path
  $Facts = New-Object System.Collections.Generic.List[string]
  [void]$Facts.Add("path=" + $Resolved.ToLowerInvariant())
  $Git = Get-Command git -ErrorAction SilentlyContinue
  if($null -ne $Git){
    $PreviousErrorAction = $ErrorActionPreference
    try {
      # Git may reject a readable repository owned by another Windows account.
      # Treat Git metadata as optional identity evidence instead of losing the path binding.
      $ErrorActionPreference = "SilentlyContinue"
      $Top = @(& $Git.Source -C $Resolved rev-parse --show-toplevel 2>$null) -join "`n"
      $TopExitCode = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $PreviousErrorAction }
    if($TopExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($Top)){
      [void]$Facts.Add("git_top=" + ([System.IO.Path]::GetFullPath($Top.Trim())).ToLowerInvariant())
      try {
        $ErrorActionPreference = "SilentlyContinue"
        $Roots = @(& $Git.Source -C $Resolved rev-list --max-parents=0 HEAD 2>$null | Sort-Object)
        $RootsExitCode = $LASTEXITCODE
        $Remote = @(& $Git.Source -C $Resolved remote get-url origin 2>$null) -join "`n"
        $RemoteExitCode = $LASTEXITCODE
      }
      finally { $ErrorActionPreference = $PreviousErrorAction }
      if($RootsExitCode -eq 0){ [void]$Facts.Add("git_roots=" + ($Roots -join ",")) }
      if($RemoteExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($Remote)){ [void]$Facts.Add("git_origin=" + $Remote.Trim()) }
    }
  }
  foreach($IdentityFile in @("project.contract.json",".pie\profile.json")){
    $IdentityPath = Join-Path $Resolved $IdentityFile
    if(Test-Path -LiteralPath $IdentityPath -PathType Leaf){
      try {
        $Identity = PIE_ReadUtf8Text -Path $IdentityPath | ConvertFrom-Json
        foreach($Name in @("project_id","canonical_name","project","service_id")){
          $Value = [string](PIE_GetSessionProperty -Object $Identity -Name $Name)
          if(-not [string]::IsNullOrWhiteSpace($Value)){ [void]$Facts.Add($IdentityFile + ":" + $Name + "=" + $Value) }
        }
      }
      catch { throw ("PIE_AGENT_PROJECT_IDENTITY_INVALID: " + $IdentityPath + " :: " + $_.Exception.Message) }
    }
  }
  return PIE_Sha256Text -Text ($Facts.ToArray() -join "`n")
}

function PIE_CurrentModelIdentityHash {
  param(
    [Parameter(Mandatory=$true)][string]$Backend,
    [Parameter(Mandatory=$true)][string]$Model
  )
  if($Backend -ne "ollama"){ return PIE_Sha256Text -Text ($Backend + "`n" + $Model) }
  try { $Tags = Invoke-RestMethod -Method Get -Uri "http://127.0.0.1:11434/api/tags" -TimeoutSec 10 }
  catch { throw ("PIE_AGENT_MODEL_REGISTRY_UNAVAILABLE: " + $_.Exception.Message) }
  $Match = @($Tags.models | Where-Object { [string]$_.name -ieq $Model } | Select-Object -First 1)
  if($Match.Count -ne 1){ throw ("PIE_AGENT_MODEL_NOT_LOCAL: " + $Model) }
  $Digest = [string]$Match[0].digest
  if([string]::IsNullOrWhiteSpace($Digest)){ throw ("PIE_AGENT_MODEL_DIGEST_MISSING: " + $Model) }
  return PIE_Sha256Text -Text ("ollama`n" + $Model + "`n" + $Digest)
}

function PIE_VerifySessionModelIdentity {
  param([Parameter(Mandatory=$true)][object]$Session)
  $Stored = [string]$Session.model_identity_sha256
  if([string]::IsNullOrWhiteSpace($Stored)){ return }
  $Current = PIE_CurrentModelIdentityHash -Backend ([string]$Session.backend) -Model ([string]$Session.model)
  if($Current -ne $Stored){ throw ("PIE_AGENT_MODEL_IDENTITY_DRIFT: " + [string]$Session.session_id + " model=" + [string]$Session.model) }
}

function PIE_ConversationTurnHash {
  param(
    [Parameter(Mandatory=$true)][string]$SessionId,
    [Parameter(Mandatory=$true)][string]$BindingHash,
    [Parameter(Mandatory=$true)][int]$TurnIndex,
    [Parameter(Mandatory=$true)][AllowEmptyString()][string]$PreviousTurnHash,
    [Parameter(Mandatory=$true)][string]$Timestamp,
    [Parameter(Mandatory=$true)][AllowEmptyString()][string]$PromptPath,
    [Parameter(Mandatory=$true)][string]$Message,
    [Parameter(Mandatory=$true)][string]$Response,
    [Parameter(Mandatory=$true)][int]$GroundingCorrectionCount
  )

  $Canonical = @(
    "pie.conversation.turn.v2",$SessionId,$BindingHash,[string]$TurnIndex,$PreviousTurnHash,
    $Timestamp,$PromptPath,$Message,$Response,[string]$GroundingCorrectionCount
  ) | ForEach-Object { ([string]$_).Replace("`r`n","`n").Replace("`r","`n") }
  return PIE_Sha256Text -Text ($Canonical -join "`n")
}

function PIE_WriteAtomicText {
  param(
    [Parameter(Mandatory=$true)][string]$Path,
    [Parameter(Mandatory=$true)][AllowEmptyString()][string]$Text
  )
  $Directory = Split-Path -Parent $Path
  if(-not (Test-Path -LiteralPath $Directory -PathType Container)){ New-Item -ItemType Directory -Force -Path $Directory | Out-Null }
  $Temporary = $Path + ".pie-tmp-" + [Guid]::NewGuid().ToString("N")
  $Enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Temporary,$Text,$Enc)
  try { Move-Item -LiteralPath $Temporary -Destination $Path -Force }
  finally { if(Test-Path -LiteralPath $Temporary -PathType Leaf){ Remove-Item -LiteralPath $Temporary -Force } }
}

function PIE_AcquireSessionLock {
  param([Parameter(Mandatory=$true)][string]$RunRoot)
  if(-not (Test-Path -LiteralPath $RunRoot -PathType Container)){ throw ("PIE_AGENT_SESSION_NOT_FOUND: " + (Split-Path -Leaf $RunRoot)) }
  $StateRoot = Join-Path $RunRoot "state"
  if(-not (Test-Path -LiteralPath $StateRoot -PathType Container)){ New-Item -ItemType Directory -Force -Path $StateRoot | Out-Null }
  try {
    return [System.IO.File]::Open((Join-Path $StateRoot "session-operation.lock"),[System.IO.FileMode]::OpenOrCreate,[System.IO.FileAccess]::ReadWrite,[System.IO.FileShare]::None)
  }
  catch { throw ("PIE_AGENT_SESSION_BUSY: " + (Split-Path -Leaf $RunRoot)) }
}

function PIE_WriteSessionPair {
  param(
    [Parameter(Mandatory=$true)][string]$RunRoot,
    [Parameter(Mandatory=$true)][string]$SessionId,
    [Parameter(Mandatory=$true)][object]$State,
    [Parameter(Mandatory=$true)][object]$Manifest,
    [Parameter(Mandatory=$true)][string]$Event
  )
  $StatePath = Join-Path $RunRoot "state\session.state.json"
  $ManifestPath = Join-Path $RunRoot "session_manifest.json"
  $PendingPath = Join-Path $RunRoot "state\pending-transition.json"
  $StateText = ($State | ConvertTo-Json -Depth 12) + "`n"
  $ManifestText = ($Manifest | ConvertTo-Json -Depth 12) + "`n"
  $Transition = [ordered]@{
    schema="pie.session.transition.v1"; event=$Event; session_id=$SessionId
    binding_sha256=[string](PIE_GetSessionProperty -Object $Manifest -Name "binding_sha256")
    state_sha256=(PIE_Sha256Text -Text $StateText); manifest_sha256=(PIE_Sha256Text -Text $ManifestText)
    state_json=$StateText; manifest_json=$ManifestText; created_utc=[DateTime]::UtcNow.ToString("o")
  }
  PIE_WriteAtomicText -Path $PendingPath -Text (($Transition | ConvertTo-Json -Depth 12) + "`n")
  PIE_WriteAtomicText -Path $StatePath -Text $StateText
  if($env:PIE_FAULT_AFTER_SESSION_STATE_WRITE -eq "1"){ throw "PIE_FAULT_INJECTED_AFTER_SESSION_STATE_WRITE" }
  PIE_WriteAtomicText -Path $ManifestPath -Text $ManifestText
  if((PIE_Sha256Text -Text (PIE_ReadUtf8Text -Path $StatePath)) -ne $Transition.state_sha256 -or `
     (PIE_Sha256Text -Text (PIE_ReadUtf8Text -Path $ManifestPath)) -ne $Transition.manifest_sha256){
    throw ("PIE_AGENT_SESSION_TRANSITION_VERIFY_FAILED: " + $SessionId)
  }
  $Receipt = [ordered]@{schema="pie.session.transition.receipt.v1";event=$Event;session_id=$SessionId;binding_sha256=$Transition.binding_sha256;state_sha256=$Transition.state_sha256;manifest_sha256=$Transition.manifest_sha256;recovered=$false;committed_utc=[DateTime]::UtcNow.ToString("o")}
  [System.IO.File]::AppendAllText((Join-Path $RunRoot "session_transitions.ndjson"),(($Receipt | ConvertTo-Json -Compress) + "`n"),(New-Object System.Text.UTF8Encoding($false)))
  Remove-Item -LiteralPath $PendingPath -Force
}

function PIE_RecoverSessionTransition {
  param([Parameter(Mandatory=$true)][string]$RunRoot,[Parameter(Mandatory=$true)][string]$SessionId)
  $PendingPath = Join-Path $RunRoot "state\pending-transition.json"
  if(-not (Test-Path -LiteralPath $PendingPath -PathType Leaf)){ return }
  $RecoveryLock = $null
  try { $RecoveryLock = [System.IO.File]::Open((Join-Path $RunRoot "state\transition-recovery.lock"),[System.IO.FileMode]::OpenOrCreate,[System.IO.FileAccess]::ReadWrite,[System.IO.FileShare]::None) }
  catch { throw ("PIE_AGENT_SESSION_RECOVERY_BUSY: " + $SessionId) }
  try {
    if(-not (Test-Path -LiteralPath $PendingPath -PathType Leaf)){ return }
  try { $Transition = PIE_ReadUtf8Text -Path $PendingPath | ConvertFrom-Json }
  catch { throw ("PIE_AGENT_SESSION_TRANSITION_INVALID: " + $SessionId + " :: " + $_.Exception.Message) }
  if([string]$Transition.schema -ne "pie.session.transition.v1" -or [string]$Transition.session_id -ne $SessionId){ throw ("PIE_AGENT_SESSION_TRANSITION_SCHEMA_BAD: " + $SessionId) }
  $StateText = [string]$Transition.state_json
  $ManifestText = [string]$Transition.manifest_json
  if((PIE_Sha256Text -Text $StateText) -ne [string]$Transition.state_sha256 -or (PIE_Sha256Text -Text $ManifestText) -ne [string]$Transition.manifest_sha256){
    throw ("PIE_AGENT_SESSION_TRANSITION_HASH_MISMATCH: " + $SessionId)
  }
  PIE_WriteAtomicText -Path (Join-Path $RunRoot "state\session.state.json") -Text $StateText
  PIE_WriteAtomicText -Path (Join-Path $RunRoot "session_manifest.json") -Text $ManifestText
  $Receipt = [ordered]@{schema="pie.session.transition.receipt.v1";event=[string]$Transition.event;session_id=$SessionId;binding_sha256=[string]$Transition.binding_sha256;state_sha256=[string]$Transition.state_sha256;manifest_sha256=[string]$Transition.manifest_sha256;recovered=$true;committed_utc=[DateTime]::UtcNow.ToString("o")}
  [System.IO.File]::AppendAllText((Join-Path $RunRoot "session_transitions.ndjson"),(($Receipt | ConvertTo-Json -Compress) + "`n"),(New-Object System.Text.UTF8Encoding($false)))
  Remove-Item -LiteralPath $PendingPath -Force
  }
  finally { if($null -ne $RecoveryLock){ $RecoveryLock.Dispose() } }
}

function PIE_TurnAppendTargets {
  param([Parameter(Mandatory=$true)][string]$RunRoot)
  return @((Join-Path $RunRoot "conversation.ndjson"), (Join-Path $RunRoot "transcript.ndjson"))
}

# Last complete turn_sha256 in an ndjson file, tolerating a torn trailing line (interrupted append).
function PIE_LastTurnInfo {
  param([Parameter(Mandatory=$true)][string]$Path)
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ return [pscustomobject]@{ hash=""; torn=$false } }
  $Enc = New-Object System.Text.UTF8Encoding($false)
  $Raw = [System.IO.File]::ReadAllText($Path,$Enc)
  if([string]::IsNullOrEmpty($Raw)){ return [pscustomobject]@{ hash=""; torn=$false } }
  $Torn = -not $Raw.EndsWith("`n")
  $Lines = @($Raw -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  $Hash = ""
  for($i=$Lines.Count-1; $i -ge 0; $i--){
    try { $Obj = $Lines[$i] | ConvertFrom-Json; $H=[string](PIE_GetSessionProperty -Object $Obj -Name "turn_sha256"); if(-not [string]::IsNullOrWhiteSpace($H)){ $Hash=$H; break } } catch { }
  }
  return [pscustomobject]@{ hash=$Hash; torn=$Torn }
}

# Trim a torn (non-newline-terminated) trailing line so a clean append can follow.
function PIE_TrimTornTail {
  param([Parameter(Mandatory=$true)][string]$Path)
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ return }
  $Enc = New-Object System.Text.UTF8Encoding($false)
  $Raw = [System.IO.File]::ReadAllText($Path,$Enc)
  if([string]::IsNullOrEmpty($Raw) -or $Raw.EndsWith("`n")){ return }
  $Idx = $Raw.LastIndexOf("`n")
  $Trimmed = $(if($Idx -ge 0){ $Raw.Substring(0,$Idx+1) } else { "" })
  PIE_WriteAtomicText -Path $Path -Text $Trimmed
}

# Crash-safe dual append of a conversation turn to conversation.ndjson + transcript.ndjson.
# A pending-turn journal is written first (the commit point); recovery rolls forward from it so both
# files always end with the same committed turn. Happy-path bytes are identical to a plain append.
function PIE_AppendTurnPair {
  param(
    [Parameter(Mandatory=$true)][string]$RunRoot,
    [Parameter(Mandatory=$true)][string]$SessionId,
    [Parameter(Mandatory=$true)][string]$Line,
    [Parameter(Mandatory=$true)][string]$TurnHash
  )
  $StateRoot = Join-Path $RunRoot "state"
  if(-not (Test-Path -LiteralPath $StateRoot -PathType Container)){ New-Item -ItemType Directory -Force -Path $StateRoot | Out-Null }
  $PendingPath = Join-Path $StateRoot "pending-turn.json"
  $Targets = PIE_TurnAppendTargets -RunRoot $RunRoot
  $Journal = [ordered]@{ schema="pie.session.turn.pending.v1"; session_id=$SessionId; turn_sha256=$TurnHash; line=$Line; targets=$Targets; created_utc=[DateTime]::UtcNow.ToString("o") }
  PIE_WriteAtomicText -Path $PendingPath -Text (($Journal | ConvertTo-Json -Depth 8) + "`n")
  $Enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::AppendAllText($Targets[0],$Line,$Enc)
  if($env:PIE_FAULT_AFTER_TURN_HISTORY_APPEND -eq "1"){ throw "PIE_FAULT_INJECTED_AFTER_TURN_HISTORY_APPEND" }
  [System.IO.File]::AppendAllText($Targets[1],$Line,$Enc)
  Remove-Item -LiteralPath $PendingPath -Force
}

# Roll forward an interrupted turn append: ensure every target ends with the journaled turn.
function PIE_RecoverTurnAppend {
  param([Parameter(Mandatory=$true)][string]$RunRoot,[Parameter(Mandatory=$true)][string]$SessionId)
  $PendingPath = Join-Path $RunRoot "state\pending-turn.json"
  if(-not (Test-Path -LiteralPath $PendingPath -PathType Leaf)){ return }
  try { $Journal = PIE_ReadUtf8Text -Path $PendingPath | ConvertFrom-Json }
  catch { throw ("PIE_SESSION_TURN_PENDING_INVALID: " + $SessionId + " :: " + $_.Exception.Message) }
  if([string]$Journal.schema -ne "pie.session.turn.pending.v1" -or [string]$Journal.session_id -ne $SessionId){ throw ("PIE_SESSION_TURN_PENDING_BAD: " + $SessionId) }
  $Line = [string]$Journal.line
  $TurnHash = [string]$Journal.turn_sha256
  $Enc = New-Object System.Text.UTF8Encoding($false)
  foreach($T in @($Journal.targets)){
    $P = [string]$T
    PIE_TrimTornTail -Path $P
    $Info = PIE_LastTurnInfo -Path $P
    if($Info.hash -ne $TurnHash){ [System.IO.File]::AppendAllText($P,$Line,$Enc) }
  }
  Remove-Item -LiteralPath $PendingPath -Force
}

function PIE_GetConversationTurns {
  param(
    [Parameter(Mandatory=$true)][string]$Path,
    [Parameter(Mandatory=$true)][string]$SessionId,
    [Parameter(Mandatory=$true)][string]$BindingHash,
    [Parameter(Mandatory=$false)][switch]$RequireHashChain
  )

  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ return @() }
  $Turns = New-Object System.Collections.Generic.List[object]
  $LineNumber = 0
  $PreviousTurnHash = ""
  foreach($Line in @((PIE_ReadUtf8Text -Path $Path) -split "`r?`n")){
    $LineNumber++
    if([string]::IsNullOrWhiteSpace($Line)){ continue }
    try {
      if((Get-Command ConvertFrom-Json).Parameters.ContainsKey("DateKind")){ $Turn = $Line | ConvertFrom-Json -DateKind String }
      else { $Turn = $Line | ConvertFrom-Json }
    }
    catch { throw ("PIE_CONVERSATION_NDJSON_INVALID: " + $Path + ":" + $LineNumber + " :: " + $_.Exception.Message) }

    $Schema = [string](PIE_GetSessionProperty -Object $Turn -Name "schema")
    $TurnSessionId = [string](PIE_GetSessionProperty -Object $Turn -Name "session_id")
    if($TurnSessionId -ne $SessionId){ throw ("PIE_CONVERSATION_SESSION_MISMATCH: " + $Path + ":" + $LineNumber) }
    if($Schema -eq "pie.conversation.turn.v1"){
      if($RequireHashChain){ throw ("PIE_CONVERSATION_LEGACY_TURN_REJECTED: " + $Path + ":" + $LineNumber) }
    }
    elseif($Schema -eq "pie.conversation.turn.v2"){
      $TurnBinding = [string](PIE_GetSessionProperty -Object $Turn -Name "binding_sha256")
      $TurnIndex = [int](PIE_GetSessionProperty -Object $Turn -Name "turn_index")
      $TurnPrevious = [string](PIE_GetSessionProperty -Object $Turn -Name "previous_turn_sha256")
      $TurnHash = [string](PIE_GetSessionProperty -Object $Turn -Name "turn_sha256")
      $TimestampValue = PIE_GetSessionProperty -Object $Turn -Name "ts"
      $Timestamp = $(if($TimestampValue -is [DateTime]){ $TimestampValue.ToUniversalTime().ToString("o") } else { [string]$TimestampValue })
      $PromptPath = [string](PIE_GetSessionProperty -Object $Turn -Name "prompt_path")
      $Message = [string](PIE_GetSessionProperty -Object $Turn -Name "message")
      $Response = [string](PIE_GetSessionProperty -Object $Turn -Name "response")
      $Corrections = [int](PIE_GetSessionProperty -Object $Turn -Name "grounding_correction_count")
      if($TurnBinding -ne $BindingHash){ throw ("PIE_CONVERSATION_BINDING_MISMATCH: " + $Path + ":" + $LineNumber) }
      if($TurnIndex -ne ($Turns.Count + 1)){ throw ("PIE_CONVERSATION_INDEX_MISMATCH: " + $Path + ":" + $LineNumber) }
      if($TurnPrevious -ne $PreviousTurnHash){ throw ("PIE_CONVERSATION_CHAIN_MISMATCH: " + $Path + ":" + $LineNumber) }
      if([string]::IsNullOrWhiteSpace($Timestamp) -or [string]::IsNullOrWhiteSpace($Message) -or [string]::IsNullOrWhiteSpace($Response)){
        throw ("PIE_CONVERSATION_TURN_INCOMPLETE: " + $Path + ":" + $LineNumber)
      }
      $ExpectedHash = PIE_ConversationTurnHash -SessionId $SessionId -BindingHash $BindingHash -TurnIndex $TurnIndex `
        -PreviousTurnHash $TurnPrevious -Timestamp $Timestamp -PromptPath $PromptPath -Message $Message -Response $Response `
        -GroundingCorrectionCount $Corrections
      if($TurnHash -ne $ExpectedHash){ throw ("PIE_CONVERSATION_HASH_MISMATCH: " + $Path + ":" + $LineNumber) }
      $PreviousTurnHash = $TurnHash
    }
    else { throw ("PIE_CONVERSATION_SCHEMA_BAD: " + $Path + ":" + $LineNumber) }
    [void]$Turns.Add($Turn)
  }
  return @($Turns.ToArray())
}

function PIE_GetAgentSession {
  param(
    [Parameter(Mandatory=$true)][string]$RepoRoot,
    [Parameter(Mandatory=$true)][string]$SessionId,
    [Parameter(Mandatory=$false)][switch]$RequireRunning,
    [Parameter(Mandatory=$false)][switch]$RequireIntegrity,
    [Parameter(Mandatory=$false)][switch]$OperationLockHeld
  )

  if($SessionId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$'){ throw "PIE_AGENT_SESSION_ID_INVALID" }
  $RunsRoot = Join-Path $RepoRoot "runs"
  $RunRoot = Join-Path $RunsRoot $SessionId
  if(-not (Test-Path -LiteralPath $RunRoot -PathType Container)){
    throw ("PIE_AGENT_SESSION_NOT_FOUND: " + $SessionId + ". Start it with: pie agent start -SessionId " + $SessionId + " -TargetRepo .")
  }

  $ReadLock = $null
  if(-not $OperationLockHeld){ $ReadLock = PIE_AcquireSessionLock -RunRoot $RunRoot }
  try {

  $Required = @("backend.txt","model.txt","project_repo.txt","goal.txt","session_manifest.json","state\session.state.json","conversation.ndjson")
  $Missing = New-Object System.Collections.Generic.List[string]
  foreach($Relative in $Required){
    if(-not (Test-Path -LiteralPath (Join-Path $RunRoot $Relative) -PathType Leaf)){ [void]$Missing.Add($Relative) }
  }
  if($Missing.Count -gt 0){
    throw ("PIE_AGENT_SESSION_INCOMPLETE: " + $SessionId + " missing=" + ($Missing.ToArray() -join ",") + ". Use a new session name; incomplete state must not be reused silently.")
  }

  PIE_RecoverSessionTransition -RunRoot $RunRoot -SessionId $SessionId
  PIE_RecoverTurnAppend -RunRoot $RunRoot -SessionId $SessionId

  try { $Manifest = PIE_ReadUtf8Text -Path (Join-Path $RunRoot "session_manifest.json") | ConvertFrom-Json }
  catch { throw ("PIE_AGENT_MANIFEST_INVALID: " + $SessionId + " :: " + $_.Exception.Message) }
  try { $State = PIE_ReadUtf8Text -Path (Join-Path $RunRoot "state\session.state.json") | ConvertFrom-Json }
  catch { throw ("PIE_AGENT_STATE_INVALID: " + $SessionId + " :: " + $_.Exception.Message) }

  $ManifestSchema = [string](PIE_GetSessionProperty -Object $Manifest -Name "schema")
  $StateSchema = [string](PIE_GetSessionProperty -Object $State -Name "schema")
  $ManifestSessionId = [string](PIE_GetSessionProperty -Object $Manifest -Name "session_id")
  $StateSessionId = [string](PIE_GetSessionProperty -Object $State -Name "session_id")
  $ManifestStatus = [string](PIE_GetSessionProperty -Object $Manifest -Name "status")
  $StateStatus = [string](PIE_GetSessionProperty -Object $State -Name "status")

  if($ManifestSchema -ne "pie.session.manifest.v1"){ throw ("PIE_AGENT_MANIFEST_SCHEMA_BAD: " + $SessionId) }
  if($StateSchema -ne "pie.session.state.v1"){ throw ("PIE_AGENT_STATE_SCHEMA_BAD: " + $SessionId) }
  if($ManifestSessionId -ne $SessionId -or $StateSessionId -ne $SessionId){ throw ("PIE_AGENT_SESSION_ID_MISMATCH: " + $SessionId) }
  if($ManifestStatus -ne $StateStatus -or $ManifestStatus -notin @("running","stopped")){ throw ("PIE_AGENT_SESSION_STATUS_MISMATCH: " + $SessionId) }

  $Backend = (PIE_ReadUtf8Text -Path (Join-Path $RunRoot "backend.txt")).Trim()
  $Model = (PIE_ReadUtf8Text -Path (Join-Path $RunRoot "model.txt")).Trim()
  $ProjectRepo = (PIE_ReadUtf8Text -Path (Join-Path $RunRoot "project_repo.txt")).Trim()
  $Goal = (PIE_ReadUtf8Text -Path (Join-Path $RunRoot "goal.txt")).Trim()
  if([string]::IsNullOrWhiteSpace($Backend) -or [string]::IsNullOrWhiteSpace($Model)){ throw ("PIE_AGENT_SESSION_BINDING_INCOMPLETE: " + $SessionId) }
  if(-not [string]::IsNullOrWhiteSpace($ProjectRepo)){
    if(-not (Test-Path -LiteralPath $ProjectRepo -PathType Container)){ throw ("PIE_AGENT_PROJECT_REPO_MISSING: " + $SessionId + " :: " + $ProjectRepo) }
    $ProjectRepo = (Resolve-Path -LiteralPath $ProjectRepo).Path
  }

  foreach($Pair in @(
    @{ name="backend"; expected=$Backend }, @{ name="model"; expected=$Model },
    @{ name="project_repo"; expected=$ProjectRepo }, @{ name="goal"; expected=$Goal }
  )){
    $ManifestValue = [string](PIE_GetSessionProperty -Object $Manifest -Name $Pair.name)
    $StateValue = [string](PIE_GetSessionProperty -Object $State -Name $Pair.name)
    if($Pair.name -eq "project_repo"){
      if(-not [string]::IsNullOrWhiteSpace($ManifestValue) -and (Test-Path -LiteralPath $ManifestValue -PathType Container)){ $ManifestValue = (Resolve-Path -LiteralPath $ManifestValue).Path }
      if(-not [string]::IsNullOrWhiteSpace($StateValue) -and (Test-Path -LiteralPath $StateValue -PathType Container)){ $StateValue = (Resolve-Path -LiteralPath $StateValue).Path }
    }
    if($ManifestValue -ine [string]$Pair.expected -or $StateValue -ine [string]$Pair.expected){
      throw ("PIE_AGENT_SESSION_BINDING_DRIFT: " + $SessionId + " field=" + $Pair.name)
    }
  }

  $BindingHash = PIE_SessionBindingHash -SessionId $SessionId -Backend $Backend -Model $Model -ProjectRepo $ProjectRepo -Goal $Goal
  $ManifestHash = [string](PIE_GetSessionProperty -Object $Manifest -Name "binding_sha256")
  $StateHash = [string](PIE_GetSessionProperty -Object $State -Name "binding_sha256")
  if(((-not [string]::IsNullOrWhiteSpace($ManifestHash)) -or (-not [string]::IsNullOrWhiteSpace($StateHash))) -and `
     ($ManifestHash -ne $BindingHash -or $StateHash -ne $BindingHash)){
    throw ("PIE_AGENT_SESSION_BINDING_HASH_MISMATCH: " + $SessionId)
  }
  $ProjectIdentityHash = PIE_ProjectIdentityHash -ProjectRepo $ProjectRepo
  $ManifestProjectIdentity = [string](PIE_GetSessionProperty -Object $Manifest -Name "project_identity_sha256")
  $StateProjectIdentity = [string](PIE_GetSessionProperty -Object $State -Name "project_identity_sha256")
  if(((-not [string]::IsNullOrWhiteSpace($ManifestProjectIdentity)) -or (-not [string]::IsNullOrWhiteSpace($StateProjectIdentity))) -and `
     ($ManifestProjectIdentity -ne $ProjectIdentityHash -or $StateProjectIdentity -ne $ProjectIdentityHash)){
    throw ("PIE_AGENT_PROJECT_IDENTITY_DRIFT: " + $SessionId + " :: " + $ProjectRepo)
  }
  $ManifestModelIdentity = [string](PIE_GetSessionProperty -Object $Manifest -Name "model_identity_sha256")
  $StateModelIdentity = [string](PIE_GetSessionProperty -Object $State -Name "model_identity_sha256")
  if($ManifestModelIdentity -ne $StateModelIdentity){ throw ("PIE_AGENT_MODEL_IDENTITY_STATE_DRIFT: " + $SessionId) }

  $ConversationChain = [string](PIE_GetSessionProperty -Object $Manifest -Name "conversation_chain")
  $StateConversationChain = [string](PIE_GetSessionProperty -Object $State -Name "conversation_chain")
  if($ConversationChain -ne $StateConversationChain){ throw ("PIE_AGENT_CONVERSATION_FORMAT_DRIFT: " + $SessionId) }
  $ConversationPath = Join-Path $RunRoot "conversation.ndjson"
  $Turns = @(PIE_GetConversationTurns -Path $ConversationPath -SessionId $SessionId -BindingHash $BindingHash -RequireHashChain:($ConversationChain -eq "sha256-v1"))
  $Integrity = $(if(
    $ManifestHash -eq $BindingHash -and $StateHash -eq $BindingHash -and
    $ManifestProjectIdentity -eq $ProjectIdentityHash -and $StateProjectIdentity -eq $ProjectIdentityHash -and
    -not [string]::IsNullOrWhiteSpace($ManifestModelIdentity) -and
    $ConversationChain -eq "sha256-v1"
  ){ "verified" } else { "legacy-read-only" })

  if($RequireRunning -and $ManifestStatus -ne "running"){
    throw ("PIE_AGENT_SESSION_NOT_RUNNING: " + $SessionId + " status=" + $ManifestStatus + ". Resume it before using this command.")
  }
  if($RequireIntegrity -and $Integrity -ne "verified"){
    throw ("PIE_AGENT_SESSION_LEGACY_READ_ONLY: " + $SessionId + ". Start a new session name to use verified repository, model, and conversation bindings.")
  }

  return [pscustomobject]@{
    session_id = $SessionId
    run_root = $RunRoot
    status = $ManifestStatus
    backend = $Backend
    model = $Model
    project_repo = $ProjectRepo
    goal = $Goal
    binding_sha256 = $BindingHash
    project_identity_sha256 = $ProjectIdentityHash
    model_identity_sha256 = $ManifestModelIdentity
    conversation_chain = $ConversationChain
    conversation_turns = $Turns
    integrity = $Integrity
    manifest = $Manifest
    state = $State
  }
  }
  finally { if($null -ne $ReadLock){ $ReadLock.Dispose() } }
}
