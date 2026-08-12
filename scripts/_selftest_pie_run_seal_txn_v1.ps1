param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$false)][string]$ModelId = "pie-onnx-fixture"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

# Verifies the B3 adoption: a real (stub) run applies its ledger + input + output artifacts as one
# crash-atomic transaction, leaving no orphan txn dir. Appends one legitimate stub run entry to the
# real ledger (that is what the append-only ledger is for). Emits SELFTEST_PIE_RUN_SEAL_TXN_V1_GREEN.

function Die([string]$m){ throw ("SELFTEST_RUN_SEAL_TXN_FAIL: " + $m) }

$RepoRoot  = (Resolve-Path -LiteralPath $RepoRoot).Path
$runScript = Join-Path $RepoRoot "scripts\pie_run_v1.ps1"
$ledgerPath = Join-Path $RepoRoot "runs\run_ledger.ndjson"
$txnRoot   = Join-Path $RepoRoot "runs\txn"
$enc = New-Object System.Text.UTF8Encoding($false)

function LedgerLines {
  if(-not (Test-Path -LiteralPath $ledgerPath -PathType Leaf)){ return @() }
  @(@([System.IO.File]::ReadAllLines($ledgerPath,$enc)) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}
function TxnDirCount {
  if(-not (Test-Path -LiteralPath $txnRoot -PathType Container)){ return 0 }
  @(Get-ChildItem -LiteralPath $txnRoot -Directory -ErrorAction SilentlyContinue).Count
}

Write-Host "PIE_RUN_SEAL_TXN_SELFTEST_START" -ForegroundColor DarkCyan

$before = (LedgerLines).Count
$marker = "seal-txn-selftest " + ([guid]::NewGuid().ToString('n'))

$out = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runScript `
  -RepoRoot $RepoRoot -ModelId $ModelId -Prompt $marker -Backend stub 2>&1 | Out-String)
if($LASTEXITCODE -ne 0){ Die ("stub run failed: " + $out) }

# Exactly one new ledger line.
$after = LedgerLines
if($after.Count -ne ($before + 1)){ Die ("ledger grew by " + ($after.Count - $before) + ", expected 1") }

# Parse the new line; find its run_id + artifacts.
$rec = $after[$after.Count - 1] | ConvertFrom-Json
$runId = [string]$rec.run_id
if([string]::IsNullOrWhiteSpace($runId)){ Die "new ledger line missing run_id" }
if($rec.schema -ne "run_record.v1"){ Die ("unexpected schema: " + $rec.schema) }

$inPath  = Join-Path $RepoRoot ("runs\run_" + $runId + "_input.txt")
$outPath = Join-Path $RepoRoot ("runs\run_" + $runId + "_output.txt")
if(-not (Test-Path -LiteralPath $inPath -PathType Leaf)){ Die "input artifact missing" }
if(-not (Test-Path -LiteralPath $outPath -PathType Leaf)){ Die "output artifact missing" }
$inTxt  = [System.IO.File]::ReadAllText($inPath,$enc)
$outTxt = [System.IO.File]::ReadAllText($outPath,$enc)
if($inTxt -notmatch [regex]::Escape($marker)){ Die "input artifact content wrong" }
if($outTxt -notmatch 'PIE_STUB_OUTPUT'){ Die "output artifact content wrong" }

# No orphan transaction directory left behind (commit fully applied + cleaned up).
if((TxnDirCount) -ne 0){ Die "orphan txn dir left after commit" }

Write-Host ("  ledger+input+output applied atomically for run " + $runId + ": OK") -ForegroundColor Green
Write-Host "SELFTEST_PIE_RUN_SEAL_TXN_V1_GREEN" -ForegroundColor Green
