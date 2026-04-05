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

$RequestPath  = (Resolve-Path -LiteralPath $RequestPath).Path
$requestJson  = Read-Utf8NoBom $RequestPath
$sessionId    = Get-JsonStringValue $requestJson "session_id"
$messageIndex = Get-JsonIntValue $requestJson "message_index"
$prompt       = Get-JsonStringValue $requestJson "prompt"

$trim = $prompt.Trim()
if([string]::IsNullOrWhiteSpace($trim)){
  Die "EMPTY_PROMPT_REJECTED"
}

$response = "[local-mock][session:$sessionId][msg:$messageIndex] $trim"
Write-Utf8NoBomLf $ResponsePath $response
Write-Host ("PIE_BACKEND_LOCAL_MOCK_OK: " + $ResponsePath) -ForegroundColor Green