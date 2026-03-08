param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }

function Read-Utf8NoBom([string]$Path){
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Die ("MISSING_FILE: " + $Path) }
  $enc = New-Object System.Text.UTF8Encoding($false)
  return [System.IO.File]::ReadAllText($Path,$enc)
}
function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $t = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if (-not $t.EndsWith("`n")) { $t += "`n" }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}
function Parse-GateText([string]$Text){ [void][ScriptBlock]::Create($Text) }

$RepoRoot = $RepoRoot.TrimEnd("\")
if (-not (Test-Path -LiteralPath $RepoRoot -PathType Container)) { Die ("MISSING_REPOROOT: " + $RepoRoot) }
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

# ---------------------------
# 1) FIX: packet_verify_v1.ps1 ($pid collides with read-only $PID)
# ---------------------------
$VerifyPath = Join-Path $RepoRoot "scripts\packet_verify_v1.ps1"
if (Test-Path -LiteralPath $VerifyPath -PathType Leaf) {
  $vt = Read-Utf8NoBom $VerifyPath

  # rename $pid (and friends) safely
  $vt2 = $vt
  $vt2 = $vt2 -replace '(?m)\$pidPath\b', '$packetIdPath'
  $vt2 = $vt2 -replace '(?m)\$pid\b', '$packetIdTxt'
  $vt2 = $vt2 -replace '(?m)\$derived\b', '$derivedPacketId'
  # but keep message labels stable
  Parse-GateText $vt2
  Write-Utf8NoBomLf $VerifyPath $vt2
  Parse-GateText (Read-Utf8NoBom $VerifyPath)
  Write-Host "PATCH_OK: packet_verify_v1.ps1 PID collision fixed" -ForegroundColor Green
} else {
  Write-Host "SKIP: packet_verify_v1.ps1 not found" -ForegroundColor DarkYellow
}

# ---------------------------
# 2) WRITE: scripts\pie_model_seal_v1.ps1
# ---------------------------
$SealPath = Join-Path $RepoRoot "scripts\pie_model_seal_v1.ps1"
$seal = New-Object System.Collections.Generic.List[string]
[void]$seal.Add('param([Parameter(Mandatory=$true)][string]$RepoRoot,[Parameter(Mandatory=$true)][string]$ModelId)')
[void]$seal.Add('$ErrorActionPreference="Stop"')
[void]$seal.Add('Set-StrictMode -Version Latest')
[void]$seal.Add('. (Join-Path $RepoRoot "scripts\_lib_neverlost_v1.ps1")')
[void]$seal.Add('. (Join-Path $RepoRoot "scripts\_lib_pie_v1.ps1")')
[void]$seal.Add('$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path')
[void]$seal.Add('')
[void]$seal.Add('function PIE_Die2([string]$m){ throw $m }')
[void]$seal.Add('function PIE_ReadAllBytes([string]$Path){ if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ PIE_Die2 ("missing_file: " + $Path) }; return [System.IO.File]::ReadAllBytes($Path) }')
[void]$seal.Add('function PIE_Sha256HexFile2([string]$Path){ PIE_Sha256HexBytes (PIE_ReadAllBytes $Path) }')
[void]$seal.Add('')
[void]$seal.Add('$modelDir = Join-Path $RepoRoot ("models\" + $ModelId)')
[void]$seal.Add('if (-not (Test-Path -LiteralPath $modelDir -PathType Container)) { PIE_Die ("missing_model_dir: " + $modelDir) }')
[void]$seal.Add('$weightsDir = Join-Path $modelDir "weights"')
[void]$seal.Add('if (-not (Test-Path -LiteralPath $weightsDir -PathType Container)) { PIE_Die ("missing_weights_dir: " + $weightsDir + " (Option B required)") }')
[void]$seal.Add('$weightFiles = @(@(Get-ChildItem -LiteralPath $weightsDir -File -Recurse | ForEach-Object { $_.FullName }))')
[void]$seal.Add('if ($weightFiles.Count -lt 1) { PIE_Die ("no_weight_files_found: " + $weightsDir) }')
[void]$seal.Add('')
[void]$seal.Add('# Ensure source.json exists (template if missing)')
[void]$seal.Add('$srcPath = Join-Path $modelDir "source.json"')
[void]$seal.Add('if (-not (Test-Path -LiteralPath $srcPath -PathType Leaf)) {')
[void]$seal.Add('  $tmpl = @{ schema="pie.model.source.v1"; model_id=$ModelId; origin=""; notes=""; created_utc=(Get-Date).ToUniversalTime().ToString("o") }')
[void]$seal.Add('  NL_WriteUtf8NoBomLf $srcPath (NL_ToCanonJson $tmpl)')
[void]$seal.Add('}')
[void]$seal.Add('')
[void]$seal.Add('# Compute sha256sums.txt for ALL files under models/<id>/** excluding sha256sums.txt itself')
[void]$seal.Add('$allFiles = @(@(Get-ChildItem -LiteralPath $modelDir -File -Recurse | ForEach-Object { $_.FullName }))')
[void]$seal.Add('$lines = New-Object System.Collections.Generic.List[string]')
[void]$seal.Add('foreach($abs in $allFiles){')
[void]$seal.Add('  $rel = $abs.Substring($modelDir.Length).TrimStart("\") -replace "\\","/"')
[void]$seal.Add('  if ($rel -ieq "sha256sums.txt") { continue }')
[void]$seal.Add('  $h = PIE_Sha256HexFile2 $abs')
[void]$seal.Add('  [void]$lines.Add(($h + "  " + $rel))')
[void]$seal.Add('}')
[void]$seal.Add('$outPath = Join-Path $modelDir "sha256sums.txt"')
[void]$seal.Add('NL_WriteUtf8NoBomLf $outPath ((@(@($lines.ToArray()) | Sort-Object) -join "`n"))')
[void]$seal.Add('')
[void]$seal.Add('# Receipt (NeverLost)')
[void]$seal.Add('$sumsSha = "sha256:" + (PIE_Sha256HexBytes ([System.Text.Encoding]::UTF8.GetBytes(((NL_ReadUtf8 $outPath).Replace("`r`n","`n").Replace("`r","`n")))))')
[void]$seal.Add('NL_AppendReceipt $RepoRoot "pie_model_seal" ("sealed model " + $ModelId) @{ model_id=$ModelId; sums_sha256=$sumsSha; file_count=$lines.Count }')
[void]$seal.Add('Write-Host ("OK: model sealed: " + $ModelId + " sums_sha256=" + $sumsSha) -ForegroundColor Green')
Write-Utf8NoBomLf $SealPath (($seal.ToArray()) -join "`n")
Parse-GateText (Read-Utf8NoBom $SealPath)
Write-Host "WROTE+PARSE_OK: pie_model_seal_v1.ps1" -ForegroundColor Green

# ---------------------------
# 3) UPGRADE: scripts\pie_register_model_v1.ps1 (register only after seal)
# ---------------------------
$RegPath = Join-Path $RepoRoot "scripts\pie_register_model_v1.ps1"
if (-not (Test-Path -LiteralPath $RegPath -PathType Leaf)) { Die ("missing_script: " + $RegPath) }

# Replace entire file deterministically (no regex surgery; instrument-grade)
$reg = New-Object System.Collections.Generic.List[string]
[void]$reg.Add('param(')
[void]$reg.Add('  [Parameter(Mandatory=$true)][string]$RepoRoot,')
[void]$reg.Add('  [Parameter(Mandatory=$true)][string]$ModelId,')
[void]$reg.Add('  [Parameter(Mandatory=$true)][string]$Backend,')
[void]$reg.Add('  [Parameter(Mandatory=$true)][string]$License,')
[void]$reg.Add('  [string]$Notes=""')
[void]$reg.Add(')')
[void]$reg.Add('$ErrorActionPreference="Stop"')
[void]$reg.Add('Set-StrictMode -Version Latest')
[void]$reg.Add('. (Join-Path $RepoRoot "scripts\_lib_neverlost_v1.ps1")')
[void]$reg.Add('. (Join-Path $RepoRoot "scripts\_lib_pie_v1.ps1")')
[void]$reg.Add('$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path')
[void]$reg.Add('')
[void]$reg.Add('function RDie([string]$m){ throw $m }')
[void]$reg.Add('function ReadAllBytes([string]$Path){ if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ RDie ("missing_file: " + $Path) }; return [System.IO.File]::ReadAllBytes($Path) }')
[void]$reg.Add('function Sha256HexFile([string]$Path){ PIE_Sha256HexBytes (ReadAllBytes $Path) }')
[void]$reg.Add('')
[void]$reg.Add('# Validate layout (Option B)')
[void]$reg.Add('$modelDir = Join-Path $RepoRoot ("models\" + $ModelId)')
[void]$reg.Add('if (-not (Test-Path -LiteralPath $modelDir -PathType Container)) { PIE_Die ("missing_model_dir: " + $modelDir) }')
[void]$reg.Add('$weightsDir = Join-Path $modelDir "weights"')
[void]$reg.Add('if (-not (Test-Path -LiteralPath $weightsDir -PathType Container)) { PIE_Die ("missing_weights_dir: " + $weightsDir) }')
[void]$reg.Add('$weightFiles = @(@(Get-ChildItem -LiteralPath $weightsDir -File -Recurse | ForEach-Object { $_.FullName }))')
[void]$reg.Add('if ($weightFiles.Count -lt 1) { PIE_Die ("no_weight_files_found: " + $weightsDir) }')
[void]$reg.Add('')
[void]$reg.Add('# Require seal outputs')
[void]$reg.Add('$sumsPath = Join-Path $modelDir "sha256sums.txt"')
[void]$reg.Add('if (-not (Test-Path -LiteralPath $sumsPath -PathType Leaf)) { PIE_Die ("missing_sha256sums: " + $sumsPath + " (run pie_model_seal_v1.ps1 first)") }')
[void]$reg.Add('')
[void]$reg.Add('# Validate sha256sums matches real files (non-mutation verification)')
[void]$reg.Add('$enc = New-Object System.Text.UTF8Encoding($false)')
[void]$reg.Add('$lines = @(@([System.IO.File]::ReadAllLines($sumsPath,$enc)))')
[void]$reg.Add('if ($lines.Count -lt 1) { PIE_Die ("sha256sums_empty: " + $sumsPath) }')
[void]$reg.Add('foreach($line in $lines){')
[void]$reg.Add('  if ([string]::IsNullOrWhiteSpace($line)) { continue }')
[void]$reg.Add('  $m = [regex]::Match($line, "^(?<h>[0-9a-f]{64})\s\s(?<p>.+)$")')
[void]$reg.Add('  if (-not $m.Success) { PIE_Die ("bad_sha256sums_line: " + $line) }')
[void]$reg.Add('  $h = $m.Groups["h"].Value')
[void]$reg.Add('  $rel = $m.Groups["p"].Value')
[void]$reg.Add('  if ($rel -ieq "sha256sums.txt") { PIE_Die "sha256sums.txt must not include itself" }')
[void]$reg.Add('  $abs = Join-Path $modelDir ($rel -replace "/","\")')
[void]$reg.Add('  if (-not (Test-Path -LiteralPath $abs -PathType Leaf)) { PIE_Die ("missing_sealed_file: " + $rel) }')
[void]$reg.Add('  $hh = Sha256HexFile $abs')
[void]$reg.Add('  if ($hh -ne $h) { PIE_Die ("sha256_mismatch: " + $rel + " expected=" + $h + " got=" + $hh) }')
[void]$reg.Add('}')
[void]$reg.Add('')
[void]$reg.Add('# Derive aggregate from canonical bytes of sha256sums.txt (LF normalized)')
[void]$reg.Add('$sumsTxt = (NL_ReadUtf8 $sumsPath).Replace("`r`n","`n").Replace("`r","`n")')
[void]$reg.Add('if (-not $sumsTxt.EndsWith("`n")) { $sumsTxt += "`n" }')
[void]$reg.Add('$aggHex = PIE_Sha256HexBytes ([System.Text.Encoding]::UTF8.GetBytes($sumsTxt))')
[void]$reg.Add('$weightsSha = "sha256:" + $aggHex')
[void]$reg.Add('$sumsSha = "sha256:" + (PIE_Sha256HexBytes ([System.Text.Encoding]::UTF8.GetBytes($sumsTxt)))')
[void]$reg.Add('')
[void]$reg.Add('# Write registry model manifest')
[void]$reg.Add('$mp = PIE_ModelManifestPath $RepoRoot $ModelId')
[void]$reg.Add('$mobj = @{ schema="model_manifest.v1"; model_id=$ModelId; backend=$Backend; license=$License; notes=$Notes; weights_sha256=$weightsSha; sums_sha256=$sumsSha; sealed_at_utc=(Get-Date).ToUniversalTime().ToString("o"); layout="B"; weights_rel="models/" + $ModelId + "/weights/" }')
[void]$reg.Add('NL_WriteUtf8NoBomLf $mp (NL_ToCanonJson $mobj)')
[void]$reg.Add('NL_AppendReceipt $RepoRoot "pie_model_register" ("registered model " + $ModelId) @{ model_id=$ModelId; weights_sha256=$weightsSha; sums_sha256=$sumsSha }')
[void]$reg.Add('Write-Host ("OK: model registered: " + $ModelId + " weights_sha256=" + $weightsSha) -ForegroundColor Green')
Write-Utf8NoBomLf $RegPath (($reg.ToArray()) -join "`n")
Parse-GateText (Read-Utf8NoBom $RegPath)
Write-Host "PATCH_OK: pie_register_model_v1.ps1 upgraded (register-after-seal)" -ForegroundColor Green

Write-Host "PATCH_ALL_DONE" -ForegroundColor Green
