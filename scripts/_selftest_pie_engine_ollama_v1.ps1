param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  # A model id that is BOTH sealed under registry\models\<ModelId>\model_manifest.v1.json
  # AND pulled into the local Ollama host. Required for the positive (real-generation) check.
  [Parameter(Mandatory=$false)][string]$ModelId = "",
  [switch]$SkipPositive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Certification test trio for the Ollama engine adapter (engine/adapters/ollama).
# Emits SELFTEST_PIE_ENGINE_OLLAMA_V1_GREEN only when the negative + binding checks pass
# AND a real generation was sealed (positive check). Until this runs green on the target host,
# the adapter status stays "preview" per engine/README.md.

function Die([string]$Message){ throw ("SELFTEST_ENGINE_OLLAMA_FAIL: " + $Message) }

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$runScript = Join-Path $RepoRoot "scripts\pie_run_v1.ps1"
if(-not (Test-Path -LiteralPath $runScript -PathType Leaf)){ Die ("MISSING_RUN_SCRIPT: " + $runScript) }

$ledgerPath = Join-Path $RepoRoot "runs\run_ledger.ndjson"
function Get-LedgerCount {
  if(-not (Test-Path -LiteralPath $ledgerPath -PathType Leaf)){ return 0 }
  $enc = New-Object System.Text.UTF8Encoding($false)
  return @(@([System.IO.File]::ReadAllLines($ledgerPath,$enc)) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count
}

# Relax the terminating-error preference: child pie_run_v1 calls below intentionally exit non-zero
# and write to stderr; we drive on exit code + captured text, not on NativeCommandError.
$ErrorActionPreference = "Continue"

Write-Host "PIE_ENGINE_OLLAMA_SELFTEST_START" -ForegroundColor DarkCyan

# --- Check 1 (negative): host down must fail closed, never fall back to stub, never ledger. ---
$before = Get-LedgerCount
$failed = $false
$captured = ""
try {
  $env:PIE_OLLAMA_URL = "http://127.0.0.1:59999/api/generate"  # unused dead port
  $captured = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runScript `
    -RepoRoot $RepoRoot -ModelId ($(if($ModelId){$ModelId}else{"selftest-missing"})) -Prompt "negative host-down" -Backend ollama 2>&1 | Out-String)
  if($LASTEXITCODE -ne 0){ $failed = $true }
}
catch { $failed = $true; $captured = $_.Exception.Message }
finally { Remove-Item Env:\PIE_OLLAMA_URL -ErrorAction SilentlyContinue }

if(-not $failed){ Die "HOST_DOWN_DID_NOT_FAIL_CLOSED" }
if($captured -match 'PIE_STUB_OUTPUT'){ Die "HOST_DOWN_FELL_BACK_TO_STUB" }
$after = Get-LedgerCount
if($after -ne $before){ Die "HOST_DOWN_APPENDED_LEDGER" }
Write-Host "  check1_negative_host_down: OK" -ForegroundColor Green

# --- Check 2 (binding): missing sealed model manifest must fail on the real backend too. ---
$bindingFailed = $false
$bindingOut = ""
try {
  $bindingOut = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runScript `
    -RepoRoot $RepoRoot -ModelId "selftest-unsealed-model-xyz" -Prompt "binding" -Backend ollama 2>&1 | Out-String)
  if($LASTEXITCODE -ne 0){ $bindingFailed = $true }
}
catch { $bindingFailed = $true; $bindingOut = $_.Exception.Message }
if(-not $bindingFailed){ Die "UNSEALED_MODEL_WAS_ACCEPTED" }
if($bindingOut -notmatch 'missing_model_manifest'){ Die "BINDING_WRONG_ERROR" }
Write-Host "  check2_sealed_model_binding: OK" -ForegroundColor Green

# --- Check 3 (positive): a real, non-stub generation is produced, ledgered, and artifacted. ---
if($SkipPositive){
  Write-Host "PIE_ENGINE_OLLAMA_SELFTEST_INCONCLUSIVE (positive skipped; NOT green)" -ForegroundColor Yellow
  return
}
if([string]::IsNullOrWhiteSpace($ModelId)){
  Write-Host "PIE_ENGINE_OLLAMA_SELFTEST_INCONCLUSIVE (no -ModelId; positive not run; NOT green)" -ForegroundColor Yellow
  return
}

$posBefore = Get-LedgerCount
$out = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runScript `
  -RepoRoot $RepoRoot -ModelId $ModelId -Prompt "In one word, say: ready" -Backend ollama 2>&1 | Out-String)
if($LASTEXITCODE -ne 0){ Die ("POSITIVE_RUN_FAILED: " + $out) }
if([string]::IsNullOrWhiteSpace($out)){ Die "POSITIVE_EMPTY_OUTPUT" }
if($out -match 'PIE_STUB_OUTPUT'){ Die "POSITIVE_RETURNED_STUB" }
$posAfter = Get-LedgerCount
if($posAfter -le $posBefore){ Die "POSITIVE_DID_NOT_LEDGER" }

Write-Host "SELFTEST_PIE_ENGINE_OLLAMA_V1_GREEN" -ForegroundColor Green
