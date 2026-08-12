Set-StrictMode -Version Latest

# PIE multi-file transaction / write-ahead journal (release-blocker B3 foundation).
# Guarantees all-or-nothing application of a set of file writes across a crash:
#   - killed BEFORE the COMMIT marker  -> rolls back on recovery (no target touched)
#   - killed AFTER the COMMIT marker    -> rolls forward on recovery (all targets applied)
# The COMMIT marker's existence is the atomic commit point. Per-file applies use
# PIE_WriteFileAtomic (B2), so each individual target write is itself torn-write safe.

. (Join-Path $PSScriptRoot "_lib_pie_atomic_v1.ps1")

function PIE_TxnRoot([string]$RepoRoot){ Join-Path $RepoRoot "runs\txn" }

function PIE_TxnBegin([string]$RepoRoot,[string]$TxnId){
  if([string]::IsNullOrWhiteSpace($TxnId)){ $TxnId = [guid]::NewGuid().ToString('n') }
  $dir = Join-Path (PIE_TxnRoot $RepoRoot) $TxnId
  if(Test-Path -LiteralPath $dir){ throw ("PIE_TXN_ALREADY_EXISTS: " + $dir) }
  New-Item -ItemType Directory -Path $dir -Force | Out-Null
  return [pscustomobject]@{ root=$RepoRoot; id=$TxnId; dir=$dir; items=(New-Object System.Collections.Generic.List[object]) }
}

function PIE_TxnStage($Txn,[string]$TargetPath,[string]$Text){
  $idx = $Txn.items.Count
  $staged = "staged_" + $idx
  PIE_WriteFileAtomic (Join-Path $Txn.dir $staged) $Text
  $Txn.items.Add([pscustomobject]@{ staged=$staged; target=$TargetPath })
}

function PIE_TxnWriteJournal($Txn){
  $items = @($Txn.items | ForEach-Object { [ordered]@{ staged=$_.staged; target=$_.target } })
  $journal = [ordered]@{ schema="pie.txn.journal.v1"; txn_id=$Txn.id; items=$items }
  PIE_WriteFileAtomic (Join-Path $Txn.dir "journal.json") ($journal | ConvertTo-Json -Depth 6)
}

# Apply a committed txn dir's staged files to their targets (idempotent), then remove the dir.
function PIE_TxnApplyDir([string]$TxnDir){
  $journalPath = Join-Path $TxnDir "journal.json"
  if(-not (Test-Path -LiteralPath $journalPath -PathType Leaf)){ throw ("PIE_TXN_JOURNAL_MISSING: " + $TxnDir) }
  $enc = New-Object System.Text.UTF8Encoding($false)
  $j = [System.IO.File]::ReadAllText($journalPath,$enc) | ConvertFrom-Json
  foreach($it in @($j.items)){
    $stagedPath = Join-Path $TxnDir ([string]$it.staged)
    if(-not (Test-Path -LiteralPath $stagedPath -PathType Leaf)){ throw ("PIE_TXN_STAGED_MISSING: " + $stagedPath) }
    $content = [System.IO.File]::ReadAllText($stagedPath,$enc)
    PIE_WriteFileAtomic ([string]$it.target) $content
  }
  Remove-Item -LiteralPath $TxnDir -Recurse -Force
}

function PIE_TxnCommit($Txn){
  PIE_TxnWriteJournal $Txn
  PIE_WriteFileAtomic (Join-Path $Txn.dir "COMMIT") $Txn.id   # atomic commit point
  PIE_TxnApplyDir $Txn.dir
}

# Recover any interrupted transactions: roll forward those past COMMIT, roll back the rest.
function PIE_TxnRecover([string]$RepoRoot){
  $root = PIE_TxnRoot $RepoRoot
  $recovered = 0; $rolledBack = 0
  if(-not (Test-Path -LiteralPath $root -PathType Container)){ return [pscustomobject]@{ recovered=0; rolled_back=0 } }
  foreach($d in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)){
    if(Test-Path -LiteralPath (Join-Path $d.FullName "COMMIT") -PathType Leaf){
      PIE_TxnApplyDir $d.FullName
      $recovered++
    } else {
      Remove-Item -LiteralPath $d.FullName -Recurse -Force
      $rolledBack++
    }
  }
  return [pscustomobject]@{ recovered=$recovered; rolled_back=$rolledBack }
}
