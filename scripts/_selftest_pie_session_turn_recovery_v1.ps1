param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

# Fault-injection test for the crash-safe conversation turn append (B3 session adoption).
# Simulates a crash AFTER conversation.ndjson is appended but BEFORE transcript.ndjson (the
# PIE_FAULT_AFTER_TURN_HISTORY_APPEND hook), then loads the session and asserts recovery rolls the
# turn forward so both files reconcile and the chain still verifies.
# Emits SELFTEST_PIE_SESSION_TURN_RECOVERY_V1_GREEN.

function Die([string]$m){ throw ("SELFTEST_SESSION_TURN_RECOVERY_FAIL: " + $m) }

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $RepoRoot "scripts\_lib_pie_agent_session_v1.ps1")
$enc = New-Object System.Text.UTF8Encoding($false)

$sid     = "selftest_turnrec_" + ([guid]::NewGuid().ToString('n'))
$RunRoot = Join-Path $RepoRoot ("runs\" + $sid)
$conv    = Join-Path $RunRoot "conversation.ndjson"
$trans   = Join-Path $RunRoot "transcript.ndjson"
$pending = Join-Path $RunRoot "state\pending-turn.json"
$start   = Join-Path $RepoRoot "scripts\pie_agent_start_v1.ps1"
$send    = Join-Path $RepoRoot "scripts\pie_agent_send_v1.ps1"
function CountLines([string]$p){ if(-not (Test-Path -LiteralPath $p -PathType Leaf)){ return 0 } @(@([System.IO.File]::ReadAllLines($p,$enc)) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count }

Write-Host "PIE_SESSION_TURN_RECOVERY_SELFTEST_START" -ForegroundColor DarkCyan

try {
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $start -RepoRoot $RepoRoot -SessionId $sid -ModelId "selftest-model" -BackendMode "mock" 2>&1 | Out-Null
  if($LASTEXITCODE -ne 0){ Die "mock session start failed" }
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $send -RepoRoot $RepoRoot -SessionId $sid -Prompt "clean turn one" 2>&1 | Out-Null
  if($LASTEXITCODE -ne 0){ Die "clean send failed" }

  $convBefore  = CountLines $conv
  $transBefore = CountLines $trans
  if($convBefore -ne $transBefore){ Die "history/transcript desynced before fault" }

  # Faulted turn: crash after history append, before transcript append.
  $env:PIE_FAULT_AFTER_TURN_HISTORY_APPEND = "1"
  [void](& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $send -RepoRoot $RepoRoot -SessionId $sid -Prompt "faulted turn two" 2>&1 | Out-String)
  $faultCode = $LASTEXITCODE
  Remove-Item Env:\PIE_FAULT_AFTER_TURN_HISTORY_APPEND -ErrorAction SilentlyContinue
  if($faultCode -eq 0){ Die "faulted send unexpectedly succeeded" }

  if(-not (Test-Path -LiteralPath $pending -PathType Leaf)){ Die "no pending-turn journal after fault" }
  $convMid  = CountLines $conv
  $transMid = CountLines $trans
  if($convMid -ne ($convBefore + 1)){ Die "history not advanced by faulted turn" }
  if($transMid -ne $transBefore){ Die "transcript advanced (fault should precede transcript append)" }
  Write-Host ("  desync_after_fault: OK (history=" + $convMid + " transcript=" + $transMid + ")") -ForegroundColor Green

  # Load the session -> triggers PIE_RecoverTurnAppend.
  [void](PIE_GetAgentSession -RepoRoot $RepoRoot -SessionId $sid)

  if(Test-Path -LiteralPath $pending -PathType Leaf){ Die "pending-turn journal not cleared after recovery" }
  $convAfter  = CountLines $conv
  $transAfter = CountLines $trans
  if($convAfter -ne $transAfter){ Die "recovery did not reconcile history/transcript" }
  if($transAfter -ne ($transBefore + 1)){ Die "recovery did not roll the faulted turn forward" }
  Write-Host ("  reconciled_after_recovery: OK (both=" + $convAfter + ")") -ForegroundColor Green

  # A second load must not throw (chain intact after recovery).
  [void](PIE_GetAgentSession -RepoRoot $RepoRoot -SessionId $sid)
  Write-Host "  session_loads_after_recovery: OK" -ForegroundColor Green

  $rcptDir = Join-Path $RepoRoot "runs\session_turn_recovery_selftest"
  if(-not (Test-Path -LiteralPath $rcptDir -PathType Container)){ New-Item -ItemType Directory -Path $rcptDir -Force | Out-Null }
  $stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss_fff")
  $receipt = [ordered]@{ schema="pie.session.turn.recovery.selftest.receipt.v1"; generated_utc=(Get-Date).ToUniversalTime().ToString("o"); green=$true }
  [System.IO.File]::WriteAllText((Join-Path $rcptDir ($stamp + ".json")), ($receipt | ConvertTo-Json -Depth 5), $enc)
}
finally {
  if(Test-Path -LiteralPath $RunRoot -PathType Container){ Remove-Item -LiteralPath $RunRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host "SELFTEST_PIE_SESSION_TURN_RECOVERY_V1_GREEN" -ForegroundColor Green
