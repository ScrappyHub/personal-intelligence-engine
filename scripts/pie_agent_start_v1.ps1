param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$false)][string]$SessionId,
  [Parameter(Mandatory=$false)][string]$ModelId = "local-default",
  [Parameter(Mandatory=$false)][string]$BackendMode = "mock"
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

function New-SessionId(){
  $utc = [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssZ")
  $guid = [Guid]::NewGuid().ToString("N")
  return ("session_" + $utc + "_" + $guid)
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

if([string]::IsNullOrWhiteSpace($SessionId)){
  $SessionId = New-SessionId
}

$runsRoot = Join-Path $RepoRoot "runs"
$sessionRoot = Join-Path $runsRoot $SessionId
$stateRoot = Join-Path $sessionRoot "state"

Ensure-Dir $runsRoot
Ensure-Dir $sessionRoot
Ensure-Dir $stateRoot

$manifestPath = Join-Path $sessionRoot "session_manifest.json"
$transcriptPath = Join-Path $sessionRoot "transcript.ndjson"
$receiptsPath = Join-Path $sessionRoot "receipts.ndjson"
$stdoutPath = Join-Path $sessionRoot "stdout.log"
$stderrPath = Join-Path $sessionRoot "stderr.log"
$statePath = Join-Path $stateRoot "session.state.json"

if(Test-Path -LiteralPath $manifestPath -PathType Leaf){
  Die ("SESSION_ALREADY_EXISTS: " + $SessionId)
}

$startedUtc = [DateTime]::UtcNow.ToString("o")

$manifest = @(
  "{"
  '  "schema":"pie.session_manifest.v1",'
  ('  "session_id":"' + (Escape-JsonString $SessionId) + '",')
  ('  "model_id":"' + (Escape-JsonString $ModelId) + '",')
  ('  "backend_mode":"' + (Escape-JsonString $BackendMode) + '",')
  ('  "started_utc":"' + (Escape-JsonString $startedUtc) + '",')
  '  "status":"open",'
  '  "message_count":0'
  "}"
) -join "`n"

$state = @(
  "{"
  '  "schema":"pie.session_state.v1",'
  ('  "session_id":"' + (Escape-JsonString $SessionId) + '",')
  ('  "model_id":"' + (Escape-JsonString $ModelId) + '",')
  ('  "backend_mode":"' + (Escape-JsonString $BackendMode) + '",')
  '  "message_count":0,'
  '  "status":"open"'
  "}"
) -join "`n"

$receipt = @(
  "{"
  '"schema":"pie.session.receipt.v1",'
  '"event":"session_started",'
  ('"session_id":"' + (Escape-JsonString $SessionId) + '",')
  ('"utc":"' + (Escape-JsonString $startedUtc) + '",')
  ('"model_id":"' + (Escape-JsonString $ModelId) + '",')
  ('"backend_mode":"' + (Escape-JsonString $BackendMode) + '"')
  "}"
) -join ""

Write-Utf8NoBomLf $manifestPath $manifest
Write-Utf8NoBomLf $statePath $state
Write-Utf8NoBomLf $transcriptPath ""
Write-Utf8NoBomLf $receiptsPath $receipt
Write-Utf8NoBomLf $stdoutPath ""
Write-Utf8NoBomLf $stderrPath ""

Write-Host ("PIE_AGENT_START_OK: " + $SessionId) -ForegroundColor Green
Write-Host $sessionRoot