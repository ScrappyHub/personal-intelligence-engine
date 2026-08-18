param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

# OS-level process-kill injection for the conversation turn write (deepens B3 session adoption from
# simulated throw to a real crash). Runs a live mock `pie agent send`, waits until it is blocked
# between the conversation.ndjson append and the transcript.ndjson append, Stop-Process -Force kills
# it (no finally/cleanup runs), then loads the session and proves PIE_RecoverTurnAppend reconciles
# the two files. Emits SELFTEST_PIE_SESSION_KILL_INJECTION_V1_GREEN.

function Die([string]$m){ throw ("SELFTEST_SESSION_KILL_FAIL: " + $m) }

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $RepoRoot "scripts\_lib_pie_agent_session_v1.ps1")
$enc = New-Object System.Text.UTF8Encoding($false)

$sid     = "selftest_sesskill_" + ([guid]::NewGuid().ToString('n'))
$RunRoot = Join-Path $RepoRoot ("runs\" + $sid)
$conv    = Join-Path $RunRoot "conversation.ndjson"
$trans   = Join-Path $RunRoot "transcript.ndjson"
$pending = Join-Path $RunRoot "state\pending-turn.json"
$sig     = Join-Path $RunRoot "kill_ready.txt"
$start   = Join-Path $RepoRoot "scripts\pie_agent_start_v1.ps1"
$send    = Join-Path $RepoRoot "scripts\pie_agent_send_v1.ps1"
function CountLines([string]$p){ if(-not (Test-Path -LiteralPath $p -PathType Leaf)){ return 0 } @(@([System.IO.File]::ReadAllLines($p,$enc)) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count }

Write-Host "PIE_SESSION_KILL_INJECTION_SELFTEST_START" -ForegroundColor DarkCyan

try {
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $start -RepoRoot $RepoRoot -SessionId $sid -ModelId "selftest-model" -BackendMode "mock" 2>&1 | Out-Null
  if($LASTEXITCODE -ne 0){ Die "mock session start failed" }
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $send -RepoRoot $RepoRoot -SessionId $sid -Prompt "clean turn one" 2>&1 | Out-Null
  if($LASTEXITCODE -ne 0){ Die "clean send failed" }

  $convBefore  = CountLines $conv
  $transBefore = CountLines $trans
  if($convBefore -ne $transBefore){ Die "history/transcript desynced before kill" }

  if(Test-Path -LiteralPath $sig -PathType Leaf){ Remove-Item -LiteralPath $sig -Force }
  $env:PIE_SESSION_KILL_SIGNAL = $sig
  $env:PIE_SESSION_KILL_AFTER_HISTORY_APPEND = "1"
  try {
    $p = Start-Process -FilePath "powershell.exe" -PassThru -WindowStyle Hidden -ArgumentList @(
      "-NoProfile","-ExecutionPolicy","Bypass","-File",$send,"-RepoRoot",$RepoRoot,"-SessionId",$sid,"-Prompt","killed turn two")
    $waitedMs = 0
    while(-not (Test-Path -LiteralPath $sig -PathType Leaf)){
      Start-Sleep -Milliseconds 200; $waitedMs += 200
      if($p.HasExited){ Die "send child exited before reaching the kill window" }
      if($waitedMs -ge 25000){ Die "send child never reached the kill window (timeout)" }
    }
    Stop-Process -Id $p.Id -Force
    [void]$p.WaitForExit(5000)
  }
  finally {
    Remove-Item Env:\PIE_SESSION_KILL_AFTER_HISTORY_APPEND -ErrorAction SilentlyContinue
    Remove-Item Env:\PIE_SESSION_KILL_SIGNAL -ErrorAction SilentlyContinue
  }

  # Desync after the real kill: history advanced, transcript not, pending-turn journal present.
  if(-not (Test-Path -LiteralPath $pending -PathType Leaf)){ Die "no pending-turn journal after kill" }
  $convMid  = CountLines $conv
  $transMid = CountLines $trans
  if($convMid -ne ($convBefore + 1)){ Die "history not advanced by killed turn" }
  if($transMid -ne $transBefore){ Die "transcript advanced (kill should precede transcript append)" }
  Write-Host ("  desync_after_kill: OK (history=" + $convMid + " transcript=" + $transMid + ")") -ForegroundColor Green

  # Load the session -> PIE_RecoverTurnAppend reconciles.
  [void](PIE_GetAgentSession -RepoRoot $RepoRoot -SessionId $sid)
  if(Test-Path -LiteralPath $pending -PathType Leaf){ Die "pending-turn journal not cleared after recovery" }
  $convAfter  = CountLines $conv
  $transAfter = CountLines $trans
  if($convAfter -ne $transAfter){ Die "recovery did not reconcile history/transcript" }
  if($transAfter -ne ($transBefore + 1)){ Die "recovery did not roll the killed turn forward" }
  Write-Host ("  reconciled_after_recovery: OK (both=" + $convAfter + ")") -ForegroundColor Green

  [void](PIE_GetAgentSession -RepoRoot $RepoRoot -SessionId $sid)
  Write-Host "  session_loads_after_recovery: OK" -ForegroundColor Green

  $rcptDir = Join-Path $RepoRoot "runs\session_kill_selftest"
  if(-not (Test-Path -LiteralPath $rcptDir -PathType Container)){ New-Item -ItemType Directory -Path $rcptDir -Force | Out-Null }
  $stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss_fff")
  $receipt = [ordered]@{ schema="pie.session.kill.selftest.receipt.v1"; generated_utc=(Get-Date).ToUniversalTime().ToString("o"); green=$true }
  [System.IO.File]::WriteAllText((Join-Path $rcptDir ($stamp + ".json")), ($receipt | ConvertTo-Json -Depth 5), $enc)
}
finally {
  if(Test-Path -LiteralPath $RunRoot -PathType Container){ Remove-Item -LiteralPath $RunRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host "SELFTEST_PIE_SESSION_KILL_INJECTION_V1_GREEN" -ForegroundColor Green
