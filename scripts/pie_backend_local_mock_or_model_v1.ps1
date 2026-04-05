param(
  [Parameter(Mandatory=$true)][string]$RequestPath,
  [Parameter(Mandatory=$true)][string]$ResponsePath
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

function Get-JsonStringValue([string]$Json,[string]$Key){
  $pattern = '"' + [regex]::Escape($Key) + '"\s*:\s*"((?:\\.|[^"])*)"'
  $m = [regex]::Match($Json,$pattern)
  if(-not $m.Success){
    Die ("JSON_KEY_NOT_FOUND: " + $Key)
  }
  $v = $m.Groups[1].Value
  $v = $v.Replace('\"','"')
  $v = $v.Replace('\\','\')
  $v = $v.Replace('\r',"`r")
  $v = $v.Replace('\n',"`n")
  $v = $v.Replace('\t',"`t")
  return $v
}

# -------------------------------------------------------------------
# Tier-0 backend mode switch
# MODEL_BACKEND_MODE=mock  -> deterministic local mock
# MODEL_BACKEND_MODE=llama -> call local llama.cpp server/CLI wrapper later
# -------------------------------------------------------------------
$mode = [Environment]::GetEnvironmentVariable("MODEL_BACKEND_MODE","Process")
if([string]::IsNullOrWhiteSpace($mode)){
  $mode = "mock"
}

$requestJson = Read-Utf8NoBom $RequestPath
$sessionId   = Get-JsonStringValue $requestJson "session_id"
$prompt      = Get-JsonStringValue $requestJson "prompt"

$response = ""

switch ($mode) {
  "mock" {
    $trim = $prompt.Trim()
    if([string]::IsNullOrWhiteSpace($trim)){
      $response = "EMPTY_PROMPT_REJECTED"
    } else {
      $response = ("[external-mock][" + $sessionId + "] " + $trim)
    }
  }

  "llama" {
    Die "LLAMA_BACKEND_NOT_YET_WIRED"
  }

  default {
    Die ("UNKNOWN_MODEL_BACKEND_MODE: " + $mode)
  }
}

Write-Utf8NoBomLf $ResponsePath $response
Write-Host ("PIE_BACKEND_LOCAL_OK mode=" + $mode) -ForegroundColor Green