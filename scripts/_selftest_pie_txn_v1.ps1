param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Certification for the multi-file transaction / crash-recovery primitive (release-blocker B3).
# check1  full commit applies all targets, txn dir removed.
# check2  kill BEFORE commit -> recovery rolls back; no target changed.
# check3  kill AFTER commit mid-apply -> recovery rolls forward; all targets applied.
# check4  recovery is idempotent (second pass is a no-op).
# Emits SELFTEST_PIE_TXN_V1_GREEN on success.
# All txn ops use an isolated scratch base as the "RepoRoot" so recovery never touches real state.

function Die([string]$m){ throw ("SELFTEST_TXN_FAIL: " + $m) }

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $RepoRoot "scripts\_lib_pie_txn_v1.ps1")

$enc  = New-Object System.Text.UTF8Encoding($false)
$base = Join-Path $RepoRoot ("runs\txn_selftest_" + ([guid]::NewGuid().ToString('n')))
$tgt  = Join-Path $base "targets"
New-Item -ItemType Directory -Path $tgt -Force | Out-Null
$tA = Join-Path $tgt "a.txt"
$tB = Join-Path $tgt "b.txt"
function ReadT([string]$p){ if(Test-Path -LiteralPath $p -PathType Leaf){ [System.IO.File]::ReadAllText($p,$enc) } else { "" } }

Write-Host "PIE_TXN_SELFTEST_START" -ForegroundColor DarkCyan

try {
  # check1: full commit.
  $t = PIE_TxnBegin $base "commit1"
  PIE_TxnStage $t $tA "NEW_A"
  PIE_TxnStage $t $tB "NEW_B"
  PIE_TxnCommit $t
  if((ReadT $tA) -ne "NEW_A`n"){ Die "commit did not apply target A" }
  if((ReadT $tB) -ne "NEW_B`n"){ Die "commit did not apply target B" }
  if(Test-Path -LiteralPath (Join-Path (PIE_TxnRoot $base) "commit1")){ Die "committed txn dir not removed" }
  Write-Host "  check1_full_commit: OK" -ForegroundColor Green

  # check2: kill before commit -> rollback.
  PIE_WriteFileAtomic $tA "ORIG_A"
  PIE_WriteFileAtomic $tB "ORIG_B"
  $t2 = PIE_TxnBegin $base "rollback1"
  PIE_TxnStage $t2 $tA "SHOULD_NOT_APPLY_A"
  PIE_TxnStage $t2 $tB "SHOULD_NOT_APPLY_B"
  # no commit -> simulate crash, then recover
  $r2 = PIE_TxnRecover $base
  if($r2.rolled_back -lt 1){ Die "rollback not counted" }
  if((ReadT $tA) -ne "ORIG_A`n"){ Die "rollback changed target A" }
  if((ReadT $tB) -ne "ORIG_B`n"){ Die "rollback changed target B" }
  if(Test-Path -LiteralPath (Join-Path (PIE_TxnRoot $base) "rollback1")){ Die "rolled-back txn dir not removed" }
  Write-Host "  check2_rollback_before_commit: OK" -ForegroundColor Green

  # check3: kill after commit, mid-apply -> roll forward. Build the crash state on disk manually.
  PIE_WriteFileAtomic $tA "ORIG_A"
  PIE_WriteFileAtomic $tB "ORIG_B"
  $txnDir = Join-Path (PIE_TxnRoot $base) "rollfwd1"
  New-Item -ItemType Directory -Path $txnDir -Force | Out-Null
  PIE_WriteFileAtomic (Join-Path $txnDir "staged_0") "RF_A"
  PIE_WriteFileAtomic (Join-Path $txnDir "staged_1") "RF_B"
  $journal = [ordered]@{ schema="pie.txn.journal.v1"; txn_id="rollfwd1"; items=@(
    [ordered]@{ staged="staged_0"; target=$tA },
    [ordered]@{ staged="staged_1"; target=$tB }
  ) }
  PIE_WriteFileAtomic (Join-Path $txnDir "journal.json") ($journal | ConvertTo-Json -Depth 6)
  PIE_WriteFileAtomic (Join-Path $txnDir "COMMIT") "rollfwd1"
  # simulate: only target A applied before the kill
  PIE_WriteFileAtomic $tA "RF_A"
  $r3 = PIE_TxnRecover $base
  if($r3.recovered -lt 1){ Die "roll-forward not counted" }
  if((ReadT $tA) -ne "RF_A`n"){ Die "roll-forward target A wrong" }
  if((ReadT $tB) -ne "RF_B`n"){ Die "roll-forward did not complete target B" }
  if(Test-Path -LiteralPath $txnDir){ Die "rolled-forward txn dir not removed" }
  Write-Host "  check3_rollforward_after_commit: OK" -ForegroundColor Green

  # check4: idempotent recovery (nothing pending).
  $r4 = PIE_TxnRecover $base
  if($r4.recovered -ne 0 -or $r4.rolled_back -ne 0){ Die "recovery not idempotent" }
  if((ReadT $tA) -ne "RF_A`n" -or (ReadT $tB) -ne "RF_B`n"){ Die "idempotent recovery changed state" }
  Write-Host "  check4_idempotent_recovery: OK" -ForegroundColor Green

  $rcptDir = Join-Path $RepoRoot "runs\txn_selftest"
  if(-not (Test-Path -LiteralPath $rcptDir -PathType Container)){ New-Item -ItemType Directory -Path $rcptDir -Force | Out-Null }
  $stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss_fff")
  $receipt = [ordered]@{ schema="pie.txn.selftest.receipt.v1"; generated_utc=(Get-Date).ToUniversalTime().ToString("o"); checks=4; green=$true }
  [System.IO.File]::WriteAllText((Join-Path $rcptDir ($stamp + ".json")), ($receipt | ConvertTo-Json -Depth 5), $enc)
}
finally {
  if(Test-Path -LiteralPath $base -PathType Container){ Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host "SELFTEST_PIE_TXN_V1_GREEN" -ForegroundColor Green
