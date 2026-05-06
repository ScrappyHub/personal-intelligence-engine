param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$false)]
  [ValidateSet("core","coding","general")]
  [string]$Profile = "core"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Models = @()

if($Profile -eq "core"){
  $Models = @("qwen2.5-coder:7b")
}
elseif($Profile -eq "coding"){
  $Models = @("qwen2.5-coder:7b")
}
elseif($Profile -eq "general"){
  $Models = @("qwen2.5:3b","llama3.1:8b","gemma3:latest")
}

foreach($m in $Models){
  Write-Host ("PIE_MODEL_PULL_START: " + $m) -ForegroundColor Cyan
  ollama pull $m
  if($LASTEXITCODE -ne 0){
    throw ("PIE_MODEL_PULL_FAIL: " + $m)
  }
  Write-Host ("PIE_MODEL_PULL_OK: " + $m) -ForegroundColor Green
}

Write-Host "PIE_MODEL_PROFILE_PULL_OK" -ForegroundColor Green