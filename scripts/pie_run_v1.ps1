param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$ModelId,
  [Parameter(Mandatory=$true)][string]$Prompt,
  [ValidateSet('0.25','0.5','0.75','1.0')][string]$SpeedFactor='1.0',
  [ValidateSet('stub','ollama','llamacpp','onnx')][string]$Backend='stub'
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

. (Join-Path $RepoRoot 'scripts\_lib_pie_v1.ps1')

$RepoRoot = $RepoRoot.TrimEnd('\')

# Require sealed model manifest
$mp = PIE_ModelManifestPath $RepoRoot $ModelId
if (-not (Test-Path -LiteralPath $mp -PathType Leaf)) { PIE_Die ('missing_model_manifest: ' + $mp) }

$mj = (NL_ReadUtf8 $mp) | ConvertFrom-Json

$sumsSha    = [string]$mj.sums_sha256
$weightsSha = [string]$mj.weights_sha256

if ([string]::IsNullOrWhiteSpace($sumsSha))    { PIE_Die ('missing_sums_sha256_in_model_manifest: ' + $mp) }
if ([string]::IsNullOrWhiteSpace($weightsSha)) { PIE_Die ('missing_weights_sha256_in_model_manifest: ' + $mp) }

# Params hash (canonical JSON)
$params = @{ speed_factor = $SpeedFactor }
$paramsHash = PIE_Sha256HexBytes ([System.Text.Encoding]::UTF8.GetBytes((NL_ToCanonJson $params)))

# Input hash is over canonical bytes of prompt text (as provided)
$inBytes = [System.Text.Encoding]::UTF8.GetBytes($Prompt)
$inHash  = PIE_Sha256HexBytes $inBytes

# Backend execution.
# Recording law (input/output hashing, ledger, artifacts) is owned here regardless of backend.
# Default 'stub' is deterministic and network-free, preserving the frozen Tier-0 pipeline.
# See engine/README.md and engine/adapters/<name>/PIE_ENGINE_ADAPTER.v1.json.
# Run a backend adapter as a child process, capturing stdout+stderr reliably. The terminating-error
# preference is relaxed so a child that writes to stderr or exits non-zero (expected for negative
# cases) is surfaced via the exit code + captured text, not lost to a NativeCommandError.
function Invoke-BackendChild([string]$AdapterPath,[string[]]$AdapterArgs){
  if(-not (Test-Path -LiteralPath $AdapterPath -PathType Leaf)){ PIE_Die ('PIE_ENGINE_BACKEND_UNAVAILABLE: ' + $AdapterPath) }
  $prev = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $o = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $AdapterPath @AdapterArgs 2>&1 | Out-String
    $code = $LASTEXITCODE
  }
  finally { $ErrorActionPreference = $prev }
  return [pscustomobject]@{ out = $o.TrimEnd("`r","`n"); code = $code }
}

switch ($Backend) {

  'stub' {
    $output = ('PIE_STUB_OUTPUT model=' + $ModelId + ' speed=' + $SpeedFactor + ' prompt_sha256=' + $inHash + ' model_sums=' + $sumsSha)
  }

  'ollama' {
    # Real local generation via the loopback Ollama adapter. Fail-closed: never fall back to stub.
    # The sealed manifest may carry an explicit ollama_model tag (e.g. "qwen2.5-coder:1.5b") so a
    # filesystem-safe sealed model_id can map to a real Ollama tag containing ':'. Falls back to
    # the ModelId when the field is absent.
    $ollamaModel = $ModelId
    if (($mj.PSObject.Properties.Name -contains 'ollama_model') -and -not [string]::IsNullOrWhiteSpace([string]$mj.ollama_model)) {
      $ollamaModel = [string]$mj.ollama_model
    }
    $r = Invoke-BackendChild (Join-Path $RepoRoot 'scripts\pie_backend_ollama_cmd_v1.ps1') @("-Model",$ollamaModel,"-Message",$Prompt)
    if ($r.code -ne 0) { PIE_Die ('PIE_ENGINE_OLLAMA_FAILED: exit ' + $r.code + ' :: ' + $r.out) }
    $output = $r.out
    if ([string]::IsNullOrWhiteSpace($output)) { PIE_Die 'PIE_ENGINE_EMPTY_OUTPUT' }
  }

  'llamacpp' {
    # Real local generation via a loopback llama.cpp server. Fail-closed: never fall back to stub.
    $r = Invoke-BackendChild (Join-Path $RepoRoot 'scripts\pie_backend_llamacpp_cmd_v1.ps1') @("-Model",$ModelId,"-Message",$Prompt)
    if ($r.code -ne 0) { PIE_Die ('PIE_ENGINE_LLAMACPP_FAILED: exit ' + $r.code + ' :: ' + $r.out) }
    $output = $r.out
    if ([string]::IsNullOrWhiteSpace($output)) { PIE_Die 'PIE_ENGINE_EMPTY_OUTPUT' }
  }

  'onnx' {
    # Native offline generation via onnxruntime-genai (subprocess). Fail-closed; needs -RepoRoot
    # so the wrapper can resolve the sealed model directory.
    $r = Invoke-BackendChild (Join-Path $RepoRoot 'scripts\pie_backend_onnx_cmd_v1.ps1') @("-RepoRoot",$RepoRoot,"-Model",$ModelId,"-Message",$Prompt)
    if ($r.code -ne 0) { PIE_Die ('PIE_ENGINE_ONNX_GENERATION_FAILED: exit ' + $r.code + ' :: ' + $r.out) }
    $output = $r.out
    if ([string]::IsNullOrWhiteSpace($output)) { PIE_Die 'PIE_ENGINE_EMPTY_OUTPUT' }
  }

  default { PIE_Die ('PIE_ENGINE_UNKNOWN_BACKEND: ' + $Backend) }
}

$outHash = PIE_Sha256HexBytes ([System.Text.Encoding]::UTF8.GetBytes($output))
$runId   = ([guid]::NewGuid().ToString('n'))

# Instrument-grade: bind run to sealed model set (sums_sha256) + expose weights_sha256 too
$rec = @{
  schema       = 'run_record.v1'
  run_id       = $runId
  model_id     = $ModelId

  # Strong binding (sealed set)
  sums_sha256  = $sumsSha

  # Extra signal (weights-only)
  weights_sha256 = $weightsSha

  # Back-compat slot: treat model_sha256 as sums_sha256 (stronger than weights-only)
  model_sha256 = $sumsSha

  input_hash   = ('sha256:' + $inHash)
  output_hash  = ('sha256:' + $outHash)
  params_hash  = ('sha256:' + $paramsHash)
  time_utc     = (Get-Date).ToUniversalTime().ToString('o')
}

# Crash-atomic multi-file state change (B3 adoption): the input artifact, output artifact, and run
# ledger apply all-or-nothing via a write-ahead transaction. Artifacts are staged before the ledger
# so a pre-recovery partial state never shows a ledger entry without its artifacts; a transaction
# interrupted mid-commit is completed by `pie recover`.
. (Join-Path $RepoRoot 'scripts\_lib_pie_txn_v1.ps1')

$inPath  = Join-Path $RepoRoot ('runs\run_' + $runId + '_input.txt')
$outPath = Join-Path $RepoRoot ('runs\run_' + $runId + '_output.txt')

$ledger    = PIE_ComputeRunLedgerLine $RepoRoot $rec
$newLedger = $ledger.existing + $ledger.line + "`n"

$txn = PIE_TxnBegin $RepoRoot
PIE_TxnStage $txn $inPath      $Prompt
PIE_TxnStage $txn $outPath     $output
PIE_TxnStage $txn $ledger.path $newLedger
PIE_TxnCommit $txn

# Evidence receipt (matches prior PIE_AppendRunLedger behavior).
NL_AppendReceipt $RepoRoot "pie_run_ledger" "appended run ledger entry" @{ run_id=$rec.run_id; line_sha256=(PIE_Sha256HexBytes([System.Text.Encoding]::UTF8.GetBytes($ledger.line))) }

Write-Host ('OK: run recorded: ' + $runId) -ForegroundColor Green
Write-Output $output
