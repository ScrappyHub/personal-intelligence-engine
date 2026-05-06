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
$ModelFile = Join-Path $RunRoot "model.txt"

if(-not (Test-Path -LiteralPath $RunRoot -PathType Container)){
  throw ("PIE_SESSION_NOT_STARTED: " + $SessionId)
}
if(-not (Test-Path -LiteralPath $BackendFile -PathType Leaf)){
  throw ("PIE_SESSION_MISSING_BACKEND: " + $BackendFile)
}
if(-not (Test-Path -LiteralPath $ModelFile -PathType Leaf)){
  throw ("PIE_SESSION_MISSING_MODEL: " + $ModelFile)
}

$Backend = ([System.IO.File]::ReadAllText($BackendFile)).Trim()
$Model = ([System.IO.File]::ReadAllText($ModelFile)).Trim()

if($Backend -ne "ollama"){
  throw ("PIE_BACKEND_UNSUPPORTED: " + $Backend)
}

$BackendScript = Join-Path $RepoRoot "scripts\pie_backend_ollama_cmd_v1.ps1"
if(-not (Test-Path -LiteralPath $BackendScript -PathType Leaf)){
  throw ("PIE_BACKEND_SCRIPT_MISSING: " + $BackendScript)
}

$Response = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File $BackendScript `
  -Model $Model `
  -Message $Message

$Transcript = Join-Path $RunRoot "conversation.ndjson"
$Enc = New-Object System.Text.UTF8Encoding($false)
$Now = [DateTime]::UtcNow.ToString("o")

$SafeMsg = $Message.Replace("\","\\").Replace('"','\"')
$SafeResp = (($Response -join "`n")).Replace("\","\\").Replace('"','\"').Replace("`r`n","\n").Replace("`n","\n")

$Line = '{"ts":"' + $Now + '","session_id":"' + $SessionId + '","message":"' + $SafeMsg + '","response":"' + $SafeResp + '"}' + "`n"
[System.IO.File]::AppendAllText($Transcript,$Line,$Enc)

Write-Host ("PIE_AGENT_SEND_OK: " + $SessionId) -ForegroundColor Green
$Response
