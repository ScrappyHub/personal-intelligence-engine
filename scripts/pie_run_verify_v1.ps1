param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$RunRoot,
  [switch]$RequireCertifiedInference
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$RunRoot = (Resolve-Path -LiteralPath $RunRoot).Path
. (Join-Path $RepoRoot 'scripts\_lib_neverlost_v1.ps1')
. (Join-Path $RepoRoot 'scripts\_lib_pie_v1.ps1')

function Die([string]$Message){ throw ('PIE_RUN_VERIFY_INVALID: ' + $Message) }
function Read-Text([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ('missing ' + $Path) }
  return [System.IO.File]::ReadAllText($Path,(New-Object System.Text.UTF8Encoding($false)))
}
function Normalize-Relative([string]$Path){ return $Path.Replace('\','/') }
function Is-SafeRelative([string]$Path){
  if([string]::IsNullOrWhiteSpace($Path) -or [System.IO.Path]::IsPathRooted($Path)){ return $false }
  $normalized = Normalize-Relative $Path
  return -not ($normalized -match '(^|/)\.\.(/|$)')
}

$required = @('adapter.ps1','input.txt','model_manifest.json','output.txt','persona.txt','provenance.json','record.json','sha256sums.txt')
foreach($name in $required){ if(-not (Test-Path -LiteralPath (Join-Path $RunRoot $name) -PathType Leaf)){ Die ('missing required file ' + $name) } }

$listed = @{}
foreach($line in @((Read-Text (Join-Path $RunRoot 'sha256sums.txt')) -split "`n")){
  if([string]::IsNullOrWhiteSpace($line)){ continue }
  $match = [regex]::Match($line.TrimEnd("`r"),'^(?<hash>[0-9a-f]{64})\s{2}(?<path>.+)$')
  if(-not $match.Success){ Die ('invalid sha256sums line ' + $line) }
  $relative = Normalize-Relative $match.Groups['path'].Value
  if(-not (Is-SafeRelative $relative)){ Die ('unsafe checksum path ' + $relative) }
  if($listed.ContainsKey($relative)){ Die ('duplicate checksum path ' + $relative) }
  $fullPath = Join-Path $RunRoot $relative.Replace('/','\')
  if(-not (Test-Path -LiteralPath $fullPath -PathType Leaf)){ Die ('checksum target missing ' + $relative) }
  if((PIE_Sha256HexFile $fullPath) -ne $match.Groups['hash'].Value){ Die ('checksum mismatch ' + $relative) }
  $listed[$relative] = $true
}

$actualFiles = @(Get-ChildItem -LiteralPath $RunRoot -File | Where-Object { $_.Name -ne 'sha256sums.txt' } | ForEach-Object { Normalize-Relative $_.Name } | Sort-Object)
foreach($actualFile in $actualFiles){ if(-not $listed.ContainsKey($actualFile)){ Die ('unlisted sealed file ' + $actualFile) } }
foreach($listedFile in @($listed.Keys)){ if($actualFiles -notcontains $listedFile){ Die ('checksum lists unexpected file ' + $listedFile) } }

try { $record = (Read-Text (Join-Path $RunRoot 'record.json')) | ConvertFrom-Json } catch { Die ('record JSON invalid: ' + $_.Exception.Message) }
try { $provenance = (Read-Text (Join-Path $RunRoot 'provenance.json')) | ConvertFrom-Json } catch { Die ('provenance JSON invalid: ' + $_.Exception.Message) }
try { $manifest = (Read-Text (Join-Path $RunRoot 'model_manifest.json')) | ConvertFrom-Json } catch { Die ('model manifest JSON invalid: ' + $_.Exception.Message) }

$runId = [string]$record.run_id
if($runId -notmatch '^[0-9a-f]{32}$' -or [string]$provenance.run_id -ne $runId){ Die 'run id binding mismatch' }
if([string]$provenance.schema -ne 'pie.run.provenance.v1'){ Die ('unsupported provenance schema ' + [string]$provenance.schema) }
if([string]$manifest.model_id -ne [string]$record.model_id -or [string]$provenance.model_id -ne [string]$record.model_id){ Die 'model id binding mismatch' }

$inputHash = 'sha256:' + (PIE_Sha256HexFile (Join-Path $RunRoot 'input.txt'))
$outputHash = 'sha256:' + (PIE_Sha256HexFile (Join-Path $RunRoot 'output.txt'))
if([string]$record.input_hash -ne $inputHash -or [string]$provenance.input_sha256 -ne $inputHash){ Die 'input hash binding mismatch' }
if([string]$record.output_hash -ne $outputHash -or [string]$provenance.output_sha256 -ne $outputHash){ Die 'output hash binding mismatch' }
if([string]$record.params_hash -ne [string]$provenance.params_sha256){ Die 'parameter hash binding mismatch' }
$paramsHash = 'sha256:' + (PIE_Sha256HexBytes ([System.Text.Encoding]::UTF8.GetBytes((NL_ToCanonJson $provenance.params))))
if($paramsHash -ne [string]$provenance.params_sha256){ Die 'parameter bytes mismatch' }

$recordLine = (Read-Text (Join-Path $RunRoot 'record.json')).TrimEnd("`r","`n")
$recordHash = 'sha256:' + (PIE_Sha256HexBytes ([System.Text.Encoding]::UTF8.GetBytes($recordLine)))
if($recordHash -ne [string]$provenance.record_line_sha256){ Die 'record line hash mismatch' }
if(('sha256:' + (PIE_Sha256HexFile (Join-Path $RunRoot 'model_manifest.json'))) -ne [string]$provenance.model_manifest_sha256){ Die 'model manifest hash mismatch' }
if(('sha256:' + (PIE_Sha256HexFile (Join-Path $RunRoot 'adapter.ps1'))) -ne [string]$provenance.adapter_script_sha256){ Die 'adapter hash mismatch' }
if(('sha256:' + (PIE_Sha256HexFile (Join-Path $RunRoot 'persona.txt'))) -ne [string]$provenance.persona_sha256){ Die 'persona hash mismatch' }

$contractFile = Join-Path $RunRoot 'adapter_contract.json'
$contractExpected = [string]$provenance.adapter_contract_sha256
if([string]::IsNullOrWhiteSpace($contractExpected)){
  if(Test-Path -LiteralPath $contractFile -PathType Leaf){ Die 'unexpected adapter contract' }
} else {
  if(-not (Test-Path -LiteralPath $contractFile -PathType Leaf)){ Die 'adapter contract missing' }
  if(('sha256:' + (PIE_Sha256HexFile $contractFile)) -ne $contractExpected){ Die 'adapter contract hash mismatch' }
}

$certified = [bool]$provenance.inference_certified
if($certified -and (-not [bool]$provenance.model_identity_verified -or -not [bool]$provenance.backend_binding_verified -or [string]$provenance.backend -eq 'stub')){
  Die 'invalid certified inference claim'
}
if($RequireCertifiedInference -and -not $certified){ Die 'certified real inference required' }

Write-Host ('PIE_RUN_VERIFY_VALID: ' + $runId + ' inference_certified=' + $certified.ToString().ToLowerInvariant()) -ForegroundColor Green
[pscustomobject]@{ run_id=$runId; inference_certified=$certified; backend=[string]$provenance.backend }
