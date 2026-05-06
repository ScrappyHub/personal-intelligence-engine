param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$SessionId,
  [Parameter(Mandatory=$true)][string]$Message
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)

$BackendFile = Join-Path $RunRoot "backend.txt"
$ModelFile   = Join-Path $RunRoot "model.txt"
$HistoryFile = Join-Path $RunRoot "conversation.ndjson"

if(-not (Test-Path -LiteralPath $RunRoot -PathType Container)){ throw ("PIE_SESSION_NOT_STARTED: " + $SessionId) }
if(-not (Test-Path -LiteralPath $BackendFile -PathType Leaf)){ throw ("PIE_SESSION_MISSING_BACKEND: " + $BackendFile) }
if(-not (Test-Path -LiteralPath $ModelFile -PathType Leaf)){ throw ("PIE_SESSION_MISSING_MODEL: " + $ModelFile) }

$Backend = ([System.IO.File]::ReadAllText($BackendFile)).Trim()
$Model   = ([System.IO.File]::ReadAllText($ModelFile)).Trim()

if($Backend -ne "ollama"){ throw ("PIE_BACKEND_UNSUPPORTED: " + $Backend) }

$BackendScript = Join-Path $RepoRoot "scripts\pie_backend_ollama_cmd_v1.ps1"
if(-not (Test-Path -LiteralPath $BackendScript -PathType Leaf)){ throw ("PIE_BACKEND_SCRIPT_MISSING: " + $BackendScript) }

$HistoryText = ""
if(Test-Path -LiteralPath $HistoryFile -PathType Leaf){
  $raw = Get-Content -LiteralPath $HistoryFile -Raw -ErrorAction SilentlyContinue
  if(-not [string]::IsNullOrWhiteSpace($raw)){
    $HistoryText = "HISTORY:`n" + $raw + "`n"
  }
}

$FullMessage = $HistoryText + "USER:`n" + $Message

# IMPORTANT: call backend in-process, not through powershell.exe argument splitting.
$Response = @(& $BackendScript -Model $Model -Message $FullMessage)

$RespText = ($Response -join "`n")
$Now = [DateTime]::UtcNow.ToString("o")
$EscMsg = $Message.Replace("\","\\").Replace('"','\"').Replace("`r`n","\n").Replace("`n","\n")
$EscResp = $RespText.Replace("\","\\").Replace('"','\"').Replace("`r`n","\n").Replace("`n","\n")

$Line = '{"ts":"' + $Now + '","session_id":"' + $SessionId + '","message":"' + $EscMsg + '","response":"' + $EscResp + '"}' + "`n"
[System.IO.File]::AppendAllText($HistoryFile,$Line,[System.Text.UTF8Encoding]::new($false))

Write-Host ("PIE_AGENT_SEND_OK: " + $SessionId) -ForegroundColor Green
$RespText
