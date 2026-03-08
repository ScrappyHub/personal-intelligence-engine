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

$RunPath = Join-Path $RepoRoot "scripts\pie_run_v1.ps1"
if (-not (Test-Path -LiteralPath $RunPath -PathType Leaf)) { Die ("MISSING_TARGET: " + $RunPath) }

$bak = $RunPath + ".bak_" + (Get-Date -Format "yyyyMMdd_HHmmss")
Copy-Item -LiteralPath $RunPath -Destination $bak -Force | Out-Null

# Full rewrite (avoid anchor drift)
$new = @"
param(
  [Parameter(Mandatory=`$true)][string]`$RepoRoot,
  [Parameter(Mandatory=`$true)][string]`$ModelId,
  [Parameter(Mandatory=`$true)][string]`$Prompt,
  [ValidateSet('0.25','0.5','0.75','1.0')][string]`$SpeedFactor='1.0'
)

`$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

. (Join-Path `$RepoRoot 'scripts\_lib_pie_v1.ps1')

`$RepoRoot = `$RepoRoot.TrimEnd('\')

# Require sealed model manifest
`$mp = PIE_ModelManifestPath `$RepoRoot `$ModelId
if (-not (Test-Path -LiteralPath `$mp -PathType Leaf)) { PIE_Die ('missing_model_manifest: ' + `$mp) }

`$mj = (NL_ReadUtf8 `$mp) | ConvertFrom-Json

`$sumsSha    = [string]`$mj.sums_sha256
`$weightsSha = [string]`$mj.weights_sha256

if ([string]::IsNullOrWhiteSpace(`$sumsSha))    { PIE_Die ('missing_sums_sha256_in_model_manifest: ' + `$mp) }
if ([string]::IsNullOrWhiteSpace(`$weightsSha)) { PIE_Die ('missing_weights_sha256_in_model_manifest: ' + `$mp) }

# Params hash (canonical JSON)
`$params = @{ speed_factor = `$SpeedFactor }
`$paramsHash = PIE_Sha256HexBytes ([System.Text.Encoding]::UTF8.GetBytes((NL_ToCanonJson `$params)))

# Input hash is over canonical bytes of prompt text (as provided)
`$inBytes = [System.Text.Encoding]::UTF8.GetBytes(`$Prompt)
`$inHash  = PIE_Sha256HexBytes `$inBytes

# Backend execution stub (replace with engine adapters but keep recording law)
`$output = ('PIE_STUB_OUTPUT model=' + `$ModelId + ' speed=' + `$SpeedFactor + ' prompt_sha256=' + `$inHash + ' model_sums=' + `$sumsSha)

`$outHash = PIE_Sha256HexBytes ([System.Text.Encoding]::UTF8.GetBytes(`$output))
`$runId   = ([guid]::NewGuid().ToString('n'))

# Instrument-grade: bind run to sealed model set (sums_sha256) + expose weights_sha256 too
`$rec = @{
  schema       = 'run_record.v1'
  run_id       = `$runId
  model_id     = `$ModelId

  # Strong binding (sealed set)
  sums_sha256  = `$sumsSha

  # Extra signal (weights-only)
  weights_sha256 = `$weightsSha

  # Back-compat slot: treat model_sha256 as sums_sha256 (stronger than weights-only)
  model_sha256 = `$sumsSha

  input_hash   = ('sha256:' + `$inHash)
  output_hash  = ('sha256:' + `$outHash)
  params_hash  = ('sha256:' + `$paramsHash)
  time_utc     = (Get-Date).ToUniversalTime().ToString('o')
}

[void](PIE_AppendRunLedger `$RepoRoot `$rec)

# Write plaintext artifacts (inputs/outputs) to support later sealing
`$inPath  = Join-Path `$RepoRoot ('runs\run_' + `$runId + '_input.txt')
`$outPath = Join-Path `$RepoRoot ('runs\run_' + `$runId + '_output.txt')

NL_WriteUtf8NoBomLf `$inPath  `$Prompt
NL_WriteUtf8NoBomLf `$outPath `$output

Write-Host ('OK: run recorded: ' + `$runId) -ForegroundColor Green
Write-Output `$output
"@

Parse-GateText $new
Write-Utf8NoBomLf $RunPath $new
Parse-GateText (Read-Utf8NoBom $RunPath)

Write-Host ("PATCH_OK: pie_run_v1.ps1 now requires sealed model + records sums_sha256; backup=" + $bak) -ForegroundColor Green
