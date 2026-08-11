param([Parameter(Mandatory=$true)][string]$RepoRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$FixtureRoot = Join-Path $RepoRoot "runs\pie_drift_boundary_fixtures"
$SessionId = "pie_drift_boundary_session"
$CorruptId = "pie_drift_corrupt_session"
$BindingId = "pie_drift_binding_session"
$ModelId = "pie_drift_model_session"
$ProjectId = "pie_drift_project_session"
$FaultId = "pie_drift_fault_session"
$EncodingId = "pie_drift_encoding_session"
$Enc = New-Object System.Text.UTF8Encoding($false)
. (Join-Path $RepoRoot "scripts\_lib_pie_agent_session_v1.ps1")
. (Join-Path $RepoRoot "scripts\_lib_pie_memory_v1.ps1")

foreach($Path in @($FixtureRoot,(Join-Path $RepoRoot ("runs\" + $SessionId)),(Join-Path $RepoRoot ("runs\" + $CorruptId)),(Join-Path $RepoRoot ("runs\" + $BindingId)),(Join-Path $RepoRoot ("runs\" + $ModelId)),(Join-Path $RepoRoot ("runs\" + $ProjectId)),(Join-Path $RepoRoot ("runs\" + $FaultId)),(Join-Path $RepoRoot ("runs\" + $EncodingId)))){
  if(Test-Path -LiteralPath $Path -PathType Container){ Remove-Item -LiteralPath $Path -Recurse -Force }
}

function Write-Utf8([string]$Path,[string]$Text){
  $Parent = Split-Path -Parent $Path
  if(-not (Test-Path -LiteralPath $Parent -PathType Container)){ New-Item -ItemType Directory -Force -Path $Parent | Out-Null }
  $Clean = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $Clean.EndsWith("`n")){ $Clean += "`n" }
  [System.IO.File]::WriteAllText($Path,$Clean,$Enc)
}

function New-Policy([string]$Path,[string]$Mode){
  $Policy = [ordered]@{schema="pie.memory.policy.v1";mode=$Mode;allowed_modes=@("ask","auto_accept","manual_only","off");default_lane="active";repo_memory_enabled=$true;project_memory_enabled=$true;coding_memory_enabled=$true}
  Write-Utf8 -Path $Path -Text ($Policy | ConvertTo-Json -Depth 8)
}

$RepoA = Join-Path $FixtureRoot "a\shared"
$RepoB = Join-Path $FixtureRoot "b\shared"
New-Item -ItemType Directory -Force -Path (Join-Path $RepoA ".pie") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $RepoB ".pie") | Out-Null
Write-Utf8 -Path (Join-Path $RepoA ".pie\profile.json") -Text '{"schema":"pie.repo.profile.v1","project":"shared"}'
Write-Utf8 -Path (Join-Path $RepoB ".pie\profile.json") -Text '{"schema":"pie.repo.profile.v1","project":"shared"}'

& (Join-Path $RepoRoot "scripts\pie_agent_start_v1.ps1") -RepoRoot $RepoRoot -SessionId $SessionId -Backend mock -Model drift-mock -ProjectRepo $RepoA -Goal "stable binding" | Out-Null
& (Join-Path $RepoRoot "scripts\pie_agent_send_v1.ps1") -RepoRoot $RepoRoot -SessionId $SessionId -Message "first project A turn" -ConversationMessage "first project A turn" -TimeoutSeconds 30 -MaxAttempts 1 | Out-Null
& (Join-Path $RepoRoot "scripts\pie_agent_stop_v1.ps1") -RepoRoot $RepoRoot -SessionId $SessionId | Out-Null

$RebindRejected = $false
try { & (Join-Path $RepoRoot "scripts\pie_agent_start_v1.ps1") -RepoRoot $RepoRoot -SessionId $SessionId -Backend mock -Model drift-mock -ProjectRepo $RepoB -Goal "stable binding" | Out-Null }
catch { if($_.Exception.Message -like "PIE_AGENT_SESSION_BINDING_MISMATCH:*"){ $RebindRejected = $true } }
if(-not $RebindRejected){ throw "PIE_DRIFT_SESSION_REBIND_ALLOWED" }
$Bound = PIE_GetAgentSession -RepoRoot $RepoRoot -SessionId $SessionId
if($Bound.project_repo -ine (Resolve-Path $RepoA).Path -or @($Bound.conversation_turns).Count -ne 1){ throw "PIE_DRIFT_REBIND_MUTATED_SESSION" }

& (Join-Path $RepoRoot "scripts\pie_agent_start_v1.ps1") -RepoRoot $RepoRoot -SessionId $SessionId -Backend mock -Model drift-mock -ProjectRepo $RepoA -Goal "stable binding" | Out-Null
$HeldLock = [System.IO.File]::Open((Join-Path $Bound.run_root "state\session-operation.lock"),[System.IO.FileMode]::OpenOrCreate,[System.IO.FileAccess]::ReadWrite,[System.IO.FileShare]::None)
try {
  $PreviousErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  $BusyOutput = @(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $RepoRoot "scripts\pie_agent_send_v1.ps1") -RepoRoot $RepoRoot -SessionId $SessionId -Message "must not run" -TimeoutSeconds 5 -MaxAttempts 1 2>&1) -join "`n"
  $BusyExit = $LASTEXITCODE
  $ErrorActionPreference = $PreviousErrorActionPreference
}
finally {
  $ErrorActionPreference = "Stop"
  $HeldLock.Dispose()
}
if($BusyExit -eq 0 -or $BusyOutput -notmatch "PIE_AGENT_SESSION_BUSY"){ throw "PIE_DRIFT_CONCURRENT_CHAT_NOT_BLOCKED" }

& (Join-Path $RepoRoot "scripts\pie_agent_send_v1.ps1") -RepoRoot $RepoRoot -SessionId $SessionId -Message "second project A turn" -ConversationMessage "second project A turn" -TimeoutSeconds 30 -MaxAttempts 1 | Out-Null
$Resumed = PIE_GetAgentSession -RepoRoot $RepoRoot -SessionId $SessionId
if(@($Resumed.conversation_turns).Count -ne 2){ throw "PIE_DRIFT_RESUME_HISTORY_LOST" }
if([string]@($Resumed.conversation_turns)[1].previous_turn_sha256 -ne [string]@($Resumed.conversation_turns)[0].turn_sha256){ throw "PIE_DRIFT_CONVERSATION_CHAIN_BAD" }

$ConversationPath = Join-Path $Resumed.run_root "conversation.ndjson"
$PreviousHash = [string]@($Resumed.conversation_turns)[-1].turn_sha256
for($Index = 3; $Index -le 12; $Index++){
  $Timestamp = "2026-01-01T00:00:" + $Index.ToString("00") + "Z"
  $TurnMessage = "anchored turn " + $Index
  $TurnResponse = "anchored response " + $Index
  $TurnHash = PIE_ConversationTurnHash -SessionId $SessionId -BindingHash $Resumed.binding_sha256 -TurnIndex $Index -PreviousTurnHash $PreviousHash -Timestamp $Timestamp -PromptPath ("fixture-" + $Index) -Message $TurnMessage -Response $TurnResponse -GroundingCorrectionCount 0
  $Turn = [ordered]@{schema="pie.conversation.turn.v2";session_id=$SessionId;binding_sha256=$Resumed.binding_sha256;turn_index=$Index;previous_turn_sha256=$PreviousHash;ts=$Timestamp;prompt_path=("fixture-" + $Index);message=$TurnMessage;response=$TurnResponse;grounding_correction_count=0;turn_sha256=$TurnHash}
  [System.IO.File]::AppendAllText($ConversationPath,(($Turn | ConvertTo-Json -Compress) + "`n"),$Enc)
  $PreviousHash = $TurnHash
}
& (Join-Path $RepoRoot "scripts\pie_agent_send_v1.ps1") -RepoRoot $RepoRoot -SessionId $SessionId -Message "anchor verification turn" -ConversationMessage "anchor verification turn" -TimeoutSeconds 30 -MaxAttempts 1 | Out-Null
$LatestPrompt = Get-ChildItem -LiteralPath (Join-Path $Resumed.run_root "sent_prompts") -File -Filter "prompt_*.txt" | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1 | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }
foreach($RequiredAnchor in @("VERIFIED CONVERSATION ANCHOR:","binding_sha256=" + $Resumed.binding_sha256,"project_identity_sha256=" + $Resumed.project_identity_sha256,"verified_turn_count=12","first project A turn","second project A turn","anchored turn 12","2 verified middle turns omitted")){
  if($LatestPrompt -notmatch [regex]::Escape($RequiredAnchor)){ throw ("PIE_DRIFT_CONVERSATION_ANCHOR_MISSING: " + $RequiredAnchor) }
}
if($LatestPrompt -match [regex]::Escape("anchored turn 3") -or $LatestPrompt -match [regex]::Escape("anchored turn 4")){ throw "PIE_DRIFT_CONVERSATION_OMISSION_BOUNDARY_BAD" }

& (Join-Path $RepoRoot "scripts\pie_agent_start_v1.ps1") -RepoRoot $RepoRoot -SessionId $CorruptId -Backend mock -Model drift-mock -ProjectRepo $RepoA -Goal "corruption test" | Out-Null
[System.IO.File]::AppendAllText((Join-Path $RepoRoot ("runs\" + $CorruptId + "\conversation.ndjson")),"{not-json}`n",$Enc)
$CorruptRejected = $false
try { [void](PIE_GetAgentSession -RepoRoot $RepoRoot -SessionId $CorruptId) }
catch { if($_.Exception.Message -like "PIE_CONVERSATION_NDJSON_INVALID:*"){ $CorruptRejected = $true } }
if(-not $CorruptRejected){ throw "PIE_DRIFT_CORRUPT_HISTORY_ACCEPTED" }

& (Join-Path $RepoRoot "scripts\pie_agent_start_v1.ps1") -RepoRoot $RepoRoot -SessionId $BindingId -Backend mock -Model drift-mock -ProjectRepo $RepoA -Goal "binding test" | Out-Null
$BindingStatePath = Join-Path $RepoRoot ("runs\" + $BindingId + "\state\session.state.json")
$BindingState = Get-Content -LiteralPath $BindingStatePath -Raw | ConvertFrom-Json
$BindingState.model = "forged-model"
Write-Utf8 -Path $BindingStatePath -Text ($BindingState | ConvertTo-Json -Depth 12)
$BindingRejected = $false
try { [void](PIE_GetAgentSession -RepoRoot $RepoRoot -SessionId $BindingId) }
catch { if($_.Exception.Message -like "PIE_AGENT_SESSION_BINDING_DRIFT:*"){ $BindingRejected = $true } }
if(-not $BindingRejected){ throw "PIE_DRIFT_SPLIT_BINDING_ACCEPTED" }

& (Join-Path $RepoRoot "scripts\pie_agent_start_v1.ps1") -RepoRoot $RepoRoot -SessionId $ModelId -Backend mock -Model drift-mock -ProjectRepo $RepoA -Goal "model identity test" | Out-Null
$ModelRun = Join-Path $RepoRoot ("runs\" + $ModelId)
foreach($Relative in @("session_manifest.json","state\session.state.json")){
  $Path = Join-Path $ModelRun $Relative
  $Object = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
  $Object.model_identity_sha256 = "0" * 64
  Write-Utf8 -Path $Path -Text ($Object | ConvertTo-Json -Depth 12)
}
$ModelSession = PIE_GetAgentSession -RepoRoot $RepoRoot -SessionId $ModelId
$ModelDriftRejected = $false
try { [void](PIE_VerifySessionModelIdentity -Session $ModelSession) }
catch { if($_.Exception.Message -like "PIE_AGENT_MODEL_IDENTITY_DRIFT:*"){ $ModelDriftRejected = $true } }
if(-not $ModelDriftRejected){ throw "PIE_DRIFT_MODEL_REPLACEMENT_ACCEPTED" }

& (Join-Path $RepoRoot "scripts\pie_agent_start_v1.ps1") -RepoRoot $RepoRoot -SessionId $ProjectId -Backend mock -Model drift-mock -ProjectRepo $RepoA -Goal "project identity test" | Out-Null
$ProjectRun = Join-Path $RepoRoot ("runs\" + $ProjectId)
foreach($Relative in @("session_manifest.json","state\session.state.json")){
  $Path = Join-Path $ProjectRun $Relative
  $Object = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
  $Object.project_identity_sha256 = "0" * 64
  Write-Utf8 -Path $Path -Text ($Object | ConvertTo-Json -Depth 12)
}
$ProjectDriftRejected = $false
try { [void](PIE_GetAgentSession -RepoRoot $RepoRoot -SessionId $ProjectId) }
catch { if($_.Exception.Message -like "PIE_AGENT_PROJECT_IDENTITY_DRIFT:*"){ $ProjectDriftRejected = $true } }
if(-not $ProjectDriftRejected){ throw "PIE_DRIFT_PROJECT_REPLACEMENT_ACCEPTED" }

& (Join-Path $RepoRoot "scripts\pie_agent_start_v1.ps1") -RepoRoot $RepoRoot -SessionId $FaultId -Backend mock -Model drift-mock -ProjectRepo $RepoA -Goal "transition recovery test" | Out-Null
$env:PIE_FAULT_AFTER_SESSION_STATE_WRITE = "1"
$FaultInjected = $false
try { & (Join-Path $RepoRoot "scripts\pie_agent_stop_v1.ps1") -RepoRoot $RepoRoot -SessionId $FaultId | Out-Null }
catch { if($_.Exception.Message -eq "PIE_FAULT_INJECTED_AFTER_SESSION_STATE_WRITE"){ $FaultInjected = $true } }
finally { Remove-Item Env:PIE_FAULT_AFTER_SESSION_STATE_WRITE -ErrorAction SilentlyContinue }
if(-not $FaultInjected){ throw "PIE_DRIFT_TRANSITION_FAULT_NOT_INJECTED" }
$FaultRun = Join-Path $RepoRoot ("runs\" + $FaultId)
if(-not (Test-Path -LiteralPath (Join-Path $FaultRun "state\pending-transition.json") -PathType Leaf)){ throw "PIE_DRIFT_TRANSITION_PENDING_MISSING" }
$Recovered = PIE_GetAgentSession -RepoRoot $RepoRoot -SessionId $FaultId
if($Recovered.status -ne "stopped" -or (Test-Path -LiteralPath (Join-Path $FaultRun "state\pending-transition.json") -PathType Leaf)){ throw "PIE_DRIFT_TRANSITION_NOT_RECOVERED" }
$TransitionReceipts = @(Get-Content -LiteralPath (Join-Path $FaultRun "session_transitions.ndjson") | ForEach-Object { $_ | ConvertFrom-Json })
if(@($TransitionReceipts | Where-Object { [bool]$_.recovered }).Count -ne 1){ throw "PIE_DRIFT_TRANSITION_RECOVERY_RECEIPT_MISSING" }

& (Join-Path $RepoRoot "scripts\pie_agent_start_v1.ps1") -RepoRoot $RepoRoot -SessionId $EncodingId -Backend mock -Model drift-mock -ProjectRepo $RepoA -Goal "encoding stability" | Out-Null
$UnicodeMessage = "UTF-8 caf" + [char]0x00E9 + " sunset " + [char]0x2600
& (Join-Path $RepoRoot "scripts\pie_agent_send_v1.ps1") -RepoRoot $RepoRoot -SessionId $EncodingId -Message $UnicodeMessage -ConversationMessage $UnicodeMessage -TimeoutSeconds 30 -MaxAttempts 1 | Out-Null
$EncodingOutput = @(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $RepoRoot "pie.ps1") agent status -SessionId $EncodingId 2>&1) -join "`n"
if($LASTEXITCODE -ne 0 -or $EncodingOutput -notmatch "integrity: verified"){ throw "PIE_DRIFT_CROSS_SHELL_UTF8_UNSTABLE" }

$MemoryRoot = Join-Path $FixtureRoot "memory"
$PolicyOn = Join-Path $FixtureRoot "policy-on.json"
$PolicyOff = Join-Path $FixtureRoot "policy-off.json"
New-Policy -Path $PolicyOn -Mode "auto_accept"
New-Policy -Path $PolicyOff -Mode "off"
$ActiveText = "ACTIVE_MEMORY_MUST_NOT_ENTER_PROJECT"
$CodingText = "CODING_MEMORY_ALLOWED_GLOBALLY"
$ProjectAText = "PROJECT_A_MEMORY_ONLY"
$ProjectBText = "PROJECT_B_MEMORY_ONLY"
$IdentityA = PIE_ProjectIdentityHash -ProjectRepo $RepoA
$IdentityB = PIE_ProjectIdentityHash -ProjectRepo $RepoB
$Records = @(
  @{path=(Join-Path $MemoryRoot "active\memory.ndjson"); lane="active"; project=""; repo=""; text=$ActiveText},
  @{path=(Join-Path $MemoryRoot "coding\memory.ndjson"); lane="coding"; project=""; repo=""; text=$CodingText},
  @{path=(Join-Path $MemoryRoot "projects\a\memory.ndjson"); lane="project"; project="shared"; repo=$RepoA; text=$ProjectAText},
  @{path=(Join-Path $MemoryRoot "projects\b\memory.ndjson"); lane="project"; project="shared"; repo=$RepoB; text=$ProjectBText}
)
foreach($Record in $Records){
  $Id = PIE_MemoryId -Lane $Record.lane -Project $Record.project -ProjectRepo $Record.repo -Text $Record.text
  $RecordIdentity = $(if($Record.repo -ieq $RepoA){ $IdentityA } elseif($Record.repo -ieq $RepoB){ $IdentityB } else { "" })
  $Obj = [ordered]@{schema="pie.memory.record.v1";memory_id=$Id;lane=$Record.lane;project=$Record.project;project_repo=$Record.repo;project_identity_sha256=$RecordIdentity;text=$Record.text;created_utc="2026-01-01T00:00:00Z"}
  Write-Utf8 -Path $Record.path -Text ($Obj | ConvertTo-Json -Compress)
}
$RepoRecordId = PIE_MemoryId -Lane "project" -Project "shared" -ProjectRepo $RepoA -Text "REPO_FILE_MEMORY"
$RepoRecord = [ordered]@{schema="pie.memory.record.v1";memory_id=$RepoRecordId;lane="project";project="shared";project_repo=$RepoA;project_identity_sha256=$IdentityA;text="REPO_FILE_MEMORY";created_utc="2026-01-01T00:00:00Z"}
Write-Utf8 -Path (Join-Path $RepoA ".pie\memory\memory.ndjson") -Text ($RepoRecord | ConvertTo-Json -Compress)

& (Join-Path $RepoRoot "scripts\pie_memory_resolve_v1.ps1") -RepoRoot $RepoRoot -SessionId $SessionId -Query "memory" -MemoryRoot $MemoryRoot -PolicyPath $PolicyOn | Out-Null
$Resolution = Get-Content -LiteralPath (Join-Path $Resumed.run_root "memory_resolve\latest_memory_resolution.md") -Raw
if($Resolution -notmatch $CodingText -or $Resolution -notmatch $ProjectAText -or $Resolution -notmatch "REPO_FILE_MEMORY"){ throw "PIE_DRIFT_EXPECTED_MEMORY_MISSING" }
if($Resolution -match $ActiveText -or $Resolution -match $ProjectBText){ throw "PIE_DRIFT_CROSS_PROJECT_MEMORY_LEAK" }

$ForgedText = "FORGED_PROJECT_IDENTITY_MEMORY"
$ForgedId = PIE_MemoryId -Lane "project" -Project "shared" -ProjectRepo $RepoA -Text $ForgedText
$Forged = [ordered]@{schema="pie.memory.record.v1";memory_id=$ForgedId;lane="project";project="shared";project_repo=$RepoA;project_identity_sha256=("0" * 64);text=$ForgedText;created_utc="2026-01-02T00:00:00Z"}
[System.IO.File]::AppendAllText((Join-Path $MemoryRoot "projects\a\memory.ndjson"),(($Forged | ConvertTo-Json -Compress) + "`n"),$Enc)
$IdentityDriftRejected = $false
try { & (Join-Path $RepoRoot "scripts\pie_memory_resolve_v1.ps1") -RepoRoot $RepoRoot -SessionId $SessionId -Query "memory" -MemoryRoot $MemoryRoot -PolicyPath $PolicyOn | Out-Null }
catch { if($_.Exception.Message -like "PIE_MEMORY_PROJECT_IDENTITY_DRIFT:*"){ $IdentityDriftRejected = $true } }
if(-not $IdentityDriftRejected){ throw "PIE_DRIFT_MEMORY_IDENTITY_FORGERY_ACCEPTED" }

$MemoryLock = PIE_AcquireMemoryLock -MemoryRoot $MemoryRoot
try {
  $PreviousErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  $MemoryBusyOutput = @(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $RepoRoot "scripts\pie_memory_accept_v1.ps1") -RepoRoot $RepoRoot -Text "must not race" -Lane coding -MemoryRoot $MemoryRoot -PolicyPath $PolicyOn 2>&1) -join "`n"
  $MemoryBusyExit = $LASTEXITCODE
  $ErrorActionPreference = $PreviousErrorActionPreference
}
finally {
  $ErrorActionPreference = "Stop"
  $MemoryLock.Dispose()
}
if($MemoryBusyExit -eq 0 -or $MemoryBusyOutput -notmatch "PIE_MEMORY_BUSY"){ throw "PIE_DRIFT_CONCURRENT_MEMORY_WRITE_NOT_BLOCKED" }

& (Join-Path $RepoRoot "scripts\pie_memory_resolve_v1.ps1") -RepoRoot $RepoRoot -SessionId $SessionId -Query "memory" -MemoryRoot $MemoryRoot -PolicyPath $PolicyOff | Out-Null
$OffResolution = Get-Content -LiteralPath (Join-Path $Resumed.run_root "memory_resolve\latest_memory_resolution.md") -Raw
foreach($Forbidden in @($ActiveText,$CodingText,$ProjectAText,$ProjectBText,"REPO_FILE_MEMORY")){
  if($OffResolution -match $Forbidden){ throw "PIE_DRIFT_MEMORY_OFF_LEAK" }
}

Write-Host "PIE_DRIFT_BOUNDARIES_SELFTEST_OK" -ForegroundColor Green
