param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$false)][string]$ModelId = 'pie-onnx-fixture'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

function Die([string]$Message){ throw ('SELFTEST_PIE_RUN_PROVENANCE_FAIL: ' + $Message) }
function Invoke-Child([string]$Script,[string[]]$Arguments){
  $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try { $output = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Script @Arguments 2>&1 | Out-String; $code = $LASTEXITCODE }
  finally { $ErrorActionPreference = $old }
  return [pscustomobject]@{ output=$output; code=$code }
}

$runScript = Join-Path $RepoRoot 'scripts\pie_run_v1.ps1'
$sealScript = Join-Path $RepoRoot 'scripts\pie_run_seal_v1.ps1'
$verifyScript = Join-Path $RepoRoot 'scripts\pie_run_verify_v1.ps1'
$ledgerPath = Join-Path $RepoRoot 'runs\run_ledger.ndjson'
$marker = 'provenance-selftest-' + [guid]::NewGuid().ToString('n')

Write-Host 'PIE_RUN_PROVENANCE_SELFTEST_START' -ForegroundColor DarkCyan
$run = Invoke-Child $runScript @('-RepoRoot',$RepoRoot,'-ModelId',$ModelId,'-Prompt',$marker,'-Backend','stub')
if($run.code -ne 0){ Die ('run failed: ' + $run.output) }
$record = (Get-Content -LiteralPath $ledgerPath | Select-Object -Last 1) | ConvertFrom-Json
$runId = [string]$record.run_id

foreach($suffix in @('input.txt','output.txt','record.json','provenance.json')){
  $path = Join-Path $RepoRoot ('runs\run_' + $runId + '_' + $suffix)
  if(-not (Test-Path -LiteralPath $path -PathType Leaf)){ Die ('missing run artifact ' + $suffix) }
}
$provenance = Get-Content -LiteralPath (Join-Path $RepoRoot ('runs\run_' + $runId + '_provenance.json')) -Raw | ConvertFrom-Json
if([string]$provenance.schema -ne 'pie.run.provenance.v1'){ Die 'wrong provenance schema' }
if([bool]$provenance.inference_certified){ Die 'stub was incorrectly certified as real inference' }
if(-not [bool]$provenance.model_identity_verified){ Die 'fixture bytes were not verified' }

$seal = Invoke-Child $sealScript @('-RepoRoot',$RepoRoot,'-RunId',$runId)
if($seal.code -ne 0){ Die ('seal failed: ' + $seal.output) }
$runRoot = Join-Path $RepoRoot ('runs\run_' + $runId)
$verify = Invoke-Child $verifyScript @('-RepoRoot',$RepoRoot,'-RunRoot',$runRoot)
if($verify.code -ne 0 -or $verify.output -notmatch 'PIE_RUN_VERIFY_VALID'){ Die ('valid seal rejected: ' + $verify.output) }

$certified = Invoke-Child $verifyScript @('-RepoRoot',$RepoRoot,'-RunRoot',$runRoot,'-RequireCertifiedInference')
if($certified.code -eq 0){ Die 'stub seal passed RequireCertifiedInference' }

$testRoot = Join-Path $RepoRoot ('runs\provenance_selftest\' + [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
try {
  Copy-Item -LiteralPath $runRoot -Destination (Join-Path $testRoot 'tampered') -Recurse -Force
  [System.IO.File]::AppendAllText((Join-Path $testRoot 'tampered\output.txt'),'tamper',(New-Object System.Text.UTF8Encoding($false)))
  $negative = Invoke-Child $verifyScript @('-RepoRoot',$RepoRoot,'-RunRoot',(Join-Path $testRoot 'tampered'))
  if($negative.code -eq 0){ Die 'tampered output passed verification' }
}
finally {
  $selftestRoot = (Resolve-Path -LiteralPath (Join-Path $RepoRoot 'runs\provenance_selftest')).Path
  $resolvedTestRoot = (Resolve-Path -LiteralPath $testRoot -ErrorAction SilentlyContinue).Path
  if($resolvedTestRoot -and $resolvedTestRoot.StartsWith($selftestRoot + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){
    Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
  }
}

Write-Host ('  provenance, certified-mode, and tamper checks: OK for ' + $runId) -ForegroundColor Green
Write-Host 'SELFTEST_PIE_RUN_PROVENANCE_V1_GREEN' -ForegroundColor Green
