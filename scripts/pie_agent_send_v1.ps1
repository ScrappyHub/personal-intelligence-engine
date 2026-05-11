param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$SessionId,
  [Parameter(Mandatory=$false)][string]$Message = "",
  [Parameter(Mandatory=$false)][string]$MessagePath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)

$BackendFile = Join-Path $RunRoot "backend.txt"
$ModelFile = Join-Path $RunRoot "model.txt"
$HistoryFile = Join-Path $RunRoot "conversation.ndjson"
$PromptRoot = Join-Path $RunRoot "sent_prompts"

$Enc = New-Object System.Text.UTF8Encoding($false)

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

  $Message = Get-Content -LiteralPath $MessagePath -Raw
}

if([string]::IsNullOrWhiteSpace($Message)){
  throw "PIE_AGENT_MESSAGE_REQUIRED"
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

$HistoryText = ""

if(Test-Path -LiteralPath $HistoryFile -PathType Leaf){

  $RawHistory = Get-Content -LiteralPath $HistoryFile -Raw -ErrorAction SilentlyContinue

  if(-not [string]::IsNullOrWhiteSpace($RawHistory)){

    if($RawHistory.Length -gt 12000){
      $RawHistory = $RawHistory.Substring($RawHistory.Length - 12000)
    }

    $HistoryText = "RECENT_HISTORY_NDJSON:`n" + $RawHistory.Trim() + "`n`n"
  }
}

$FullMessage = $HistoryText + "CURRENT_USER_CONTEXT_PACKET_OR_MESSAGE:`n" + $Message

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
$PromptPath = Join-Path $PromptRoot ("prompt_" + $Stamp + ".txt")
$BackendOut = Join-Path $PromptRoot ("backend_stdout_" + $Stamp + ".txt")
$BackendErr = Join-Path $PromptRoot ("backend_stderr_" + $Stamp + ".txt")

Write-Utf8NoBomLf -Path $PromptPath -Text $FullMessage

$EnsureOllama = Join-Path $RepoRoot "scripts\pie_ollama_ensure_v1.ps1"

if(Test-Path -LiteralPath $EnsureOllama -PathType Leaf){
  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File $EnsureOllama | Out-Null

  if($LASTEXITCODE -ne 0){
    throw "PIE_OLLAMA_ENSURE_FAIL"
  }
}

$BackendArgs = @(
  "-NoProfile",
  "-NonInteractive",
  "-ExecutionPolicy","Bypass",
  "-File",$BackendScript,
  "-Model",$Model,
  "-MessagePath",$PromptPath
)

$Proc = Start-Process `
  -FilePath "powershell.exe" `
  -ArgumentList $BackendArgs `
  -NoNewWindow `
  -PassThru `
  -Wait `
  -RedirectStandardOutput $BackendOut `
  -RedirectStandardError $BackendErr

$OutTextPre = ""

if(Test-Path -LiteralPath $BackendOut -PathType Leaf){
  $OutTextPre = Get-Content -LiteralPath $BackendOut -Raw
}

$ErrTextPre = ""

if(Test-Path -LiteralPath $BackendErr -PathType Leaf){
  $ErrTextPre = Get-Content -LiteralPath $BackendErr -Raw
}

$ExitCodeText = [string]$Proc.ExitCode
$HasUsableOutput = -not [string]::IsNullOrWhiteSpace($OutTextPre)

if((-not [string]::IsNullOrWhiteSpace($ExitCodeText)) -and ([int]$Proc.ExitCode -ne 0)){
  throw ("PIE_AGENT_BACKEND_SEND_FAIL: exit=" + $ExitCodeText + " stdout=" + $BackendOut + " stderr=" + $BackendErr + "`nSTDERR:`n" + $ErrTextPre + "`nSTDOUT:`n" + $OutTextPre)
}

if([string]::IsNullOrWhiteSpace($ExitCodeText) -and -not $HasUsableOutput){
  throw ("PIE_AGENT_BACKEND_SEND_FAIL: exit_empty stdout=" + $BackendOut + " stderr=" + $BackendErr + "`nSTDERR:`n" + $ErrTextPre + "`nSTDOUT:`n" + $OutTextPre)
}

$Response = @()

if(Test-Path -LiteralPath $BackendOut -PathType Leaf){
  $Response = @(Get-Content -LiteralPath $BackendOut)
}

$RespText = ($Response -join "`n").Trim()

if([string]::IsNullOrWhiteSpace($RespText)){
  throw ("PIE_AGENT_EMPTY_RESPONSE: stdout=" + $BackendOut + " stderr=" + $BackendErr)
}

$Now = [DateTime]::UtcNow.ToString("o")
$EscMsg = Escape-JsonString -Value $Message
$EscResp = Escape-JsonString -Value $RespText
$EscPrompt = Escape-JsonString -Value $PromptPath

$Line = '{"ts":"' + $Now + '","schema":"pie.conversation.turn.v1","session_id":"' + $SessionId + '","prompt_path":"' + $EscPrompt + '","message":"' + $EscMsg + '","response":"' + $EscResp + '"}' + "`n"

[System.IO.File]::AppendAllText($HistoryFile,$Line,$Enc)

Write-Host ("PIE_AGENT_SEND_OK: " + $SessionId) -ForegroundColor Green
Write-Output $RespText