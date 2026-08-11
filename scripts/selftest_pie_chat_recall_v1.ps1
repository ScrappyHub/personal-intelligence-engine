param([Parameter(Mandatory=$true)][string]$RepoRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$SessionId = "pie_chat_recall_selftest"
$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)
$Fixture = Join-Path $RepoRoot "runs\pie_chat_recall_fixture"
foreach($Path in @($RunRoot,$Fixture)){ if(Test-Path -LiteralPath $Path -PathType Container){ Remove-Item -LiteralPath $Path -Recurse -Force } }
New-Item -ItemType Directory -Force -Path $Fixture | Out-Null
[System.IO.File]::WriteAllText((Join-Path $Fixture "README.md"),"# Recall fixture`n",(New-Object System.Text.UTF8Encoding($false)))

$Chat = Join-Path $RepoRoot "scripts\pie_chat_v1.ps1"
& $Chat -RepoRoot $RepoRoot -SessionId $SessionId -Model "chat-recall-mock" -Backend mock -ProjectRepo $Fixture -Goal "recall exact chat" -SetupOnly | Out-Null
& (Join-Path $RepoRoot "scripts\pie_ask_v1.ps1") -RepoRoot $RepoRoot -SessionId $SessionId -Message "remember the exact visible message" -TimeoutSeconds 30 -MaxAttempts 1 | Out-Null
& (Join-Path $RepoRoot "scripts\pie_agent_stop_v1.ps1") -RepoRoot $RepoRoot -SessionId $SessionId | Out-Null

$Reopen = @(& $Chat -RepoRoot $RepoRoot -SessionId $SessionId -Model "ignored-model" -Backend mock -SetupOnly 6>&1) -join "`n"
if($Reopen -notmatch "PIE_AGENT_RESUME_OK" -or $Reopen -notmatch "Recalled 1 verified turn" -or $Reopen -notmatch "remember the exact visible message"){
  throw "PIE_CHAT_RECALL_OUTPUT_BAD"
}
. (Join-Path $RepoRoot "scripts\_lib_pie_agent_session_v1.ps1")
$Session = PIE_GetAgentSession -RepoRoot $RepoRoot -SessionId $SessionId -RequireRunning -RequireIntegrity
if($Session.project_repo -ine (Resolve-Path $Fixture).Path -or $Session.goal -ne "recall exact chat" -or @($Session.conversation_turns).Count -ne 1){
  throw "PIE_CHAT_RECALL_BINDING_BAD"
}
if([string]$Session.conversation_turns[0].message -ne "remember the exact visible message"){ throw "PIE_CHAT_RECALL_MESSAGE_NOT_EXACT" }
$ChatMeta = Get-Content -LiteralPath (Join-Path $RunRoot "session.json") -Raw | ConvertFrom-Json
if([string]$ChatMeta.schema -ne "pie.chat.session.v2" -or [string]$ChatMeta.binding_sha256 -ne $Session.binding_sha256){ throw "PIE_CHAT_META_BAD" }

$Rejected = $false
try { & $Chat -RepoRoot $RepoRoot -SessionId $SessionId -Model "chat-recall-mock" -Backend mock -ProjectRepo $RepoRoot -SetupOnly | Out-Null }
catch { if($_.Exception.Message -like "PIE_CHAT_PROJECT_SWITCH_REQUIRES_NEW_SESSION:*"){ $Rejected = $true } }
if(-not $Rejected){ throw "PIE_CHAT_PROJECT_SWITCH_ALLOWED" }
$After = PIE_GetAgentSession -RepoRoot $RepoRoot -SessionId $SessionId -RequireIntegrity
if($After.binding_sha256 -ne $Session.binding_sha256 -or @($After.conversation_turns).Count -ne 1){ throw "PIE_CHAT_REJECT_MUTATED_SESSION" }

Write-Host "PIE_CHAT_RECALL_SELFTEST_OK" -ForegroundColor Green
