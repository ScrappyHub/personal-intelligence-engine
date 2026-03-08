param([Parameter(Mandatory=$true)][string]$RepoRoot,[Parameter(Mandatory=$true)][string]$ModelId)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
. (Join-Path $RepoRoot "scripts\_lib_neverlost_v1.ps1")
. (Join-Path $RepoRoot "scripts\_lib_pie_v1.ps1")
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

function PIE_Die2([string]$m){ throw $m }
function PIE_ReadAllBytes([string]$Path){ if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ PIE_Die2 ("missing_file: " + $Path) }; return [System.IO.File]::ReadAllBytes($Path) }
function PIE_Sha256HexFile2([string]$Path){ PIE_Sha256HexBytes (PIE_ReadAllBytes $Path) }

$modelDir = Join-Path $RepoRoot ("models\" + $ModelId)
if (-not (Test-Path -LiteralPath $modelDir -PathType Container)) { PIE_Die ("missing_model_dir: " + $modelDir) }
$weightsDir = Join-Path $modelDir "weights"
if (-not (Test-Path -LiteralPath $weightsDir -PathType Container)) { PIE_Die ("missing_weights_dir: " + $weightsDir + " (Option B required)") }
$weightFiles = @(@(Get-ChildItem -LiteralPath $weightsDir -File -Recurse | ForEach-Object { $_.FullName }))
if ($weightFiles.Count -lt 1) { PIE_Die ("no_weight_files_found: " + $weightsDir) }

# Ensure source.json exists (template if missing)
$srcPath = Join-Path $modelDir "source.json"
if (-not (Test-Path -LiteralPath $srcPath -PathType Leaf)) {
  $tmpl = @{ schema="pie.model.source.v1"; model_id=$ModelId; origin=""; notes=""; created_utc=(Get-Date).ToUniversalTime().ToString("o") }
  NL_WriteUtf8NoBomLf $srcPath (NL_ToCanonJson $tmpl)
}

# Compute sha256sums.txt for ALL files under models/<id>/** excluding sha256sums.txt itself
$allFiles = @(@(Get-ChildItem -LiteralPath $modelDir -File -Recurse | ForEach-Object { $_.FullName }))
$lines = New-Object System.Collections.Generic.List[string]
foreach($abs in $allFiles){
  $rel = $abs.Substring($modelDir.Length).TrimStart("\") -replace "\\","/"
  if ($rel -ieq "sha256sums.txt") { continue }
  $h = PIE_Sha256HexFile2 $abs
  [void]$lines.Add(($h + "  " + $rel))
}
$outPath = Join-Path $modelDir "sha256sums.txt"
NL_WriteUtf8NoBomLf $outPath ((@(@($lines.ToArray()) | Sort-Object) -join "`n"))

# Receipt (NeverLost)
$sumsSha = "sha256:" + (PIE_Sha256HexBytes ([System.Text.Encoding]::UTF8.GetBytes(((NL_ReadUtf8 $outPath).Replace("`r`n","`n").Replace("`r","`n")))))
NL_AppendReceipt $RepoRoot "pie_model_seal" ("sealed model " + $ModelId) @{ model_id=$ModelId; sums_sha256=$sumsSha; file_count=$lines.Count }
Write-Host ("OK: model sealed: " + $ModelId + " sums_sha256=" + $sumsSha) -ForegroundColor Green
