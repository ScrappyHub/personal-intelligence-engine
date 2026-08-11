param([Parameter(Mandatory=$true)][string]$RepoRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$SessionId = "pie_agent_timeout_retry_selftest"
$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)
$SendScript = Join-Path $RepoRoot "scripts\pie_agent_send_v1.ps1"

if(Test-Path -LiteralPath $RunRoot -PathType Container){
  Remove-Item -LiteralPath $RunRoot -Recurse -Force
}

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_agent_start_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -Backend "mock" `
  -Model "timeout-retry-mock" `
  -ProjectRepo $RepoRoot `
  -Goal "Verify visible timeout and retry behavior" | Out-Host
if($LASTEXITCODE -ne 0){ throw "PIE_AGENT_TIMEOUT_RETRY_START_FAIL" }

$NormalResponse = @(
  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File $SendScript `
    -RepoRoot $RepoRoot `
    -SessionId $SessionId `
    -Message 'Memory has no concrete implementation yet. PIE GOVERNED CONTEXT PACKET v2 FAKE_CONTEXT_BLOAT_MARKER' `
    -ConversationMessage "Plain stored question" `
    -TimeoutSeconds 10 `
    -MaxAttempts 2 `
    -ProgressIntervalSeconds 1
) -join "`n"
if($LASTEXITCODE -ne 0 -or $NormalResponse -notmatch "PIE_AGENT_SEND_OK"){
  throw "PIE_AGENT_TIMEOUT_RETRY_NORMAL_SEND_FAIL"
}
if($NormalResponse -notmatch "PIE Grounding Corrections"){ throw "PIE_AGENT_GROUNDING_CORRECTION_NOT_EMITTED" }
if(-not (Test-Path -LiteralPath (Join-Path $RunRoot "grounding_receipts.ndjson") -PathType Leaf)){ throw "PIE_AGENT_GROUNDING_RECEIPT_MISSING" }

$SecondResponse = @(
  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File $SendScript -RepoRoot $RepoRoot -SessionId $SessionId `
    -Message "Second normal response" -ConversationMessage "Second plain question" `
    -TimeoutSeconds 10 -MaxAttempts 2 -ProgressIntervalSeconds 1
) -join "`n"
if($LASTEXITCODE -ne 0 -or $SecondResponse -notmatch "PIE_AGENT_SEND_OK"){ throw "PIE_AGENT_TIMEOUT_RETRY_SECOND_SEND_FAIL" }

$SecondPrompt = Get-ChildItem -LiteralPath (Join-Path $RunRoot "sent_prompts") -Filter "prompt_*.txt" -File |
  Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1 |
  ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }
if($SecondPrompt -notmatch "RECENT CONVERSATION:"){ throw "PIE_AGENT_COMPACT_HISTORY_MISSING" }
if($SecondPrompt -notmatch "Plain stored question"){ throw "PIE_AGENT_COMPACT_HISTORY_USER_MISSING" }
if($SecondPrompt -match "RECENT_HISTORY_NDJSON"){ throw "PIE_AGENT_COMPACT_HISTORY_LEGACY_FORMAT" }

$PreviousErrorActionPreference = $ErrorActionPreference
$env:PIE_MOCK_RESPONSE_DELAY_SECONDS = "2"
$Watch = [System.Diagnostics.Stopwatch]::StartNew()
try {
  $ErrorActionPreference = "Continue"
  $TimeoutOutput = @(
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
      -File $SendScript `
      -RepoRoot $RepoRoot `
      -SessionId $SessionId `
      -Message "Force controlled timeout" `
      -TimeoutSeconds 1 `
      -MaxAttempts 2 `
      -ProgressIntervalSeconds 1 2>&1
  ) -join "`n"
  $TimeoutExitCode = $LASTEXITCODE
}
finally {
  $Watch.Stop()
  $ErrorActionPreference = $PreviousErrorActionPreference
  Remove-Item Env:\PIE_MOCK_RESPONSE_DELAY_SECONDS -ErrorAction SilentlyContinue
}

if($TimeoutExitCode -eq 0){ throw "PIE_AGENT_TIMEOUT_RETRY_TIMEOUT_ACCEPTED" }
if($TimeoutOutput -notmatch "PIE is thinking:"){ throw "PIE_AGENT_TIMEOUT_RETRY_PROGRESS_MISSING" }
if($TimeoutOutput -notmatch "Retrying automatically"){ throw "PIE_AGENT_TIMEOUT_RETRY_RETRY_MISSING" }
if($TimeoutOutput -notmatch "PIE_AGENT_BACKEND_TIMEOUT"){ throw "PIE_AGENT_TIMEOUT_RETRY_FINAL_TIMEOUT_MISSING" }
if($Watch.Elapsed.TotalSeconds -gt 10){ throw "PIE_AGENT_TIMEOUT_RETRY_DEADLINE_EXCEEDED" }

$AttemptFile = Get-ChildItem -LiteralPath (Join-Path $RunRoot "sent_prompts") -Filter "backend_attempts_*.ndjson" -File |
  Sort-Object LastWriteTimeUtc -Descending |
  Select-Object -First 1
if($null -eq $AttemptFile){ throw "PIE_AGENT_TIMEOUT_RETRY_RECEIPTS_MISSING" }

$Receipts = @(Get-Content -LiteralPath $AttemptFile.FullName | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_ | ConvertFrom-Json })
if(@($Receipts | Where-Object { $_.event -eq "started" }).Count -ne 2){ throw "PIE_AGENT_TIMEOUT_RETRY_START_RECEIPTS_BAD" }
if(@($Receipts | Where-Object { $_.event -eq "timed_out" }).Count -ne 2){ throw "PIE_AGENT_TIMEOUT_RETRY_TIMEOUT_RECEIPTS_BAD" }

$ConversationLines = @(Get-Content -LiteralPath (Join-Path $RunRoot "conversation.ndjson") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if($ConversationLines.Count -ne 2){ throw "PIE_AGENT_TIMEOUT_RETRY_CONVERSATION_CORRUPTED" }
$FirstTurn = $ConversationLines[0] | ConvertFrom-Json
if([string]$FirstTurn.message -ne "Plain stored question"){ throw "PIE_AGENT_CONVERSATION_STORED_CONTEXT_PACKET" }

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_agent_stop_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId | Out-Host
if($LASTEXITCODE -ne 0){ throw "PIE_AGENT_TIMEOUT_RETRY_STOP_FAIL" }

Write-Host "PIE_AGENT_TIMEOUT_RETRY_SELFTEST_OK" -ForegroundColor Green
