param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$false)][ValidateSet("start","status")][string]$Action = "start",
  [Parameter(Mandatory=$false)][ValidateRange(1024,65535)][int]$Port = 4317,
  [Parameter(Mandatory=$false)][switch]$AllowMock
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Server = Join-Path $RepoRoot "workbench\server.js"
$Node = Get-Command node -ErrorAction SilentlyContinue

if($null -eq $Node){ throw "PIE_WORKBENCH_NODE_REQUIRED: Install Node.js 18 or newer." }
if(-not (Test-Path -LiteralPath $Server -PathType Leaf)){ throw ("PIE_WORKBENCH_SERVER_MISSING: " + $Server) }

if($Action -eq "status"){
  try {
    $Health = Invoke-RestMethod -Method Get -Uri ("http://127.0.0.1:" + $Port + "/health") -TimeoutSec 3
    if([string]$Health.status -ne "ok"){ throw "health status is not ok" }
    Write-Host ("PIE_WORKBENCH_RUNNING: http://127.0.0.1:" + $Port) -ForegroundColor Green
    exit 0
  }
  catch {
    Write-Host ("PIE_WORKBENCH_STOPPED: http://127.0.0.1:" + $Port)
    exit 0
  }
}

$NodeArgs = @($Server,"--repo-root",$RepoRoot,"--port",[string]$Port)
if($AllowMock){ $NodeArgs += "--allow-mock" }

Write-Host "PIE WORKBENCH" -ForegroundColor Cyan
Write-Host ("Open: http://127.0.0.1:" + $Port)
Write-Host "Press Ctrl+C to stop."
& $Node.Source @NodeArgs
exit $LASTEXITCODE
