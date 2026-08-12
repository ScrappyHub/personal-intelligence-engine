param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  # Sealed model id. Defaults to the bundled fixture registry\models\pie-onnx-fixture.
  [Parameter(Mandatory=$false)][string]$ModelId = "pie-onnx-fixture",
  # Optional real onnxruntime-genai export dir for the positive check (overrides the fixture dir).
  [Parameter(Mandatory=$false)][string]$ModelDir = "",
  [switch]$SkipPositive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Certification test trio for the onnx engine adapter (engine/adapters/onnx).
# Emits SELFTEST_PIE_ENGINE_ONNX_V1_GREEN only when the negative + binding checks pass AND a real
# generation was sealed. Positive requires a real ONNX export (genai_config.json) + onnxruntime-genai;
# otherwise the positive check reports INCONCLUSIVE (not green).

function Die([string]$Message){ throw ("SELFTEST_ENGINE_ONNX_FAIL: " + $Message) }

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$runScript = Join-Path $RepoRoot "scripts\pie_run_v1.ps1"
if(-not (Test-Path -LiteralPath $runScript -PathType Leaf)){ Die ("MISSING_RUN_SCRIPT: " + $runScript) }

$fixtureManifest = Join-Path $RepoRoot ("registry\models\" + $ModelId + "\model_manifest.v1.json")
if(-not (Test-Path -LiteralPath $fixtureManifest -PathType Leaf)){ Die ("MISSING_SEALED_FIXTURE: " + $fixtureManifest) }

$ledgerPath = Join-Path $RepoRoot "runs\run_ledger.ndjson"
function Get-LedgerCount {
  if(-not (Test-Path -LiteralPath $ledgerPath -PathType Leaf)){ return 0 }
  $enc = New-Object System.Text.UTF8Encoding($false)
  return @(@([System.IO.File]::ReadAllLines($ledgerPath,$enc)) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count
}

# Relax the terminating-error preference: child pie_run_v1 calls below intentionally exit non-zero
# and write to stderr; we drive on exit code + captured text, not on NativeCommandError.
$ErrorActionPreference = "Continue"

Write-Host "PIE_ENGINE_ONNX_SELFTEST_START" -ForegroundColor DarkCyan

# --- Check 1 (negative): sealed model but unresolvable model dir must fail closed, no stub, no ledger. ---
$before = Get-LedgerCount
$failed = $false
$captured = ""
try {
  $env:PIE_ONNX_MODEL_DIR = Join-Path $RepoRoot ("runs\onnx_nonexistent_" + ([guid]::NewGuid().ToString('n')))
  $captured = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runScript `
    -RepoRoot $RepoRoot -ModelId $ModelId -Prompt "negative dir-unresolved" -Backend onnx 2>&1 | Out-String)
  if($LASTEXITCODE -ne 0){ $failed = $true }
}
catch { $failed = $true; $captured = $_.Exception.Message }
finally { Remove-Item Env:\PIE_ONNX_MODEL_DIR -ErrorAction SilentlyContinue }

if(-not $failed){ Die "UNRESOLVED_DIR_DID_NOT_FAIL_CLOSED" }
if($captured -match 'PIE_STUB_OUTPUT'){ Die "UNRESOLVED_DIR_FELL_BACK_TO_STUB" }
$after = Get-LedgerCount
if($after -ne $before){ Die "UNRESOLVED_DIR_APPENDED_LEDGER" }
# Specific-token match is informational only: PowerShell renders a thrown error as a wrapped/
# truncated error record, so the nested token can be cut off depending on console width. The robust
# invariants above (failed + no stub + no ledger growth) are what prove fail-closed behavior.
if($captured -notmatch 'PIE_ENGINE_ONNX_MODEL_DIR_UNRESOLVED'){ Write-Host "    (note: dir-unresolved token not visible in rendered output; invariants still hold)" -ForegroundColor DarkYellow }
Write-Host "  check1_negative_dir_unresolved: OK" -ForegroundColor Green

# --- Check 2 (binding): missing sealed model manifest must fail before the backend runs. ---
$bindingFailed = $false
$bindingOut = ""
try {
  $bindingOut = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runScript `
    -RepoRoot $RepoRoot -ModelId "selftest-unsealed-model-xyz" -Prompt "binding" -Backend onnx 2>&1 | Out-String)
  if($LASTEXITCODE -ne 0){ $bindingFailed = $true }
}
catch { $bindingFailed = $true; $bindingOut = $_.Exception.Message }
if(-not $bindingFailed){ Die "UNSEALED_MODEL_WAS_ACCEPTED" }
if($bindingOut -match 'PIE_STUB_OUTPUT'){ Die "UNSEALED_MODEL_FELL_BACK_TO_STUB" }
# Specific-token match is informational only (see note above re: error-record rendering).
if($bindingOut -notmatch 'missing_model_manifest'){ Write-Host "    (note: binding token not visible in rendered output; rejection still enforced)" -ForegroundColor DarkYellow }
Write-Host "  check2_sealed_model_binding: OK" -ForegroundColor Green

# --- Check 3 (positive): real, non-stub generation from an actual ONNX export. ---
if($SkipPositive){
  Write-Host "PIE_ENGINE_ONNX_SELFTEST_INCONCLUSIVE (positive skipped; NOT green)" -ForegroundColor Yellow
  return
}

# Resolve the dir we will check for a real export.
$resolvedDir = $ModelDir
if([string]::IsNullOrWhiteSpace($resolvedDir)){
  $resolvedDir = Join-Path $RepoRoot ("registry\models\" + $ModelId + "\onnx")
}
$genaiConfig = Join-Path $resolvedDir "genai_config.json"
if(-not (Test-Path -LiteralPath $genaiConfig -PathType Leaf)){
  Write-Host ("PIE_ENGINE_ONNX_SELFTEST_INCONCLUSIVE (no real ONNX export at " + $resolvedDir + "; positive not run; NOT green)") -ForegroundColor Yellow
  return
}

$posBefore = Get-LedgerCount
try {
  if(-not [string]::IsNullOrWhiteSpace($ModelDir)){ $env:PIE_ONNX_MODEL_DIR = $ModelDir }
  $out = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runScript `
    -RepoRoot $RepoRoot -ModelId $ModelId -Prompt "In one word, say: ready" -Backend onnx 2>&1 | Out-String)
  $code = $LASTEXITCODE
}
finally { Remove-Item Env:\PIE_ONNX_MODEL_DIR -ErrorAction SilentlyContinue }

if($code -ne 0){ Die ("POSITIVE_RUN_FAILED: " + $out) }
if([string]::IsNullOrWhiteSpace($out)){ Die "POSITIVE_EMPTY_OUTPUT" }
if($out -match 'PIE_STUB_OUTPUT'){ Die "POSITIVE_RETURNED_STUB" }
$posAfter = Get-LedgerCount
if($posAfter -le $posBefore){ Die "POSITIVE_DID_NOT_LEDGER" }

Write-Host "SELFTEST_PIE_ENGINE_ONNX_V1_GREEN" -ForegroundColor Green
