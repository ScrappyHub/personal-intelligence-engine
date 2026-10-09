param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$ModelId,
  [Parameter(Mandatory=$false)][string]$Prompt = '',
  [Parameter(Mandatory=$false)][switch]$PromptStdin,
  [ValidateSet('0.25','0.5','0.75','1.0')][string]$SpeedFactor='1.0',
  [ValidateSet('stub','ollama','llamacpp','onnx')][string]$Backend='stub'
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

. (Join-Path $RepoRoot 'scripts\_lib_pie_v1.ps1')
. (Join-Path $RepoRoot 'scripts\_lib_pie_persona_v1.ps1')

$RepoRoot = $RepoRoot.TrimEnd('\')
if($PromptStdin){ $Prompt = ([Console]::In.ReadToEnd()).TrimEnd("`r","`n") }
if([string]::IsNullOrWhiteSpace($Prompt)){ PIE_Die 'PIE_RUN_PROMPT_REQUIRED' }

# Require sealed model manifest
$mp = PIE_ModelManifestPath $RepoRoot $ModelId
if (-not (Test-Path -LiteralPath $mp -PathType Leaf)) { PIE_Die ('missing_model_manifest: ' + $mp) }

$mj = (NL_ReadUtf8 $mp) | ConvertFrom-Json
$manifestHash = 'sha256:' + (PIE_Sha256HexFile $mp)

$sumsSha    = [string]$mj.sums_sha256
$weightsSha = [string]$mj.weights_sha256

if ([string]::IsNullOrWhiteSpace($sumsSha))    { PIE_Die ('missing_sums_sha256_in_model_manifest: ' + $mp) }
if ([string]::IsNullOrWhiteSpace($weightsSha)) { PIE_Die ('missing_weights_sha256_in_model_manifest: ' + $mp) }

# Verify model identity from current bytes, not only stored manifest fields.
function Normalize-Sha256([string]$Value){ return (($Value -replace '^sha256:','').ToLowerInvariant()) }
function Verify-FileModelIdentity([string]$ExpectedSha){
  $safeId = $ModelId.Replace(':','_')
  $candidates = @(
    (Join-Path (PIE_RegistryRoot $RepoRoot) $safeId),
    (Join-Path $RepoRoot (Join-Path 'models' $ModelId))
  )
  $modelRoot = $null
  foreach($candidate in $candidates){
    if(Test-Path -LiteralPath (Join-Path $candidate 'sha256sums.txt') -PathType Leaf){ $modelRoot = $candidate; break }
  }
  if($null -eq $modelRoot){ PIE_Die ('PIE_MODEL_SUMS_FILE_MISSING: ' + $ModelId) }
  $sumsPath = Join-Path $modelRoot 'sha256sums.txt'
  $sumsText = (NL_ReadUtf8 $sumsPath).Replace("`r`n","`n").Replace("`r","`n")
  if(-not $sumsText.EndsWith("`n")){ $sumsText += "`n" }
  $actualAggregate = PIE_Sha256HexBytes ([System.Text.Encoding]::UTF8.GetBytes($sumsText))
  if($actualAggregate -ne (Normalize-Sha256 $ExpectedSha)){ PIE_Die ('PIE_MODEL_SUMS_AGGREGATE_MISMATCH: ' + $ModelId) }
  foreach($line in @($sumsText -split "`n")){
    if([string]::IsNullOrWhiteSpace($line)){ continue }
    $match = [regex]::Match($line,'^(?<hash>[0-9a-f]{64})\s{2}(?<path>.+)$')
    if(-not $match.Success){ PIE_Die ('PIE_MODEL_SUMS_LINE_INVALID: ' + $line) }
    $relative = $match.Groups['path'].Value.Replace('/','\')
    if([System.IO.Path]::IsPathRooted($relative) -or $relative -match '(^|\\)\.\.(\\|$)'){ PIE_Die ('PIE_MODEL_SUMS_PATH_INVALID: ' + $relative) }
    $actualPath = Join-Path $modelRoot $relative
    if((PIE_Sha256HexFile $actualPath) -ne $match.Groups['hash'].Value){ PIE_Die ('PIE_MODEL_FILE_HASH_MISMATCH: ' + $relative) }
  }
  return [pscustomobject]@{ source='sha256sums'; identity=('sha256:' + $actualAggregate); root=$modelRoot; verified=$true }
}
function Verify-OllamaModelIdentity([string]$OllamaModel,[string]$ExpectedSha){
  $tagsUrl = $env:PIE_OLLAMA_TAGS_URL
  if([string]::IsNullOrWhiteSpace($tagsUrl)){ $tagsUrl = 'http://127.0.0.1:11434/api/tags' }
  try { $tags = Invoke-RestMethod -Method Get -Uri $tagsUrl -ContentType 'application/json' }
  catch { PIE_Die ('PIE_MODEL_OLLAMA_TAGS_FAILED: ' + $_.Exception.Message) }
  $entry = $null
  foreach($candidate in @($tags.models)){
    $name = [string]$candidate.name
    if($name -ieq $OllamaModel -or $name -ieq ($OllamaModel + ':latest')){ $entry = $candidate; break }
  }
  if($null -eq $entry){ PIE_Die ('PIE_MODEL_OLLAMA_NOT_LOCAL: ' + $OllamaModel) }
  $actual = Normalize-Sha256 ([string]$entry.digest)
  if([string]::IsNullOrWhiteSpace($actual)){ PIE_Die ('PIE_MODEL_OLLAMA_DIGEST_MISSING: ' + $OllamaModel) }
  if($actual -ne (Normalize-Sha256 $ExpectedSha)){ PIE_Die ('PIE_MODEL_OLLAMA_DIGEST_MISMATCH: ' + $OllamaModel) }
  return [pscustomobject]@{ source='ollama_local_digest'; identity=('sha256:' + $actual); root='ollama'; verified=$true }
}

if($Backend -ne 'stub' -and ($mj.PSObject.Properties.Name -contains 'backend') -and ([string]$mj.backend -ine $Backend)){
  PIE_Die ('PIE_MODEL_BACKEND_MISMATCH: manifest=' + [string]$mj.backend + ' requested=' + $Backend)
}

$ollamaModel = $ModelId
if (($mj.PSObject.Properties.Name -contains 'ollama_model') -and -not [string]::IsNullOrWhiteSpace([string]$mj.ollama_model)) { $ollamaModel = [string]$mj.ollama_model }
$modelIdentity = $null
if($Backend -eq 'ollama'){
  $modelIdentity = Verify-OllamaModelIdentity $ollamaModel $sumsSha
} elseif(([string]$mj.layout) -eq 'B') {
  $modelIdentity = Verify-FileModelIdentity $sumsSha
} else {
  $modelIdentity = [pscustomobject]@{ source='manifest_only'; identity=$sumsSha; root=''; verified=$false }
}

# Hash every effective generation setting, not only the historical speed hint.
$params = [ordered]@{ backend=$Backend; speed_factor=$SpeedFactor }
switch($Backend){
  'ollama'   { $params.stream=$false }
  'llamacpp' { $params.n_predict=512; $params.temperature=0; $params.stream=$false }
  'onnx'     { $params.max_new_tokens=512 }
}
$paramsHash = PIE_Sha256HexBytes ([System.Text.Encoding]::UTF8.GetBytes((NL_ToCanonJson $params)))

# Run artifacts use the transaction layer's UTF-8/LF/final-newline discipline. Hash exactly those
# bytes so a verifier can compare the recorded digest directly to the artifact on disk.
function Canonical-ArtifactText([string]$Text){
  $canonical = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $canonical.EndsWith("`n")){ $canonical += "`n" }
  return $canonical
}
$inputArtifact = Canonical-ArtifactText $Prompt
$inBytes = [System.Text.Encoding]::UTF8.GetBytes($inputArtifact)
$inHash  = PIE_Sha256HexBytes $inBytes
$runId   = ([guid]::NewGuid().ToString('n'))

$persona = ''
$backendLabel = ''
switch($Backend){ 'ollama'{$backendLabel='Ollama'} 'llamacpp'{$backendLabel='llama.cpp'} 'onnx'{$backendLabel='ONNX'} }
if($backendLabel){ $persona = PIE_PersonaSystem $backendLabel }
$effectivePrompt = $(if($backendLabel){$persona + "`n`n" + $Prompt.Replace("\n","`n")}else{$Prompt})
$personaHash = PIE_Sha256HexBytes ([System.Text.Encoding]::UTF8.GetBytes($persona))
$effectivePromptHash = PIE_Sha256HexBytes ([System.Text.Encoding]::UTF8.GetBytes($effectivePrompt))

$privatePromptPath = Join-Path $RepoRoot ('runs\private_prompt_' + $runId + '.txt')
if($Backend -ne 'stub'){
  $privateEnc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($privatePromptPath,$effectivePrompt,$privateEnc)
}

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

try { switch ($Backend) {

  'stub' {
    $output = ('PIE_STUB_OUTPUT model=' + $ModelId + ' speed=' + $SpeedFactor + ' prompt_sha256=' + $inHash + ' model_sums=' + $sumsSha)
  }

  'ollama' {
    # Real local generation via the loopback Ollama adapter. Fail-closed: never fall back to stub.
    # The sealed manifest may carry an explicit ollama_model tag (e.g. "qwen2.5-coder:1.5b") so a
    # filesystem-safe sealed model_id can map to a real Ollama tag containing ':'. Falls back to
    # the ModelId when the field is absent.
    $r = Invoke-BackendChild (Join-Path $RepoRoot 'scripts\pie_backend_ollama_cmd_v1.ps1') @("-Model",$ollamaModel,"-PromptPath",$privatePromptPath)
    if ($r.code -ne 0) { PIE_Die ('PIE_ENGINE_OLLAMA_FAILED: exit ' + $r.code + ' :: ' + $r.out) }
    $output = $r.out
    if ([string]::IsNullOrWhiteSpace($output)) { PIE_Die 'PIE_ENGINE_EMPTY_OUTPUT' }
  }

  'llamacpp' {
    # Real local generation via a loopback llama.cpp server. Fail-closed: never fall back to stub.
    $r = Invoke-BackendChild (Join-Path $RepoRoot 'scripts\pie_backend_llamacpp_cmd_v1.ps1') @("-Model",$ModelId,"-PromptPath",$privatePromptPath)
    if ($r.code -ne 0) { PIE_Die ('PIE_ENGINE_LLAMACPP_FAILED: exit ' + $r.code + ' :: ' + $r.out) }
    $output = $r.out
    if ([string]::IsNullOrWhiteSpace($output)) { PIE_Die 'PIE_ENGINE_EMPTY_OUTPUT' }
  }

  'onnx' {
    # Native offline generation via onnxruntime-genai (subprocess). Fail-closed; needs -RepoRoot
    # so the wrapper can resolve the sealed model directory.
    $r = Invoke-BackendChild (Join-Path $RepoRoot 'scripts\pie_backend_onnx_cmd_v1.ps1') @("-RepoRoot",$RepoRoot,"-Model",$ModelId,"-PromptPath",$privatePromptPath)
    if ($r.code -ne 0) { PIE_Die ('PIE_ENGINE_ONNX_GENERATION_FAILED: exit ' + $r.code + ' :: ' + $r.out) }
    $output = $r.out
    if ([string]::IsNullOrWhiteSpace($output)) { PIE_Die 'PIE_ENGINE_EMPTY_OUTPUT' }
  }

  default { PIE_Die ('PIE_ENGINE_UNKNOWN_BACKEND: ' + $Backend) }
} } finally {
  if(Test-Path -LiteralPath $privatePromptPath -PathType Leaf){ Remove-Item -LiteralPath $privatePromptPath -Force -ErrorAction SilentlyContinue }
}

$outputArtifact = Canonical-ArtifactText $output
$outHash = PIE_Sha256HexBytes ([System.Text.Encoding]::UTF8.GetBytes($outputArtifact))
$runTime = (Get-Date).ToUniversalTime().ToString('o')

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
  time_utc     = $runTime
}

# Crash-atomic multi-file state change (B3 adoption): the input artifact, output artifact, and run
# ledger apply all-or-nothing via a write-ahead transaction. Artifacts are staged before the ledger
# so a pre-recovery partial state never shows a ledger entry without its artifacts; a transaction
# interrupted mid-commit is completed by `pie recover`.
. (Join-Path $RepoRoot 'scripts\_lib_pie_txn_v1.ps1')

$inPath  = Join-Path $RepoRoot ('runs\run_' + $runId + '_input.txt')
$outPath = Join-Path $RepoRoot ('runs\run_' + $runId + '_output.txt')
$recordPath = Join-Path $RepoRoot ('runs\run_' + $runId + '_record.json')
$provenancePath = Join-Path $RepoRoot ('runs\run_' + $runId + '_provenance.json')

$ledgerLock = PIE_AcquireRunLedgerLock $RepoRoot
try {
  [void](PIE_TxnRecover $RepoRoot)
  $ledger    = PIE_ComputeRunLedgerLine $RepoRoot $rec
  $newLedger = $ledger.existing + $ledger.line + "`n"
  $recordLineHash = PIE_Sha256HexBytes ([System.Text.Encoding]::UTF8.GetBytes($ledger.line))

  $adapterScript = $(switch($Backend){
    'ollama'{Join-Path $RepoRoot 'scripts\pie_backend_ollama_cmd_v1.ps1'}
    'llamacpp'{Join-Path $RepoRoot 'scripts\pie_backend_llamacpp_cmd_v1.ps1'}
    'onnx'{Join-Path $RepoRoot 'scripts\pie_backend_onnx_cmd_v1.ps1'}
    default{Join-Path $RepoRoot 'scripts\pie_run_v1.ps1'}
  })
  $contractPath = Join-Path $RepoRoot ('engine\adapters\' + $Backend + '\PIE_ENGINE_ADAPTER.v1.json')
  $backendBindingVerified = ($Backend -eq 'ollama' -and $modelIdentity.verified) -or ($Backend -eq 'onnx' -and $modelIdentity.verified)
  $provenance = [ordered]@{
    schema='pie.run.provenance.v1'; run_id=$runId; recorded_utc=$runTime; backend=$Backend
    adapter_script_sha256=('sha256:' + (PIE_Sha256HexFile $adapterScript))
    adapter_contract_sha256=$(if(Test-Path -LiteralPath $contractPath -PathType Leaf){'sha256:' + (PIE_Sha256HexFile $contractPath)}else{$null})
    model_id=$ModelId; model_manifest_sha256=$manifestHash; model_content_sha256=$modelIdentity.identity
    model_identity_source=$modelIdentity.source; model_identity_verified=[bool]$modelIdentity.verified
    backend_binding_verified=[bool]$backendBindingVerified
    inference_certified=[bool]($Backend -ne 'stub' -and $backendBindingVerified)
    persona_sha256=('sha256:' + $personaHash); effective_prompt_sha256=('sha256:' + $effectivePromptHash)
    params=$params; params_sha256=('sha256:' + $paramsHash)
    input_sha256=('sha256:' + $inHash); output_sha256=('sha256:' + $outHash)
    record_line_sha256=('sha256:' + $recordLineHash)
  }

  $txn = PIE_TxnBegin $RepoRoot
  PIE_TxnStage $txn $inPath         $inputArtifact
  PIE_TxnStage $txn $outPath        $outputArtifact
  PIE_TxnStage $txn $recordPath     $ledger.line
  PIE_TxnStage $txn $provenancePath (NL_ToCanonJson $provenance)
  PIE_TxnStage $txn $ledger.path    $newLedger
  PIE_TxnCommit $txn

  NL_AppendReceipt $RepoRoot "pie_run_ledger" "appended run ledger entry" @{ run_id=$rec.run_id; line_sha256=$recordLineHash; provenance_schema='pie.run.provenance.v1'; inference_certified=$provenance.inference_certified }
}
finally { $ledgerLock.Dispose() }

Write-Host ('OK: run recorded: ' + $runId) -ForegroundColor Green
Write-Output $output
