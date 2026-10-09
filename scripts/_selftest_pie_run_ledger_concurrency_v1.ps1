param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$false)][ValidateRange(2,16)][int]$Workers = 6,
  [Parameter(Mandatory=$false)][string]$ModelId = 'pie-onnx-fixture'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $RepoRoot 'scripts\_lib_pie_v1.ps1')

function Die([string]$Message){ throw ('SELFTEST_PIE_RUN_LEDGER_CONCURRENCY_FAIL: ' + $Message) }
function Read-Lines([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ return @() }
  return @([System.IO.File]::ReadAllLines($Path,(New-Object System.Text.UTF8Encoding($false))) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

$ledgerPath = Join-Path $RepoRoot 'runs\run_ledger.ndjson'
$runScript = Join-Path $RepoRoot 'scripts\pie_run_v1.ps1'
$before = @(Read-Lines $ledgerPath)
$testId = [guid]::NewGuid().ToString('n')
$logRoot = Join-Path $RepoRoot ('runs\ledger_concurrency_selftest\' + $testId)
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
$processes = New-Object System.Collections.Generic.List[object]

Write-Host ('PIE_RUN_LEDGER_CONCURRENCY_SELFTEST_START workers=' + $Workers) -ForegroundColor DarkCyan
try {
  for($worker=0; $worker -lt $Workers; $worker++){
    $stdout = Join-Path $logRoot ('worker_' + $worker + '.out.txt')
    $stderr = Join-Path $logRoot ('worker_' + $worker + '.err.txt')
    $arguments = @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$runScript,'-RepoRoot',$RepoRoot,'-ModelId',$ModelId,'-Prompt',($testId + '-' + $worker),'-Backend','stub')
    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -RedirectStandardOutput $stdout -RedirectStandardError $stderr -WindowStyle Hidden -PassThru
    $processes.Add([pscustomobject]@{ process=$process; stdout=$stdout; stderr=$stderr })
  }
  foreach($entry in $processes){
    $entry.process.WaitForExit()
    $entry.process.Refresh()
    $workerExitCode = $entry.process.ExitCode
    $workerOut = Get-Content -LiteralPath $entry.stdout -Raw -ErrorAction SilentlyContinue
    $workerErr = Get-Content -LiteralPath $entry.stderr -Raw -ErrorAction SilentlyContinue
    $workerSucceeded = ($workerExitCode -eq 0) -or ($null -eq $workerExitCode -and $workerOut -match 'OK: run recorded:' -and [string]::IsNullOrWhiteSpace($workerErr))
    if(-not $workerSucceeded){
      Die ('worker failed: exit=' + $workerExitCode + ' stdout=' + $workerOut + ' stderr=' + $workerErr)
    }
  }

  $after = @(Read-Lines $ledgerPath)
  if($after.Count -ne ($before.Count + $Workers)){ Die ('ledger growth was ' + ($after.Count - $before.Count) + ', expected ' + $Workers) }
  $newLines = @($after | Select-Object -Skip $before.Count)
  $previous = ''
  if($before.Count -gt 0){ $previous = $before[$before.Count - 1] }
  $runIds = @{}
  foreach($line in $newLines){
    $record = $line | ConvertFrom-Json
    if($runIds.ContainsKey([string]$record.run_id)){ Die ('duplicate run id ' + [string]$record.run_id) }
    $runIds[[string]$record.run_id] = $true
    if(-not [string]::IsNullOrWhiteSpace($previous)){
      $expectedPrev = PIE_Sha256HexBytes ([System.Text.Encoding]::UTF8.GetBytes($previous))
      if([string]$record.prev_hash -ne $expectedPrev){ Die ('hash-chain mismatch at ' + [string]$record.run_id) }
    }
    foreach($suffix in @('input.txt','output.txt','record.json','provenance.json')){
      if(-not (Test-Path -LiteralPath (Join-Path $RepoRoot ('runs\run_' + [string]$record.run_id + '_' + $suffix)) -PathType Leaf)){ Die ('missing ' + $suffix + ' for ' + [string]$record.run_id) }
    }
    $previous = $line
  }
}
finally {
  foreach($entry in $processes){ if(-not $entry.process.HasExited){ $entry.process.Kill(); $entry.process.WaitForExit() }; $entry.process.Dispose() }
  $selftestRoot = (Resolve-Path -LiteralPath (Join-Path $RepoRoot 'runs\ledger_concurrency_selftest')).Path
  $resolvedLogRoot = (Resolve-Path -LiteralPath $logRoot -ErrorAction SilentlyContinue).Path
  if($resolvedLogRoot -and $resolvedLogRoot.StartsWith($selftestRoot + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){
    Remove-Item -LiteralPath $resolvedLogRoot -Recurse -Force
  }
}

Write-Host ('  concurrent ledger append and hash chain: OK (' + $Workers + ' runs)') -ForegroundColor Green
Write-Host 'SELFTEST_PIE_RUN_LEDGER_CONCURRENCY_V1_GREEN' -ForegroundColor Green
