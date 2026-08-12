param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [int]$Sessions = 3,
  [int]$TurnsPerSession = 5,
  [int]$Cycles = 2,
  [int]$FaultEvery = 0,      # 0 = no faults; N = inject a turn-append crash every Nth turn (then recover)
  [switch]$Keep
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

# Restart/soak harness (release-blocker B4 foundation). Drives many conversation turns across
# multiple mock sessions over repeated cycles, re-loading (and optionally crash-recovering) every
# session each cycle, and verifies the conversation chain of every session after each cycle. Zero
# integrity failures across the whole run is required. Parameterized: small defaults = smoke test;
# large -Sessions/-TurnsPerSession/-Cycles = multi-hour soak. Emits PIE_SOAK_V1_GREEN.

function Die([string]$m){ throw ("PIE_SOAK_FAIL: " + $m) }

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $RepoRoot "scripts\_lib_pie_agent_session_v1.ps1")
$enc = New-Object System.Text.UTF8Encoding($false)

$start = Join-Path $RepoRoot "scripts\pie_agent_start_v1.ps1"
$send  = Join-Path $RepoRoot "scripts\pie_agent_send_v1.ps1"
$stop  = Join-Path $RepoRoot "scripts\pie_agent_stop_v1.ps1"

$runId = [guid]::NewGuid().ToString('n').Substring(0,8)
$sids = @(1..$Sessions | ForEach-Object { "soak_" + $runId + "_" + $_ })

$totalTurns = 0; $faults = 0; $recovered = 0; $verifyFailures = 0
$sw = [System.Diagnostics.Stopwatch]::StartNew()

Write-Host ("PIE_SOAK_START sessions=" + $Sessions + " turns=" + $TurnsPerSession + " cycles=" + $Cycles + " faultEvery=" + $FaultEvery) -ForegroundColor DarkCyan

try {
  foreach($sid in $sids){
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $start -RepoRoot $RepoRoot -SessionId $sid -ModelId "selftest-model" -BackendMode "mock" 2>&1 | Out-Null
    if($LASTEXITCODE -ne 0){ Die ("session start failed: " + $sid) }
  }

  for($cycle=1; $cycle -le $Cycles; $cycle++){
    foreach($sid in $sids){
      for($t=1; $t -le $TurnsPerSession; $t++){
        $totalTurns++
        $doFault = ($FaultEvery -gt 0 -and (($totalTurns % $FaultEvery) -eq 0))
        if($doFault){ $env:PIE_FAULT_AFTER_TURN_HISTORY_APPEND = "1" }
        [void](& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $send -RepoRoot $RepoRoot -SessionId $sid -Prompt ("cycle " + $cycle + " turn " + $t) 2>&1 | Out-String)
        $code = $LASTEXITCODE
        if($doFault){
          Remove-Item Env:\PIE_FAULT_AFTER_TURN_HISTORY_APPEND -ErrorAction SilentlyContinue
          if($code -eq 0){ Die ("injected fault did not interrupt turn on " + $sid) }
          $faults++
          try { [void](PIE_GetAgentSession -RepoRoot $RepoRoot -SessionId $sid); $recovered++ }
          catch { $verifyFailures++; Write-Host ("  [recover-fail] " + $sid + " :: " + $_.Exception.Message) -ForegroundColor Red }
        }
        elseif($code -ne 0){ Die ("clean turn failed on " + $sid) }
      }
    }
    # Restart-resilience proxy: re-load + verify every session's chain this cycle.
    foreach($sid in $sids){
      try { [void](PIE_GetAgentSession -RepoRoot $RepoRoot -SessionId $sid) }
      catch { $verifyFailures++; Write-Host ("  [verify-fail] cycle " + $cycle + " " + $sid + " :: " + $_.Exception.Message) -ForegroundColor Red }
    }
    Write-Host ("  cycle " + $cycle + " ok (turns so far=" + $totalTurns + ")") -ForegroundColor Green
  }

  if(-not $Keep){
    foreach($sid in $sids){ & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $stop -RepoRoot $RepoRoot -SessionId $sid 2>&1 | Out-Null }
  }

  $sw.Stop()
  $rcptDir = Join-Path $RepoRoot "runs\soak"
  if(-not (Test-Path -LiteralPath $rcptDir -PathType Container)){ New-Item -ItemType Directory -Path $rcptDir -Force | Out-Null }
  $stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss_fff")
  $receipt = [ordered]@{
    schema="pie.soak.report.v1"; generated_utc=(Get-Date).ToUniversalTime().ToString("o")
    sessions=$Sessions; turns_per_session=$TurnsPerSession; cycles=$Cycles; fault_every=$FaultEvery
    total_turns=$totalTurns; faults_injected=$faults; recovered=$recovered
    verify_failures=$verifyFailures; elapsed_ms=$sw.ElapsedMilliseconds; green=($verifyFailures -eq 0)
  }
  [System.IO.File]::WriteAllText((Join-Path $rcptDir ($stamp + ".json")), ($receipt | ConvertTo-Json -Depth 6), $enc)
  [System.IO.File]::WriteAllText((Join-Path $rcptDir "latest.json"), ($receipt | ConvertTo-Json -Depth 6), $enc)

  Write-Host ("SUMMARY turns=" + $totalTurns + " faults=" + $faults + " recovered=" + $recovered + " verify_failures=" + $verifyFailures + " elapsed_ms=" + $sw.ElapsedMilliseconds) -ForegroundColor Cyan
}
finally {
  if(-not $Keep){
    foreach($sid in $sids){ $rr = Join-Path $RepoRoot ("runs\" + $sid); if(Test-Path -LiteralPath $rr -PathType Container){ Remove-Item -LiteralPath $rr -Recurse -Force -ErrorAction SilentlyContinue } }
  }
}

if($verifyFailures -gt 0){ throw ("PIE_SOAK_V1_FAIL: " + $verifyFailures + " integrity failure(s)") }
Write-Host "PIE_SOAK_V1_GREEN" -ForegroundColor Green
