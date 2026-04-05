param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$SessionId
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

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$sessionRoot  = Join-Path (Join-Path $RepoRoot "runs") $SessionId
$statePath    = Join-Path $sessionRoot "state\session.state.json"
$manifestPath = Join-Path $sessionRoot "session_manifest.json"
$receiptsPath = Join-Path $sessionRoot "receipts.ndjson"
$stdoutPath   = Join-Path $sessionRoot "stdout.log"

if(-not (Test-Path -LiteralPath $sessionRoot -PathType Container)){
  Die ("SESSION_NOT_FOUND: " + $SessionId)
}

$utc = [DateTime]::UtcNow.ToString("o")

$stateJson = Read-Utf8NoBom $statePath
$stateJson = [regex]::Replace($stateJson,'"status"\s*:\s*"[^"]*"','"status":"stopped"',1)
Write-Utf8NoBomLf $statePath $stateJson

$manifestJson = Read-Utf8NoBom $manifestPath
$manifestJson = [regex]::Replace($manifestJson,'"status"\s*:\s*"[^"]*"','"status":"stopped"',1)
Write-Utf8NoBomLf $manifestPath $manifestJson

Append-Utf8NoBomLf $receiptsPath (
  @(
    "{"
    '"schema":"pie.session.receipt.v1",'
    '"event":"session_stop",'
    ('"session_id":"' + (Escape-JsonString $SessionId) + '",')
    ('"utc":"' + (Escape-JsonString $utc) + '"')
    "}"
  ) -join ""
)

Append-Utf8NoBomLf $stdoutPath ("SESSION_STOP: " + $SessionId)

Write-Host ("PIE_AGENT_STOP_OK: " + $SessionId) -ForegroundColor Green
Write-Host $sessionRoot
$sessionRoot