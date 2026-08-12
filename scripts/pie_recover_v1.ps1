param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# Deliberate recovery of any interrupted multi-file state transaction (B3). Rolls back transactions
# killed before their COMMIT marker and rolls forward those killed after it. Run this at a point when
# no `pie run`/session write is in flight; it is intentionally NOT auto-invoked mid-run so it cannot
# clobber a concurrent transaction.

. (Join-Path $RepoRoot "scripts\_lib_pie_txn_v1.ps1")
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$r = PIE_TxnRecover $RepoRoot
Write-Host ("OK: recover complete. rolled_forward=" + $r.recovered + " rolled_back=" + $r.rolled_back) -ForegroundColor Green
