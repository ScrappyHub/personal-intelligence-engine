param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$ModelId
)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }
function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $t = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if (-not $t.EndsWith("`n")) { $t += "`n" }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}

$RepoRoot = $RepoRoot.TrimEnd("\")
if (-not (Test-Path -LiteralPath $RepoRoot -PathType Container)) { Die ("MISSING_REPOROOT: " + $RepoRoot) }
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$modelDir  = Join-Path $RepoRoot ("models\" + $ModelId)
$weightsDir = Join-Path $modelDir "weights"
$target = Join-Path $weightsDir "weights.gguf"

if (-not (Test-Path -LiteralPath $weightsDir -PathType Container)) {
  New-Item -ItemType Directory -Force -Path $weightsDir | Out-Null
}

# Candidate sources (most likely first)
$candidates = @(
  (Join-Path $modelDir "weights.gguf"),                        # old single-file under correct modelId dir
  (Join-Path $modelDir "weights\weights.gguf"),                # already-correct target
  (Join-Path $RepoRoot "models\mistral-7b\weights.gguf"),       # your earlier dummy path (note: no -gguf)
  (Join-Path $RepoRoot "models\mistral-7b\weights\weights.gguf")
)

$src = $null
foreach($c in $candidates){
  if (Test-Path -LiteralPath $c -PathType Leaf) { $src = $c; break }
}

if ($src) {
  if ($src -ieq $target) {
    Write-Host ("OK: weights already in Option B location: " + $target) -ForegroundColor Green
  } else {
    # Copy then remove if it was the old single-file inside the ModelId dir; otherwise leave source in place (non-destructive)
    Copy-Item -LiteralPath $src -Destination $target -Force
    Write-Host ("COPIED_WEIGHTS: " + $src + " -> " + $target) -ForegroundColor Yellow

    if ($src -ieq (Join-Path $modelDir "weights.gguf")) {
      Remove-Item -LiteralPath $src -Force
      Write-Host ("REMOVED_OLD_SINGLEFILE: " + $src) -ForegroundColor Yellow
    }
  }
} else {
  # No candidates exist: create deterministic dummy weights at correct target
  $dummy = "DUMMY_WEIGHTS_PIE_V1`n"
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($target, $dummy, $enc)
  Write-Host ("WROTE_DUMMY_WEIGHTS: " + $target + " bytes=" + ([System.IO.FileInfo]$target).Length) -ForegroundColor Yellow
}

# Ensure model dir exists (it might not have been created if you only had models\mistral-7b\...)
if (-not (Test-Path -LiteralPath $modelDir -PathType Container)) {
  New-Item -ItemType Directory -Force -Path $modelDir | Out-Null
  if (-not (Test-Path -LiteralPath $weightsDir -PathType Container)) { New-Item -ItemType Directory -Force -Path $weightsDir | Out-Null }
}

Write-Host ("FIXUP_OK: modelDir=" + $modelDir) -ForegroundColor Green
Write-Host ("FIXUP_OK: target=" + $target) -ForegroundColor Green
