param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }

$RepoRoot = $RepoRoot.TrimEnd("\")
if (-not (Test-Path -LiteralPath $RepoRoot -PathType Container)) { Die ("missing_repo_root: " + $RepoRoot) }

$PSExe = (Get-Command powershell.exe -ErrorAction Stop).Source

# --- Ensure dummy weights exist for smoke-test
$wDir  = Join-Path $RepoRoot "models\mistral-7b"
$wPath = Join-Path $wDir "weights.gguf"
if (-not (Test-Path -LiteralPath $wDir -PathType Container)) { New-Item -ItemType Directory -Force -Path $wDir | Out-Null }

if (-not (Test-Path -LiteralPath $wPath -PathType Leaf)) {
  # Deterministic dummy bytes (NOT a real GGUF)
  $bytes = [System.Text.Encoding]::UTF8.GetBytes("PIE_DUMMY_GGUF_V1`n")
  [System.IO.File]::WriteAllBytes($wPath, $bytes)
  Write-Host ("WROTE_DUMMY_WEIGHTS: " + $wPath + " bytes=" + $bytes.Length) -ForegroundColor Yellow
} else {
  Write-Host ("WEIGHTS_EXISTS: " + $wPath) -ForegroundColor DarkGray
}

# --- Register model (writes manifest + receipt)
& $PSExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $RepoRoot "scripts\pie_register_model_v1.ps1") `
  -RepoRoot $RepoRoot -ModelId "mistral-7b-gguf" -Backend "llama.cpp" -Weights @("models\mistral-7b\weights.gguf") -License "apache-2.0"

# --- Run PIE (stub output ok; records run ledger + output file + receipt)
$out = & $PSExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $RepoRoot "scripts\pie_run_v1.ps1") `
  -RepoRoot $RepoRoot -ModelId "mistral-7b-gguf" -Prompt "hello PIE" -SpeedFactor "1.0"

Write-Host "---- LAST OUTPUT ----" -ForegroundColor Cyan
Write-Output $out

# --- Show ledger + receipts
$runLedger = Join-Path $RepoRoot "runs\run_ledger.ndjson"
$rcpt      = Join-Path $RepoRoot "proofs\receipts\neverlost.ndjson"

Write-Host "---- RUN LEDGER (tail 5) ----" -ForegroundColor Cyan
if (Test-Path -LiteralPath $runLedger -PathType Leaf) {
  Get-Content -LiteralPath $runLedger -Tail 5
} else {
  Write-Host ("MISSING_RUN_LEDGER: " + $runLedger) -ForegroundColor Red
}

Write-Host "---- RECEIPTS (tail 10) ----" -ForegroundColor Cyan
if (Test-Path -LiteralPath $rcpt -PathType Leaf) {
  Get-Content -LiteralPath $rcpt -Tail 10
} else {
  Write-Host ("MISSING_RECEIPTS: " + $rcpt) -ForegroundColor Red
}

Write-Host "PIE_SMOKETEST_OK" -ForegroundColor Green
