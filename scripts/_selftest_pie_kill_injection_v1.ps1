param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

# OS-level process-kill injection (release-blocker B2/B3 deepening). Launches a real transaction in a
# child process, waits until it is blocked at an exact commit transition, then Stop-Process -Force
# kills it (NO finally/cleanup runs -- a true crash), and proves PIE_TxnRecover reconciles:
#   kill BEFORE the COMMIT marker -> rollback (targets untouched)
#   kill AFTER  the COMMIT marker -> roll forward (targets fully applied)
# Emits SELFTEST_PIE_KILL_INJECTION_V1_GREEN.

function Die([string]$m){ throw ("SELFTEST_KILL_INJECTION_FAIL: " + $m) }

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $RepoRoot "scripts\_lib_pie_txn_v1.ps1")
$enc = New-Object System.Text.UTF8Encoding($false)

$base   = Join-Path $RepoRoot ("runs\kill_selftest_" + ([guid]::NewGuid().ToString('n')))
$tgtDir = Join-Path $base "targets"
New-Item -ItemType Directory -Path $tgtDir -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $base "runs") -Force | Out-Null
$tA     = Join-Path $tgtDir "a.txt"
$tB     = Join-Path $tgtDir "b.txt"
$sig    = Join-Path $base "kill_ready.txt"
$driver = Join-Path $RepoRoot "scripts\_pie_txn_kill_driver_v1.ps1"
$txnRoot = Join-Path $base "runs\txn"

function ReadT([string]$p){ if(Test-Path -LiteralPath $p -PathType Leaf){ [System.IO.File]::ReadAllText($p,$enc) } else { "" } }
function TxnDir { if(-not (Test-Path -LiteralPath $txnRoot -PathType Container)){ return $null } @(Get-ChildItem -LiteralPath $txnRoot -Directory -ErrorAction SilentlyContinue) | Select-Object -First 1 }

function Invoke-KilledTxn([string]$EnvName){
  [System.IO.File]::WriteAllText($tA, "ORIG_A`n", $enc)
  [System.IO.File]::WriteAllText($tB, "ORIG_B`n", $enc)
  if(Test-Path -LiteralPath $sig -PathType Leaf){ Remove-Item -LiteralPath $sig -Force }

  $env:PIE_TXN_KILL_SIGNAL = $sig
  Set-Item -Path ("Env:" + $EnvName) -Value "1"
  try {
    $p = Start-Process -FilePath "powershell.exe" -PassThru -WindowStyle Hidden -ArgumentList @(
      "-NoProfile","-ExecutionPolicy","Bypass","-File",$driver,"-RepoRoot",$base,"-TargetA",$tA,"-TargetB",$tB)
    $waitedMs = 0
    while(-not (Test-Path -LiteralPath $sig -PathType Leaf)){
      Start-Sleep -Milliseconds 200; $waitedMs += 200
      if($p.HasExited){ Die "child exited before reaching the kill window" }
      if($waitedMs -ge 20000){ Die "child never reached the kill window (timeout)" }
    }
    Stop-Process -Id $p.Id -Force
    [void]$p.WaitForExit(5000)
  }
  finally {
    Remove-Item -Path ("Env:" + $EnvName) -ErrorAction SilentlyContinue
    Remove-Item Env:\PIE_TXN_KILL_SIGNAL -ErrorAction SilentlyContinue
  }
}

Write-Host "PIE_KILL_INJECTION_SELFTEST_START" -ForegroundColor DarkCyan

try {
  # --- Scenario 1: kill BEFORE commit -> rollback ---
  Invoke-KilledTxn "PIE_TXN_KILL_BEFORE_COMMIT"
  $d1 = TxnDir
  if($null -eq $d1){ Die "no txn dir left after kill-before-commit" }
  if(Test-Path -LiteralPath (Join-Path $d1.FullName "COMMIT") -PathType Leaf){ Die "COMMIT marker present but kill was before commit" }
  if((ReadT $tA) -ne "ORIG_A`n" -or (ReadT $tB) -ne "ORIG_B`n"){ Die "targets changed before recovery (pre-commit crash must not apply)" }
  $r1 = PIE_TxnRecover $base
  if($r1.rolled_back -lt 1){ Die "recovery did not roll back the pre-commit crash" }
  if((ReadT $tA) -ne "ORIG_A`n" -or (ReadT $tB) -ne "ORIG_B`n"){ Die "rollback changed targets" }
  if($null -ne (TxnDir)){ Die "rolled-back txn dir not removed" }
  Write-Host "  scenario1_kill_before_commit_rollback: OK" -ForegroundColor Green

  # --- Scenario 2: kill AFTER commit -> roll forward ---
  Invoke-KilledTxn "PIE_TXN_KILL_AFTER_COMMIT"
  $d2 = TxnDir
  if($null -eq $d2){ Die "no txn dir left after kill-after-commit" }
  if(-not (Test-Path -LiteralPath (Join-Path $d2.FullName "COMMIT") -PathType Leaf)){ Die "COMMIT marker missing but kill was after commit" }
  $r2 = PIE_TxnRecover $base
  if($r2.recovered -lt 1){ Die "recovery did not roll forward the post-commit crash" }
  if((ReadT $tA) -ne "KILLTEST_A`n"){ Die "roll-forward target A wrong" }
  if((ReadT $tB) -ne "KILLTEST_B`n"){ Die "roll-forward target B wrong" }
  if($null -ne (TxnDir)){ Die "rolled-forward txn dir not removed" }
  Write-Host "  scenario2_kill_after_commit_rollforward: OK" -ForegroundColor Green

  $rcptDir = Join-Path $RepoRoot "runs\kill_injection_selftest"
  if(-not (Test-Path -LiteralPath $rcptDir -PathType Container)){ New-Item -ItemType Directory -Path $rcptDir -Force | Out-Null }
  $stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss_fff")
  $receipt = [ordered]@{ schema="pie.kill.injection.selftest.receipt.v1"; generated_utc=(Get-Date).ToUniversalTime().ToString("o"); scenarios=2; green=$true }
  [System.IO.File]::WriteAllText((Join-Path $rcptDir ($stamp + ".json")), ($receipt | ConvertTo-Json -Depth 5), $enc)
}
finally {
  if(Test-Path -LiteralPath $base -PathType Container){ Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host "SELFTEST_PIE_KILL_INJECTION_V1_GREEN" -ForegroundColor Green
