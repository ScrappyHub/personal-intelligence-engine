param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
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
  if($dir){ Ensure-Dir $dir }
  $enc = New-Object System.Text.UTF8Encoding($false)
  $t = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}

function Read-Utf8NoBom([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){
    Die ("MISSING_FILE: " + $Path)
  }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::ReadAllText($Path,$enc)
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$RunRoot = Join-Path $RepoRoot "proofs\runs\backend_mock_smoke"
$RequestPath = Join-Path $RunRoot "backend_request.json"
$ResponsePath = Join-Path $RunRoot "backend_response.txt"

if(Test-Path -LiteralPath $RunRoot -PathType Container){
  Remove-Item -LiteralPath $RunRoot -Recurse -Force
}
Ensure-Dir $RunRoot

$request = @(
  "{"
  '  "session_id":"backend_smoke_1",'
  '  "message_index":1,'
  '  "prompt":"hello from backend smoke"'
  "}"
) -join "`n"

Write-Utf8NoBomLf $RequestPath $request

$PSExe = (Get-Command powershell.exe -ErrorAction Stop).Source
$Backend = Join-Path $RepoRoot "scripts\pie_agent_backend_mock_v1.ps1"

$p = Start-Process -FilePath $PSExe -ArgumentList @(
  "-NoProfile",
  "-NonInteractive",
  "-ExecutionPolicy","Bypass",
  "-File",$Backend,
  "-RequestPath",$RequestPath,
  "-ResponsePath",$ResponsePath
) -Wait -NoNewWindow -PassThru

if($p.ExitCode -ne 0){
  Die ("BACKEND_PROCESS_FAIL: exit=" + $p.ExitCode)
}

$response = (Read-Utf8NoBom $ResponsePath).Trim()
if([string]::IsNullOrWhiteSpace($response)){
  Die "BACKEND_EMPTY_RESPONSE"
}
if($response -notmatch 'hello from backend smoke'){
  Die ("BACKEND_BAD_RESPONSE: " + $response)
}

Write-Host ("PIE_BACKEND_MOCK_SMOKE_OK: " + $response) -ForegroundColor Green