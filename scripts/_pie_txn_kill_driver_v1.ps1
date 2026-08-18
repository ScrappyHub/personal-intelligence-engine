param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$TargetA,
  [Parameter(Mandatory=$true)][string]$TargetB
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Minimal transaction driver for the OS-kill injection harness. Runs a two-file transaction against
# scratch targets; PIE_TxnCommit will block at a kill window if PIE_TXN_KILL_* is set, so the parent
# harness can Stop-Process -Force this process at that exact transition point.

# Locate the library relative to this driver (it lives in scripts/), so -RepoRoot can be a scratch
# transaction base (which has no scripts/ dir) rather than the real repo root.
. (Join-Path $PSScriptRoot "_lib_pie_txn_v1.ps1")
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$txn = PIE_TxnBegin $RepoRoot
PIE_TxnStage $txn $TargetA "KILLTEST_A"
PIE_TxnStage $txn $TargetB "KILLTEST_B"
PIE_TxnCommit $txn

Write-Host "TXN_KILL_DRIVER_COMPLETED"
