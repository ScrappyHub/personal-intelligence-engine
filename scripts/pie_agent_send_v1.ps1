param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$SessionId,
  [Parameter(Mandatory=$true)][string]$Prompt,
  [Parameter(Mandatory=$false)][string]$BackendMode = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$Message){
  throw $Message
}

function Ensure-Dir([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Container)){
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

function Read-Utf8NoBom([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){
    Die ("MISSING_FILE: " + $Path)
  }
  $enc = New-Object System.Text.UTF8Encoding($false)
  return [System.IO.File]::ReadAllText($Path,$enc)
}

function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir){
    Ensure-Dir $dir
  }
  $enc = New-Object System.Text.UTF8Encoding($false)
  $t = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $t.EndsWith("`n")){
    $t += "`n"
  }
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}

function Append-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir){
    Ensure-Dir $dir
  }
  $enc = New-Object System.Text.UTF8Encoding($false)
  $existing = ""
  if(Test-Path -LiteralPath $Path -PathType Leaf){
    $existing = [System.IO.File]::ReadAllText($Path,$enc)
  }
  $append = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $append.EndsWith("`n")){
    $append += "`n"
  }
  [System.IO.File]::WriteAllText($Path,($existing + $append),$enc)
}

function Escape-JsonString([string]$Value){
  if($null -eq $Value){
    return ""
  }
  $s = $Value
  $s = $s.Replace('\','\\')
  $s = $s.Replace('"','\"')
  $s = $s.Replace("`t","\t")
  $s = $s.Replace("`r","\r")
  $s = $s.Replace("`n","\n")
  return $s
}

function Get-JsonStringValue([string]$Json,[string]$Key){
  $pattern = '"' + [regex]::Escape($Key) + '"\s*:\s*"([^"]*)"'
  $m = [regex]::Match($Json,$pattern)
  if(-not $m.Success){
    Die ("JSON_KEY_NOT_FOUND: " + $Key)
  }
  return $m.Groups[1].Value
}

function Get-JsonIntValue([string]$Json,[string]$Key){
  $pattern = '"' + [regex]::Escape($Key) + '"\s*:\s*([0-9]+)'
  $m = [regex]::Match($Json,$pattern)
  if(-not $m.Success){
    Die ("JSON_INT_KEY_NOT_FOUND: " + $Key)
  }
  return [int]$m.Groups[1].Value
}

function Set-JsonIntValue([string]$Json,[string]$Key,[int]$Value){
  $pattern = '"' + [regex]::Escape($Key) + '"\s*:\s*([0-9]+)'
  return [regex]::Replace(
    $Json,
    $pattern,
    ('"' + $Key + '":' + $Value),
    1
  )
}

function Invoke-BackendMock([string]$UserPrompt,[int]$MessageIndex,[string]$EffectiveBackendMode){
  $trim = $UserPrompt.Trim()
  if([string]::IsNullOrWhiteSpace($trim)){
    return "EMPTY_PROMPT_REJECTED"
  }
  return ("[mock:" + $EffectiveBackendMode + "][msg:" + $MessageIndex + "] " + $trim)
}

function Invoke-BackendExternal([string]$RepoRoot,[string]$SessionId,[string]$UserPrompt,[int]$MessageIndex){
  $cmd = [Environment]::GetEnvironmentVariable("PIE_LOCAL_BACKEND_CMD","Process")
  if([string]::IsNullOrWhiteSpace($cmd)){
    Die "PIE_BACKEND_CMD_NOT_SET"
  }

  $requestPath = Join-Path (Join-Path (Join-Path $RepoRoot "runs") $SessionId) "state\backend_request.json"
  $responsePath = Join-Path (Join-Path (Join-Path $RepoRoot "runs") $SessionId) "state\backend_response.txt"

  $request = @(
    "{"
    ('  "session_id":"' + (Escape-JsonString $SessionId) + '",')
    ('  "message_index":' + $MessageIndex + ',')
    ('  "prompt":"' + (Escape-JsonString $UserPrompt) + '"')
    "}"
  ) -join "`n"

  Write-Utf8NoBomLf $requestPath $request

  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $cmd
  $psi.Arguments = ('"' + $requestPath + '" "' + $responsePath + '"')
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.CreateNoWindow = $true

  $p = New-Object System.Diagnostics.Process
  $p.StartInfo = $psi
  [void]$p.Start()
  $stdout = $p.StandardOutput.ReadToEnd()
  $stderr = $p.StandardError.ReadToEnd()
  $p.WaitForExit()

  if($p.ExitCode -ne 0){
    Die ("PIE_BACKEND_CMD_FAILED exit=" + $p.ExitCode + " stderr=" + $stderr)
  }

  if(-not (Test-Path -LiteralPath $responsePath -PathType Leaf)){
    Die ("PIE_BACKEND_RESPONSE_MISSING: " + $responsePath)
  }

  $response = Read-Utf8NoBom $responsePath
  $response = $response.Trim()

  if([string]::IsNullOrWhiteSpace($response)){
    Die "PIE_BACKEND_EMPTY_RESPONSE"
  }

  return $response
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$sessionRoot = Join-Path (Join-Path $RepoRoot "runs") $SessionId
$manifestPath = Join-Path $sessionRoot "session_manifest.json"
$transcriptPath = Join-Path $sessionRoot "transcript.ndjson"
$receiptsPath = Join-Path $sessionRoot "receipts.ndjson"
$stdoutPath = Join-Path $sessionRoot "stdout.log"
$statePath = Join-Path $sessionRoot "state\session.state.json"

if(-not (Test-Path -LiteralPath $sessionRoot -PathType Container)){
  Die ("SESSION_NOT_FOUND: " + $SessionId)
}

$stateJson = Read-Utf8NoBom $statePath
$currentCount = Get-JsonIntValue $stateJson "message_count"
$messageIndex = $currentCount + 1

$effectiveBackendMode = $BackendMode
if([string]::IsNullOrWhiteSpace($effectiveBackendMode)){
  $effectiveBackendMode = Get-JsonStringValue $stateJson "backend_mode"
}

$userUtc = [DateTime]::UtcNow.ToString("o")

$userLine = @(
  "{"
  '"schema":"pie.transcript.line.v1",'
  '"role":"user",'
  ('"session_id":"' + (Escape-JsonString $SessionId) + '",')
  ('"message_index":' + $messageIndex + ',')
  ('"utc":"' + (Escape-JsonString $userUtc) + '",')
  ('"content":"' + (Escape-JsonString $Prompt) + '"')
  "}"
) -join ""

Append-Utf8NoBomLf $transcriptPath $userLine

$responseText = ""
if($effectiveBackendMode -eq "mock"){
  $responseText = Invoke-BackendMock $Prompt $messageIndex $effectiveBackendMode
} else {
  $responseText = Invoke-BackendExternal $RepoRoot $SessionId $Prompt $messageIndex
}

$assistantUtc = [DateTime]::UtcNow.ToString("o")

$assistantLine = @(
  "{"
  '"schema":"pie.transcript.line.v1",'
  '"role":"assistant",'
  ('"session_id":"' + (Escape-JsonString $SessionId) + '",')
  ('"message_index":' + $messageIndex + ',')
  ('"utc":"' + (Escape-JsonString $assistantUtc) + '",')
  ('"content":"' + (Escape-JsonString $responseText) + '"')
  "}"
) -join ""

Append-Utf8NoBomLf $transcriptPath $assistantLine

Append-Utf8NoBomLf $receiptsPath (
  @(
    "{"
    '"schema":"pie.session.receipt.v1",'
    '"event":"message_roundtrip",'
    ('"session_id":"' + (Escape-JsonString $SessionId) + '",')
    ('"message_index":' + $messageIndex + ',')
    ('"backend_mode":"' + (Escape-JsonString $effectiveBackendMode) + '",')
    ('"user_utc":"' + (Escape-JsonString $userUtc) + '",')
    ('"assistant_utc":"' + (Escape-JsonString $assistantUtc) + '"')
    "}"
  ) -join ""
)

Append-Utf8NoBomLf $stdoutPath ("PROMPT[" + $messageIndex + "]: " + $Prompt)
Append-Utf8NoBomLf $stdoutPath ("RESPONSE[" + $messageIndex + "]: " + $responseText)

$stateJson = Set-JsonIntValue $stateJson "message_count" $messageIndex
Write-Utf8NoBomLf $statePath $stateJson

Write-Host ("PIE_AGENT_SEND_OK: " + $SessionId + " message_index=" + $messageIndex) -ForegroundColor Green
Write-Host $responseText

$responseText