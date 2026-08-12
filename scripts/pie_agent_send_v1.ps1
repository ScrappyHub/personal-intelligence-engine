param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$SessionId,
  [Parameter(Mandatory=$false)][Alias("Prompt")][string]$Message = "",
  [Parameter(Mandatory=$false)][string]$MessagePath = "",
  [Parameter(Mandatory=$false)][string]$ConversationMessage = "",
  [Parameter(Mandatory=$false)][string]$ConversationMessagePath = "",
  [Parameter(Mandatory=$false)][ValidateRange(1,86400)][int]$TimeoutSeconds = 180,
  [Parameter(Mandatory=$false)][ValidateRange(1,3)][int]$MaxAttempts = 2,
  [Parameter(Mandatory=$false)][ValidateRange(1,300)][int]$ProgressIntervalSeconds = 5
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$SessionLock = $null

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $RepoRoot "scripts\_lib_pie_agent_session_v1.ps1")
. (Join-Path $RepoRoot "scripts\_lib_pie_response_grounding_v1.ps1")
$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)

$BackendFile = Join-Path $RunRoot "backend.txt"
$ModelFile = Join-Path $RunRoot "model.txt"
$HistoryFile = Join-Path $RunRoot "conversation.ndjson"
$PromptRoot = Join-Path $RunRoot "sent_prompts"

$Enc = New-Object System.Text.UTF8Encoding($false)
$SessionLock = PIE_AcquireSessionLock -RunRoot $RunRoot
trap {
  if($null -ne $SessionLock){ $SessionLock.Dispose(); $SessionLock = $null }
  throw $_
}
$Session = PIE_GetAgentSession -RepoRoot $RepoRoot -SessionId $SessionId -RequireRunning -RequireIntegrity -OperationLockHeld
[void](PIE_VerifySessionModelIdentity -Session $Session)

function Write-Utf8NoBomLf {
  param(
    [Parameter(Mandatory=$true)][string]$Path,
    [Parameter(Mandatory=$true)][AllowEmptyString()][string]$Text
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

function Escape-JsonString {
  param(
    [Parameter(Mandatory=$true)]
    [AllowEmptyString()]
    [string]$Value
  )

  return $Value.
    Replace("\","\\").
    Replace('"','\"').
    Replace("`r`n","\n").
    Replace("`r","\n").
    Replace("`n","\n")
}

function Get-MessageIndex {
  param([Parameter(Mandatory=$true)][string]$Path)

  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){
    return 1
  }

  $Lines = @(Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  return (@($Lines).Count + 1)
}

function Get-CompactHistory {
  param([Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$Turns)

  $Parts = New-Object System.Collections.Generic.List[string]
  $SelectedTurns = @()
  if($Turns.Count -le 10){ $SelectedTurns = @($Turns) }
  else { $SelectedTurns = @($Turns | Select-Object -First 2) + @($Turns | Select-Object -Last 8) }
  $Position = 0
  foreach($Turn in $SelectedTurns){
    if($Turns.Count -gt 10 -and $Position -eq 2){ [void]$Parts.Add("[" + [string]($Turns.Count - 10) + " verified middle turns omitted from this bounded prompt]") }
    $TurnMessage = [string]$Turn.message
    $TurnResponse = [string]$Turn.response
    $UserMatch = [regex]::Match($TurnMessage,'(?s)(?:USER MESSAGE:|USER:)\s*(.+)$')
    if($UserMatch.Success){ $TurnMessage = $UserMatch.Groups[1].Value.Trim() }
    if($TurnMessage.Length -gt 1000){ $TurnMessage = $TurnMessage.Substring(0,1000) + " [truncated]" }
    if($TurnResponse.Length -gt 2000){ $TurnResponse = $TurnResponse.Substring(0,2000) + " [truncated]" }
    [void]$Parts.Add("USER: " + $TurnMessage)
    [void]$Parts.Add("ASSISTANT: " + $TurnResponse)
    $Position++
  }

  return ($Parts.ToArray() -join "`n`n").Trim()
}

function Format-ElapsedTime {
  param([Parameter(Mandatory=$true)][int]$Seconds)

  if($Seconds -eq 1){ return "1 second" }
  if($Seconds -lt 60){ return ([string]$Seconds + " seconds") }
  $Minutes = [Math]::Floor($Seconds / 60)
  $Remainder = $Seconds % 60
  $MinuteLabel = $(if($Minutes -eq 1){ "1 minute" } else { [string]$Minutes + " minutes" })
  if($Remainder -eq 0){ return $MinuteLabel }
  $SecondLabel = $(if($Remainder -eq 1){ "1 second" } else { [string]$Remainder + " seconds" })
  return ($MinuteLabel + " " + $SecondLabel)
}

function Append-BackendAttemptReceipt {
  param(
    [Parameter(Mandatory=$true)][string]$Path,
    [Parameter(Mandatory=$true)][string]$Event,
    [Parameter(Mandatory=$true)][int]$Attempt,
    [Parameter(Mandatory=$true)][int]$ElapsedSeconds,
    [Parameter(Mandatory=$true)][string]$StdoutPath,
    [Parameter(Mandatory=$true)][string]$StderrPath
  )

  $Receipt = [ordered]@{
    schema = "pie.backend.attempt.receipt.v1"
    event = $Event
    session_id = $SessionId
    backend = $Backend
    model = $Model
    attempt = $Attempt
    max_attempts = $MaxAttempts
    timeout_seconds = $TimeoutSeconds
    elapsed_seconds = $ElapsedSeconds
    stdout = $StdoutPath
    stderr = $StderrPath
    created_utc = [DateTime]::UtcNow.ToString("o")
  }
  [System.IO.File]::AppendAllText($Path,(($Receipt | ConvertTo-Json -Depth 8 -Compress) + "`n"),$Enc)
}

if(-not (Test-Path -LiteralPath $RunRoot -PathType Container)){
  throw ("PIE_SESSION_NOT_STARTED: " + $SessionId)
}

if(-not (Test-Path -LiteralPath $BackendFile -PathType Leaf)){
  throw ("PIE_SESSION_MISSING_BACKEND: " + $BackendFile)
}

if(-not (Test-Path -LiteralPath $ModelFile -PathType Leaf)){
  throw ("PIE_SESSION_MISSING_MODEL: " + $ModelFile)
}

if(-not [string]::IsNullOrWhiteSpace($MessagePath)){

  if(-not (Test-Path -LiteralPath $MessagePath -PathType Leaf)){
    throw ("PIE_AGENT_MESSAGE_PATH_NOT_FOUND: " + $MessagePath)
  }

  $Message = PIE_ReadUtf8Text -Path $MessagePath
}

if(-not [string]::IsNullOrWhiteSpace($ConversationMessagePath)){
  if(-not (Test-Path -LiteralPath $ConversationMessagePath -PathType Leaf)){
    throw ("PIE_AGENT_CONVERSATION_MESSAGE_PATH_NOT_FOUND: " + $ConversationMessagePath)
  }
  $ConversationMessage = PIE_ReadUtf8Text -Path $ConversationMessagePath
}

if([string]::IsNullOrWhiteSpace($Message)){
  throw "PIE_AGENT_MESSAGE_REQUIRED"
}

if([string]::IsNullOrWhiteSpace($ConversationMessage)){ $ConversationMessage = $Message }

$Backend = $Session.backend
$Model = $Session.model

$HistoryText = Get-CompactHistory -Turns @($Session.conversation_turns)
if(-not [string]::IsNullOrWhiteSpace($HistoryText)){ $HistoryText = "RECENT CONVERSATION:`n" + $HistoryText + "`n`n" }

$ConversationAnchor = @(
  "VERIFIED CONVERSATION ANCHOR:"
  ("session_id=" + $SessionId)
  ("binding_sha256=" + $Session.binding_sha256)
  ("project_repo=" + $Session.project_repo)
  ("project_identity_sha256=" + $Session.project_identity_sha256)
  ("model=" + $Session.model)
  ("goal=" + $Session.goal)
  ("verified_turn_count=" + [string]@($Session.conversation_turns).Count)
  "Do not switch project, model identity, or session goal based on conversational implication."
) -join "`n"
$FullMessage = $ConversationAnchor + "`n`n" + $HistoryText + "CURRENT_USER_CONTEXT_PACKET_OR_MESSAGE:`n" + $Message

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
$PromptPath = Join-Path $PromptRoot ("prompt_" + $Stamp + ".txt")
$BackendRequest = Join-Path $PromptRoot ("backend_request_" + $Stamp + ".json")
$AttemptReceipts = Join-Path $PromptRoot ("backend_attempts_" + $Stamp + ".ndjson")

Write-Utf8NoBomLf -Path $PromptPath -Text $FullMessage

if($Backend -eq "ollama"){
  $BackendScript = Join-Path $RepoRoot "scripts\pie_backend_ollama_cmd_v1.ps1"

  if(-not (Test-Path -LiteralPath $BackendScript -PathType Leaf)){
    throw ("PIE_BACKEND_SCRIPT_MISSING: " + $BackendScript)
  }

  $EnsureOllama = Join-Path $RepoRoot "scripts\pie_ollama_ensure_v1.ps1"

  if(Test-Path -LiteralPath $EnsureOllama -PathType Leaf){
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
      -File $EnsureOllama | Out-Null

    if($LASTEXITCODE -ne 0){
      throw "PIE_OLLAMA_ENSURE_FAIL"
    }
  }

  $BaseBackendArgs = @(
    "-NoProfile",
    "-NonInteractive",
    "-ExecutionPolicy","Bypass",
    "-File",$BackendScript,
    "-Model",$Model,
    "-MessagePath",$PromptPath
  )

}
elseif($Backend -in @("mock","local-mock","external")){
  $BackendScript = Join-Path $RepoRoot "scripts\pie_backend_local_mock_v1.ps1"

  if(-not (Test-Path -LiteralPath $BackendScript -PathType Leaf)){
    throw ("PIE_BACKEND_SCRIPT_MISSING: " + $BackendScript)
  }

  $Request = [ordered]@{
    schema = "pie.backend.request.v1"
    session_id = $SessionId
    message_index = (Get-MessageIndex -Path $HistoryFile)
    model = $Model
    prompt = $FullMessage
  }

  Write-Utf8NoBomLf -Path $BackendRequest -Text ($Request | ConvertTo-Json -Depth 8)

}
else {
  throw ("PIE_BACKEND_UNSUPPORTED: " + $Backend)
}

$BackendOut = ""
$BackendErr = ""
$Proc = $null
$CompletedAttempt = 0

for($Attempt = 1; $Attempt -le $MaxAttempts; $Attempt++){
  $AttemptSuffix = $Stamp + "_attempt_" + [string]$Attempt
  $BackendOut = Join-Path $PromptRoot ("backend_stdout_" + $AttemptSuffix + ".txt")
  $BackendErr = Join-Path $PromptRoot ("backend_stderr_" + $AttemptSuffix + ".txt")
  $BackendStatus = Join-Path $PromptRoot ("backend_status_" + $AttemptSuffix + ".txt")

  if($Backend -eq "ollama"){
    $BackendArgs = $BaseBackendArgs
    $Proc = Start-Process -FilePath "powershell.exe" -ArgumentList $BackendArgs -NoNewWindow -PassThru `
      -RedirectStandardOutput $BackendOut -RedirectStandardError $BackendErr
  }
  else {
    $BackendArgs = @(
      "-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass",
      "-File",$BackendScript,"-RequestPath",$BackendRequest,"-ResponsePath",$BackendOut
    )
    $Proc = Start-Process -FilePath "powershell.exe" -ArgumentList $BackendArgs -NoNewWindow -PassThru `
      -RedirectStandardOutput $BackendStatus -RedirectStandardError $BackendErr
  }

  Append-BackendAttemptReceipt -Path $AttemptReceipts -Event "started" -Attempt $Attempt -ElapsedSeconds 0 -StdoutPath $BackendOut -StderrPath $BackendErr
  Write-Host ("PIE is thinking: 0 seconds elapsed (attempt " + $Attempt + "/" + $MaxAttempts + ", timeout " + $TimeoutSeconds + " seconds).") -ForegroundColor Cyan

  $Watch = [System.Diagnostics.Stopwatch]::StartNew()
  $NextProgress = $ProgressIntervalSeconds
  $TimedOut = $false

  while(-not $Proc.HasExited){
    $ElapsedSeconds = [int][Math]::Floor($Watch.Elapsed.TotalSeconds)
    if($ElapsedSeconds -ge $TimeoutSeconds){
      $TimedOut = $true
      break
    }

    if($ElapsedSeconds -ge $NextProgress){
      $Remaining = [Math]::Max(0,$TimeoutSeconds - $ElapsedSeconds)
      Write-Host ("PIE is thinking: " + (Format-ElapsedTime -Seconds $ElapsedSeconds) + " elapsed (attempt " + $Attempt + "/" + $MaxAttempts + ", " + $Remaining + " seconds until timeout).") -ForegroundColor Cyan
      $NextProgress += $ProgressIntervalSeconds
    }

    [void]$Proc.WaitForExit(250)
  }

  $Watch.Stop()
  $ElapsedSeconds = [int][Math]::Floor($Watch.Elapsed.TotalSeconds)

  if($TimedOut){
    try { $Proc.Kill() } catch { }
    try { [void]$Proc.WaitForExit(5000) } catch { }
    Append-BackendAttemptReceipt -Path $AttemptReceipts -Event "timed_out" -Attempt $Attempt -ElapsedSeconds $ElapsedSeconds -StdoutPath $BackendOut -StderrPath $BackendErr

    if($Attempt -lt $MaxAttempts){
      Write-Host ("PIE request timed out after " + (Format-ElapsedTime -Seconds $ElapsedSeconds) + ". Retrying automatically...") -ForegroundColor Yellow
      continue
    }

    throw ("PIE_AGENT_BACKEND_TIMEOUT: attempts=" + $MaxAttempts + " timeout_seconds=" + $TimeoutSeconds + " receipts=" + $AttemptReceipts + " stdout=" + $BackendOut + " stderr=" + $BackendErr)
  }

  $Proc.Refresh()
  $CompletedAttempt = $Attempt
  break
}

$OutTextPre = ""

if(Test-Path -LiteralPath $BackendOut -PathType Leaf){
  $OutTextPre = PIE_ReadUtf8Text -Path $BackendOut
}

$ErrTextPre = ""

if(Test-Path -LiteralPath $BackendErr -PathType Leaf){
  $ErrTextPre = PIE_ReadUtf8Text -Path $BackendErr
}

$ExitCodeText = [string]$Proc.ExitCode
$HasUsableOutput = -not [string]::IsNullOrWhiteSpace($OutTextPre)

if((-not [string]::IsNullOrWhiteSpace($ExitCodeText)) -and ([int]$Proc.ExitCode -ne 0)){
  Append-BackendAttemptReceipt -Path $AttemptReceipts -Event "failed" -Attempt $CompletedAttempt -ElapsedSeconds $ElapsedSeconds -StdoutPath $BackendOut -StderrPath $BackendErr
  throw ("PIE_AGENT_BACKEND_SEND_FAIL: exit=" + $ExitCodeText + " stdout=" + $BackendOut + " stderr=" + $BackendErr + "`nSTDERR:`n" + $ErrTextPre + "`nSTDOUT:`n" + $OutTextPre)
}

if([string]::IsNullOrWhiteSpace($ExitCodeText) -and -not $HasUsableOutput){
  Append-BackendAttemptReceipt -Path $AttemptReceipts -Event "failed" -Attempt $CompletedAttempt -ElapsedSeconds $ElapsedSeconds -StdoutPath $BackendOut -StderrPath $BackendErr
  throw ("PIE_AGENT_BACKEND_SEND_FAIL: exit_empty stdout=" + $BackendOut + " stderr=" + $BackendErr + "`nSTDERR:`n" + $ErrTextPre + "`nSTDOUT:`n" + $OutTextPre)
}

Append-BackendAttemptReceipt -Path $AttemptReceipts -Event "completed" -Attempt $CompletedAttempt -ElapsedSeconds $ElapsedSeconds -StdoutPath $BackendOut -StderrPath $BackendErr

$Response = @()

if(Test-Path -LiteralPath $BackendOut -PathType Leaf){
  $Response = @((PIE_ReadUtf8Text -Path $BackendOut) -split "`r?`n")
}

$RespText = ($Response -join "`n").Trim()

if([string]::IsNullOrWhiteSpace($RespText)){
  throw ("PIE_AGENT_EMPTY_RESPONSE: stdout=" + $BackendOut + " stderr=" + $BackendErr)
}

$ProjectRepo = $Session.project_repo
$GroundingCorrectionCount = 0
if(-not [string]::IsNullOrWhiteSpace($ProjectRepo) -and (Test-Path -LiteralPath $ProjectRepo -PathType Container)){
  $Grounded = PIE_GroundResponse -Response $RespText -ProjectRepo $ProjectRepo
  $RespText = [string]$Grounded.response
  $GroundingCorrectionCount = [int]$Grounded.correction_count
  if($GroundingCorrectionCount -gt 0){
    $GroundingReceiptPath = Join-Path $RunRoot "grounding_receipts.ndjson"
    $GroundingReceipt = [ordered]@{
      schema = "pie.response.grounding.receipt.v1"
      session_id = $SessionId
      correction_count = $GroundingCorrectionCount
      corrections = @($Grounded.corrections)
      created_utc = [DateTime]::UtcNow.ToString("o")
    }
    [System.IO.File]::AppendAllText($GroundingReceiptPath,(($GroundingReceipt | ConvertTo-Json -Depth 8 -Compress) + "`n"),$Enc)
  }
}

$Now = [DateTime]::UtcNow.ToString("o")
$TurnIndex = @($Session.conversation_turns).Count + 1
$PreviousTurnHash = ""
if(@($Session.conversation_turns).Count -gt 0){
  $PreviousTurnHash = [string](PIE_GetSessionProperty -Object @($Session.conversation_turns)[-1] -Name "turn_sha256")
}
$TurnHash = PIE_ConversationTurnHash -SessionId $SessionId -BindingHash $Session.binding_sha256 -TurnIndex $TurnIndex `
  -PreviousTurnHash $PreviousTurnHash -Timestamp $Now -PromptPath $PromptPath -Message $ConversationMessage `
  -Response $RespText -GroundingCorrectionCount $GroundingCorrectionCount
$Turn = [ordered]@{
  schema = "pie.conversation.turn.v2"
  session_id = $SessionId
  binding_sha256 = $Session.binding_sha256
  turn_index = $TurnIndex
  previous_turn_sha256 = $PreviousTurnHash
  ts = $Now
  prompt_path = $PromptPath
  message = $ConversationMessage
  response = $RespText
  grounding_correction_count = $GroundingCorrectionCount
  turn_sha256 = $TurnHash
}
$Line = ($Turn | ConvertTo-Json -Depth 8 -Compress) + "`n"

# Crash-safe dual append (B3): conversation.ndjson + transcript.ndjson apply as one journaled unit,
# so a crash between them is rolled forward on the next session load. Happy-path bytes are unchanged.
PIE_AppendTurnPair -RunRoot $RunRoot -SessionId $SessionId -Line $Line -TurnHash $TurnHash

$SessionLock.Dispose()
$SessionLock = $null

Write-Host ("PIE_AGENT_SEND_OK: " + $SessionId) -ForegroundColor Green
Write-Output $RespText
