param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$ModelId,
  [Parameter(Mandatory=$true)][string]$Backend,
  [Parameter(Mandatory=$true)][string]$License,
  [string]$Notes=""
)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
. (Join-Path $RepoRoot "scripts\_lib_neverlost_v1.ps1")
. (Join-Path $RepoRoot "scripts\_lib_pie_v1.ps1")
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

function RDie([string]$m){ throw $m }
function ReadAllBytes([string]$Path){ if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ RDie ("missing_file: " + $Path) }; return [System.IO.File]::ReadAllBytes($Path) }
function Sha256HexFile([string]$Path){ PIE_Sha256HexBytes (ReadAllBytes $Path) }

# Validate layout (Option B)
$modelDir = Join-Path $RepoRoot ("models\" + $ModelId)
if (-not (Test-Path -LiteralPath $modelDir -PathType Container)) { PIE_Die ("missing_model_dir: " + $modelDir) }
$weightsDir = Join-Path $modelDir "weights"
if (-not (Test-Path -LiteralPath $weightsDir -PathType Container)) { PIE_Die ("missing_weights_dir: " + $weightsDir) }
$weightFiles = @(@(Get-ChildItem -LiteralPath $weightsDir -File -Recurse | ForEach-Object { $_.FullName }))
if ($weightFiles.Count -lt 1) { PIE_Die ("no_weight_files_found: " + $weightsDir) }

# Require seal outputs
$sumsPath = Join-Path $modelDir "sha256sums.txt"
if (-not (Test-Path -LiteralPath $sumsPath -PathType Leaf)) { PIE_Die ("missing_sha256sums: " + $sumsPath + " (run pie_model_seal_v1.ps1 first)") }

# Validate sha256sums matches real files (non-mutation verification)
$enc = New-Object System.Text.UTF8Encoding($false)
$lines = @(@([System.IO.File]::ReadAllLines($sumsPath,$enc)))
if ($lines.Count -lt 1) { PIE_Die ("sha256sums_empty: " + $sumsPath) }
foreach($line in $lines){
  if ([string]::IsNullOrWhiteSpace($line)) { continue }
  $m = [regex]::Match($line, "^(?<h>[0-9a-f]{64})\s\s(?<p>.+)$")
  if (-not $m.Success) { PIE_Die ("bad_sha256sums_line: " + $line) }
  $h = $m.Groups["h"].Value
  $rel = $m.Groups["p"].Value
  if ($rel -ieq "sha256sums.txt") { PIE_Die "sha256sums.txt must not include itself" }
  $abs = Join-Path $modelDir ($rel -replace "/","\")
  if (-not (Test-Path -LiteralPath $abs -PathType Leaf)) { PIE_Die ("missing_sealed_file: " + $rel) }
  $hh = Sha256HexFile $abs
  if ($hh -ne $h) { PIE_Die ("sha256_mismatch: " + $rel + " expected=" + $h + " got=" + $hh) }
}

# Derive aggregate from canonical bytes of sha256sums.txt (LF normalized)
$sumsTxt = (NL_ReadUtf8 $sumsPath).Replace("`r`n","`n").Replace("`r","`n")
if (-not $sumsTxt.EndsWith("`n")) { $sumsTxt += "`n" }
$aggHex = PIE_Sha256HexBytes ([System.Text.Encoding]::UTF8.GetBytes($sumsTxt))
$weightsSha = "sha256:" + $aggHex
$sumsSha = "sha256:" + (PIE_Sha256HexBytes ([System.Text.Encoding]::UTF8.GetBytes($sumsTxt)))

# Write registry model manifest
$mp = PIE_ModelManifestPath $RepoRoot $ModelId
$mobj = @{ schema="model_manifest.v1"; model_id=$ModelId; backend=$Backend; license=$License; notes=$Notes; weights_sha256=$weightsSha; sums_sha256=$sumsSha; sealed_at_utc=(Get-Date).ToUniversalTime().ToString("o"); layout="B"; weights_rel="models/" + $ModelId + "/weights/" }
NL_WriteUtf8NoBomLf $mp (NL_ToCanonJson $mobj)
NL_AppendReceipt $RepoRoot "pie_model_register" ("registered model " + $ModelId) @{ model_id=$ModelId; weights_sha256=$weightsSha; sums_sha256=$sumsSha }
Write-Host ("OK: model registered: " + $ModelId + " weights_sha256=" + $weightsSha) -ForegroundColor Green
