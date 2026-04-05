param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$SessionId,
  [Parameter(Mandatory=$true)][string]$ModelId,
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

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$sessionRoot   = Join-Path (Join-Path $RepoRoot "runs") $SessionId
$stateDir      = Join-Path $sessionRoot "state"
$manifestPath  = Join-Path $sessionRoot "session_manifest.json"
$statePath     = Join-Path $stateDir "session.state.json"
$transcript    = Join-Path $sessionRoot "transcript.ndjson"
$receipts      = Join-Path $sessionRoot "receipts.ndjson"
$stdoutLog     = Join-Path $sessionRoot "stdout.log"

if(Test-Path -LiteralPath $sessionRoot -PathType Container){
  Die ("SESSION_ALREADY_EXISTS: " + $SessionId)
}

Ensure-Dir $sessionRoot
Ensure-Dir $stateDir

$utc = [DateTime]::UtcNow.ToString("o")

$manifest = @(
  "{"
  '  "schema":"pie.session_manifest.v1",'
  ('  "session_id":"' + (Escape-JsonString $SessionId) + '",')
  ('  "model_id":"' + (Escape-JsonString $ModelId) + '",')
  ('  "backend_mode":"' + (Escape-JsonString $BackendMode) + '",')
  ('  "created_utc":"' + (Escape-JsonString $utc) + '",')
  '  "status":"running"'
  "}"
) -join "`n"

$state = @(
  "{"
  '  "schema":"pie.session_state.v1",'
  ('  "session_id":"' + (Escape-JsonString $SessionId) + '",')
  ('  "model_id":"' + (Escape-JsonString $ModelId) + '",')
  ('  "backend_mode":"' + (Escape-JsonString $BackendMode) + '",')
  '  "message_count":0,'
  '  "status":"running"'
  "}"
) -join "`n"

Write-Utf8NoBomLf $manifestPath $manifest
Write-Utf8NoBomLf $statePath $state
Write-Utf8NoBomLf $transcript ""
Write-Utf8NoBomLf $receipts (
  @(
    "{"
    '"schema":"pie.session.receipt.v1",'
    '"event":"session_start",'
    ('"session_id":"' + (Escape-JsonString $SessionId) + '",')
    ('"model_id":"' + (Escape-JsonString $ModelId) + '",')
    ('"backend_mode":"' + (Escape-JsonString $BackendMode) + '",')
    ('"utc":"' + (Escape-JsonString $utc) + '"')
    "}"
  ) -join ""
)
Write-Utf8NoBomLf $stdoutLog ("SESSION_START: " + $SessionId)

Write-Host ("PIE_AGENT_START_OK: " + $SessionId) -ForegroundColor Green
Write-Host $sessionRoot
$sessionRoot