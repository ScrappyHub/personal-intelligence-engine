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
$ModelsScript = Join-Path $RepoRoot "scripts\pie_models_v1.ps1"

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $ModelsScript -RepoRoot $RepoRoot -Action validate | Out-Host
if($LASTEXITCODE -ne 0){ throw "PIE_SETUP_MODEL_REGISTRY_INVALID" }

Write-Host ("PIE_SETUP_PROFILE: " + $Profile) -ForegroundColor Cyan

if(-not $SkipPull){
  foreach($m in $models){
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
      -File $ModelsScript -RepoRoot $RepoRoot -Action pull -Model $m
    if($LASTEXITCODE -ne 0){ throw ("PIE_SETUP_PULL_FAIL: " + $m) }
  }
}

if(@($models).Count -gt 0 -and -not $SkipPull){
  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File $ModelsScript -RepoRoot $RepoRoot -Action use -Model ([string]$models[0])
  if($LASTEXITCODE -ne 0){ throw "PIE_SETUP_MODEL_SELECT_FAIL" }
}

Write-Host "PIE_SETUP_OK" -ForegroundColor Green
