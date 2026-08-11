param([Parameter(Mandatory=$true)][string]$RepoRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$ModelsScript = Join-Path $RepoRoot "scripts\pie_models_v1.ps1"
$RegistryPath = Join-Path $RepoRoot "models\PIE_MODEL_REGISTRY.v1.json"
$TestRoot = Join-Path $RepoRoot "runs\pie_model_registry_selftest"
if(Test-Path -LiteralPath $TestRoot -PathType Container){ Remove-Item -LiteralPath $TestRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path $TestRoot | Out-Null

& $ModelsScript -RepoRoot $RepoRoot -Action validate | Out-Host
$CatalogJson = & $ModelsScript -RepoRoot $RepoRoot -Action "catalog-json"
$Catalog = ([string]($CatalogJson -join "`n")) | ConvertFrom-Json
if([string]$Catalog.schema -ne "pie.model.catalog.v1"){ throw "PIE_MODEL_REGISTRY_SELFTEST_CATALOG_SCHEMA_BAD" }
if(@($Catalog.models).Count -lt 14){ throw "PIE_MODEL_REGISTRY_SELFTEST_CATALOG_TOO_SMALL" }
$Names = @($Catalog.models | ForEach-Object { [string]$_.name })
if(@($Names | Sort-Object -Unique).Count -ne $Names.Count){ throw "PIE_MODEL_REGISTRY_SELFTEST_DUPLICATE_NAME" }
foreach($Entry in @($Catalog.models)){
  if([int64]$Entry.size_bytes -lt 100MB -or [int]$Entry.min_ram_gb -lt 1){ throw ("PIE_MODEL_REGISTRY_SELFTEST_REQUIREMENTS_BAD: " + [string]$Entry.name) }
  if(([string]$Entry.source) -notmatch '^https://(www\.)?ollama\.com/library/'){ throw ("PIE_MODEL_REGISTRY_SELFTEST_SOURCE_BAD: " + [string]$Entry.name) }
}

$Broken = Get-Content -LiteralPath $RegistryPath -Raw | ConvertFrom-Json
$Broken.catalog[1].name = [string]$Broken.catalog[0].name
$BrokenPath = Join-Path $TestRoot "duplicate_registry.json"
$Broken | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath $BrokenPath -Encoding UTF8
$DuplicateRejected = $false
try { & $ModelsScript -RepoRoot $RepoRoot -Action validate -RegistryPath $BrokenPath | Out-Null }
catch { if($_.Exception.Message -like "PIE_MODEL_REGISTRY_NAME_DUPLICATE:*"){ $DuplicateRejected = $true } }
if(-not $DuplicateRejected){ throw "PIE_MODEL_REGISTRY_SELFTEST_DUPLICATE_ALLOWED" }

Write-Host "PIE_MODEL_REGISTRY_SELFTEST_OK" -ForegroundColor Green
