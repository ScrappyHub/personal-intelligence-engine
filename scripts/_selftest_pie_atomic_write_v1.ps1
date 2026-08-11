param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Certification for the atomic state-write primitive (release-blocker B2 foundation).
# check1  new-file write produces the full file, no temp residue.
# check2  overwrite replaces content atomically, no temp residue.
# check3  failure (locked target) leaves the ORIGINAL intact, throws a clear token, no temp residue.
# check4  torn NDJSON tail (interrupted append) is detected, not silently accepted.
# Emits SELFTEST_PIE_ATOMIC_WRITE_V1_GREEN on success.

function Die([string]$m){ throw ("SELFTEST_ATOMIC_WRITE_FAIL: " + $m) }

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $RepoRoot "scripts\_lib_pie_atomic_v1.ps1")

$work = Join-Path $RepoRoot ("runs\atomic_selftest_" + ([guid]::NewGuid().ToString('n')))
New-Item -ItemType Directory -Path $work -Force | Out-Null
$enc = New-Object System.Text.UTF8Encoding($false)
function TempResidue { @(Get-ChildItem -LiteralPath $work -Filter ".pie_atomic_*.tmp" -Force -ErrorAction SilentlyContinue).Count }

Write-Host "PIE_ATOMIC_WRITE_SELFTEST_START" -ForegroundColor DarkCyan

try {
  # check1: new file.
  $f1 = Join-Path $work "a.txt"
  PIE_WriteFileAtomic $f1 "hello"
  $c1 = [System.IO.File]::ReadAllText($f1,$enc)
  if($c1 -ne "hello`n"){ Die ("new-file content wrong: " + [System.BitConverter]::ToString([System.Text.Encoding]::UTF8.GetBytes($c1))) }
  if((TempResidue) -ne 0){ Die "temp residue after new-file write" }
  Write-Host "  check1_new_file: OK" -ForegroundColor Green

  # check2: overwrite.
  PIE_WriteFileAtomic $f1 "world"
  $c2 = [System.IO.File]::ReadAllText($f1,$enc)
  if($c2 -ne "world`n"){ Die "overwrite content wrong" }
  if((TempResidue) -ne 0){ Die "temp residue after overwrite" }
  Write-Host "  check2_overwrite: OK" -ForegroundColor Green

  # check3: failure leaves original intact. Lock the target with an exclusive handle so Replace fails.
  $f3 = Join-Path $work "locked.txt"
  PIE_WriteFileAtomic $f3 "ORIGINAL"
  $lock = [System.IO.File]::Open($f3,[System.IO.FileMode]::Open,[System.IO.FileAccess]::ReadWrite,[System.IO.FileShare]::None)
  $threw = $false
  try {
    try { PIE_WriteFileAtomic $f3 "REPLACEMENT" } catch { $threw = $true; if($_.Exception.Message -notmatch 'PIE_ATOMIC_WRITE_FAILED'){ $lock.Dispose(); Die ("wrong error: " + $_.Exception.Message) } }
  }
  finally { $lock.Dispose() }
  if(-not $threw){ Die "locked-target write did not fail closed" }
  $c3 = [System.IO.File]::ReadAllText($f3,$enc)
  if($c3 -ne "ORIGINAL`n"){ Die "original was corrupted on failed write" }
  if((TempResidue) -ne 0){ Die "temp residue after failed write" }
  Write-Host "  check3_failure_preserves_original: OK" -ForegroundColor Green

  # check4: torn NDJSON tail detection.
  $nd = Join-Path $work "ledger.ndjson"
  [System.IO.File]::WriteAllText($nd, "{`"a`":1}`n{`"a`":2}", $enc)   # missing trailing newline == interrupted append
  $r = PIE_ReadNdjsonSafe $nd
  if(-not $r.torn){ Die "torn NDJSON tail not detected" }
  if($r.lines.Count -ne 2){ Die "torn NDJSON line parse wrong" }
  [System.IO.File]::WriteAllText($nd, "{`"a`":1}`n{`"a`":2}`n", $enc)  # clean
  $r2 = PIE_ReadNdjsonSafe $nd
  if($r2.torn){ Die "clean NDJSON falsely reported torn" }
  Write-Host "  check4_torn_tail_detection: OK" -ForegroundColor Green

  # Receipt.
  $rcptDir = Join-Path $RepoRoot "runs\atomic_selftest"
  if(-not (Test-Path -LiteralPath $rcptDir -PathType Container)){ New-Item -ItemType Directory -Path $rcptDir -Force | Out-Null }
  $stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss_fff")
  $receipt = [ordered]@{ schema="pie.atomic.selftest.receipt.v1"; generated_utc=(Get-Date).ToUniversalTime().ToString("o"); checks=4; green=$true }
  [System.IO.File]::WriteAllText((Join-Path $rcptDir ($stamp + ".json")), ($receipt | ConvertTo-Json -Depth 5), $enc)
}
finally {
  if(Test-Path -LiteralPath $work -PathType Container){ Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host "SELFTEST_PIE_ATOMIC_WRITE_V1_GREEN" -ForegroundColor Green
