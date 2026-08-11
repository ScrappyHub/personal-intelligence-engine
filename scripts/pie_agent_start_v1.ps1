param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$SessionId,
  [Parameter(Mandatory=$false)][Alias("BackendMode")][string]$Backend = "ollama",
  [Parameter(Mandatory=$false)][Alias("ModelId")][string]$Model = "qwen2.5-coder:7b",
  [Parameter(Mandatory=$false)][string]$ProjectRepo = "",
  [Parameter(Mandatory=$false)][string]$Goal = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$SessionLock = $null
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $RepoRoot "scripts\_lib_pie_agent_session_v1.ps1")

if($SessionId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$'){ throw "PIE_AGENT_SESSION_ID_INVALID" }
if([string]::IsNullOrWhiteSpace($Backend)){ throw "PIE_AGENT_BACKEND_REQUIRED" }
if([string]::IsNullOrWhiteSpace($Model)){ throw "PIE_AGENT_MODEL_REQUIRED" }
if(-not [string]::IsNullOrWhiteSpace($ProjectRepo)){
  if(-not (Test-Path -LiteralPath $ProjectRepo -PathType Container)){ throw ("PIE_AGENT_PROJECT_REPO_NOT_FOUND: " + $ProjectRepo) }
  $ProjectRepo = (Resolve-Path -LiteralPath $ProjectRepo).Path
}

$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)
$StateRoot = Join-Path $RunRoot "state"
$Enc = New-Object System.Text.UTF8Encoding($false)
$Utc = [DateTime]::UtcNow.ToString("o")
$BindingHash = PIE_SessionBindingHash -SessionId $SessionId -Backend $Backend -Model $Model -ProjectRepo $ProjectRepo -Goal $Goal
$ProjectIdentityHash = PIE_ProjectIdentityHash -ProjectRepo $ProjectRepo
$ModelIdentityHash = PIE_CurrentModelIdentityHash -Backend $Backend -Model $Model

trap {
  if($null -ne $SessionLock){ $SessionLock.Dispose(); $SessionLock = $null }
  throw $_
}

if(Test-Path -LiteralPath $RunRoot -PathType Container){
  $Required = @("backend.txt","model.txt","project_repo.txt","goal.txt","session_manifest.json","state\session.state.json","conversation.ndjson")
  $Missing = @($Required | Where-Object { -not (Test-Path -LiteralPath (Join-Path $RunRoot $_) -PathType Leaf) })
  if($Missing.Count -gt 0){
    $HasConversation = (Test-Path -LiteralPath (Join-Path $RunRoot "conversation.ndjson") -PathType Leaf) -and `
      ((Get-Item -LiteralPath (Join-Path $RunRoot "conversation.ndjson")).Length -gt 0)
    if($HasConversation -or (Test-Path -LiteralPath (Join-Path $RunRoot "session_manifest.json") -PathType Leaf)){
      throw ("PIE_AGENT_SESSION_INCOMPLETE: " + $SessionId + " missing=" + ($Missing -join ",") + ". Use a new session name; existing state was not changed.")
    }
    $QuarantineRoot = Join-Path $RepoRoot "runs\quarantine"
    New-Item -ItemType Directory -Force -Path $QuarantineRoot | Out-Null
    $QuarantinePath = Join-Path $QuarantineRoot ($SessionId + "_" + (Get-Date -Format "yyyyMMdd_HHmmss_fff"))
    Move-Item -LiteralPath $RunRoot -Destination $QuarantinePath
  }
  else {
    $SessionLock = PIE_AcquireSessionLock -RunRoot $RunRoot
    $Existing = PIE_GetAgentSession -RepoRoot $RepoRoot -SessionId $SessionId -OperationLockHeld
    if($Existing.binding_sha256 -ne $BindingHash){
      throw ("PIE_AGENT_SESSION_BINDING_MISMATCH: " + $SessionId + " is bound to repo=" + $Existing.project_repo + " model=" + $Existing.model + ". Use a new session name for a different project, model, backend, or goal.")
    }
    if($Existing.integrity -ne "verified"){
      throw ("PIE_AGENT_SESSION_LEGACY_READ_ONLY: " + $SessionId + ". Its transcript remains available, but it cannot be resumed without weakening drift protection. Use a new session name.")
    }
    if(-not [string]::IsNullOrWhiteSpace([string]$Existing.model_identity_sha256) -and $Existing.model_identity_sha256 -ne $ModelIdentityHash){
      throw ("PIE_AGENT_MODEL_IDENTITY_DRIFT: " + $SessionId + " model=" + $Model)
    }
    $Existing.state.status = "running"
    $Existing.manifest.status = "running"
    if($null -eq $Existing.state.PSObject.Properties["resumed_utc"]){ $Existing.state | Add-Member -NotePropertyName resumed_utc -NotePropertyValue $Utc }
    else { $Existing.state.resumed_utc = $Utc }
    if($null -eq $Existing.manifest.PSObject.Properties["resumed_utc"]){ $Existing.manifest | Add-Member -NotePropertyName resumed_utc -NotePropertyValue $Utc }
    else { $Existing.manifest.resumed_utc = $Utc }
    PIE_WriteSessionPair -RunRoot $RunRoot -SessionId $SessionId -State $Existing.state -Manifest $Existing.manifest -Event "session_resume"
    $SessionLock.Dispose()
    $SessionLock = $null
    Write-Host ("PIE_AGENT_RESUME_OK: " + $SessionId) -ForegroundColor Green
    Write-Host $RunRoot
    return
  }
}

New-Item -ItemType Directory -Force -Path $StateRoot | Out-Null
$SessionLock = PIE_AcquireSessionLock -RunRoot $RunRoot
[System.IO.File]::WriteAllText((Join-Path $RunRoot "backend.txt"),($Backend + "`n"),$Enc)
[System.IO.File]::WriteAllText((Join-Path $RunRoot "model.txt"),($Model + "`n"),$Enc)
[System.IO.File]::WriteAllText((Join-Path $RunRoot "project_repo.txt"),($ProjectRepo + "`n"),$Enc)
[System.IO.File]::WriteAllText((Join-Path $RunRoot "goal.txt"),($Goal + "`n"),$Enc)
[System.IO.File]::WriteAllText((Join-Path $RunRoot "conversation.ndjson"),"",$Enc)

$State = [ordered]@{
  schema="pie.session.state.v1"; session_id=$SessionId; backend=$Backend; model=$Model; status="running"
  project_repo=$ProjectRepo; goal=$Goal; binding_sha256=$BindingHash; conversation_chain="sha256-v1"; started_utc=$Utc
  project_identity_sha256=$ProjectIdentityHash
  model_identity_sha256=$ModelIdentityHash
}
$Manifest = [ordered]@{
  schema="pie.session.manifest.v1"; session_id=$SessionId; backend=$Backend; model=$Model; status="running"
  project_repo=$ProjectRepo; goal=$Goal; binding_sha256=$BindingHash; conversation_chain="sha256-v1"; created_utc=$Utc
  project_identity_sha256=$ProjectIdentityHash
  model_identity_sha256=$ModelIdentityHash
}
PIE_WriteSessionPair -RunRoot $RunRoot -SessionId $SessionId -State $State -Manifest $Manifest -Event "session_start"
$SessionLock.Dispose()
$SessionLock = $null

Write-Host ("PIE_AGENT_START_OK: " + $SessionId) -ForegroundColor Green
Write-Host $RunRoot
