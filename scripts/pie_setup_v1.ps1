param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$false)][string]$Profile = "core",
  [Parameter(Mandatory=$false)][switch]$SkipPull
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$RegistryPath = Join-Path $RepoRoot "models\PIE_MODEL_REGISTRY.v1.json"

if(-not (Test-Path -LiteralPath $RegistryPath -PathType Leaf)){
  throw ("PIE_MODEL_REGISTRY_MISSING: " + $RegistryPath)
}

$registry = Get-Content -LiteralPath $RegistryPath -Raw | ConvertFrom-Json

if(-not ($registry.profiles.PSObject.Properties.Name -contains $Profile)){
  throw ("PIE_MODEL_PROFILE_UNKNOWN: " + $Profile)
}

$profileObj = $registry.profiles.$Profile
$models = @($profileObj.models)

Write-Host ("PIE_SETUP_PROFILE: " + $Profile) -ForegroundColor Cyan

$ollama = Get-Command ollama -ErrorAction SilentlyContinue
if($null -eq $ollama){
  throw "PIE_SETUP_OLLAMA_MISSING: install Ollama first, then rerun setup. Future installer will automate this."
}

if(-not $SkipPull){
  foreach($m in $models){
    Write-Host ("PIE_SETUP_PULL_START: " + $m) -ForegroundColor Cyan
    & ollama pull $m
    if($LASTEXITCODE -ne 0){ throw ("PIE_SETUP_PULL_FAIL: " + $m) }
    Write-Host ("PIE_SETUP_PULL_OK: " + $m) -ForegroundColor Green
  }
}

Write-Host "PIE_SETUP_OK" -ForegroundColor Green
