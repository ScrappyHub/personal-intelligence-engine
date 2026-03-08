param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$ModelId,
  [Parameter(Mandatory=$true)][string]$Prompt,
  [ValidateSet('0.25','0.5','0.75','1.0')][string]$SpeedFactor='1.0'
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

# Backend execution stub (replace with engine adapters but keep recording law)
$output = ('PIE_STUB_OUTPUT model=' + $ModelId + ' speed=' + $SpeedFactor + ' prompt_sha256=' + $inHash + ' model_sums=' + $sumsSha)

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

[void](PIE_AppendRunLedger $RepoRoot $rec)

# Write plaintext artifacts (inputs/outputs) to support later sealing
$inPath  = Join-Path $RepoRoot ('runs\run_' + $runId + '_input.txt')
$outPath = Join-Path $RepoRoot ('runs\run_' + $runId + '_output.txt')

NL_WriteUtf8NoBomLf $inPath  $Prompt
NL_WriteUtf8NoBomLf $outPath $output

Write-Host ('OK: run recorded: ' + $runId) -ForegroundColor Green
Write-Output $output
