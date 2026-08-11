param([Parameter(Mandatory=$true)][string]$RepoRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Pie = Join-Path $RepoRoot "pie.ps1"
$SessionId = "pie_agent_session_contract_selftest"
$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)
$Snapshots = Join-Path $RunRoot "snapshots"

if(Test-Path -LiteralPath $RunRoot -PathType Container){
  Remove-Item -LiteralPath $RunRoot -Recurse -Force
}

New-Item -ItemType Directory -Force -Path $RunRoot | Out-Null
[System.IO.File]::WriteAllText((Join-Path $RunRoot "orphan.txt"),"incomplete")

$BeforeSnapshots = @(Get-ChildItem -LiteralPath $Snapshots -Directory -ErrorAction SilentlyContinue).Count
$PreviousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = "Continue"
$FailureOutput = @(
  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File $Pie agent exec `
    -RepoRoot $RepoRoot `
    -SessionId $SessionId `
    -Text "git status" 2>&1
) -join "`n"
$FailureExitCode = $LASTEXITCODE
$ErrorActionPreference = $PreviousErrorActionPreference

if($FailureExitCode -eq 0){ throw "PIE_AGENT_SESSION_CONTRACT_INCOMPLETE_ACCEPTED" }
if($FailureOutput -notmatch "PIE_AGENT_SESSION_INCOMPLETE"){ throw "PIE_AGENT_SESSION_CONTRACT_ERROR_NOT_ACTIONABLE" }

$AfterSnapshots = @(Get-ChildItem -LiteralPath $Snapshots -Directory -ErrorAction SilentlyContinue).Count
if($AfterSnapshots -ne $BeforeSnapshots){ throw "PIE_AGENT_SESSION_CONTRACT_INVALID_EXEC_CREATED_SNAPSHOT" }

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File $Pie agent start `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -TargetRepo $RepoRoot `
  -Goal "Verify session repair" `
  -Backend "mock" `
  -Model "session-contract-mock" | Out-Host
if($LASTEXITCODE -ne 0){ throw "PIE_AGENT_SESSION_CONTRACT_REPAIR_FAIL" }

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File $Pie agent status `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId | Out-Host
if($LASTEXITCODE -ne 0){ throw "PIE_AGENT_SESSION_CONTRACT_STATUS_FAIL" }

$BindingRejected = $false
try {
  & (Join-Path $RepoRoot "scripts\pie_agent_start_v1.ps1") -RepoRoot $RepoRoot -SessionId $SessionId -ProjectRepo $RepoRoot -Goal "changed goal" -Backend mock -Model session-contract-mock | Out-Null
}
catch { if($_.Exception.Message -like "PIE_AGENT_SESSION_BINDING_MISMATCH:*"){ $BindingRejected = $true } }
if(-not $BindingRejected){ throw "PIE_AGENT_SESSION_CONTRACT_REBIND_ALLOWED" }

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File $Pie agent stop `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId | Out-Host
if($LASTEXITCODE -ne 0){ throw "PIE_AGENT_SESSION_CONTRACT_STOP_FAIL" }

$ErrorActionPreference = "Continue"
$StoppedOutput = @(
  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File $Pie agent exec `
    -RepoRoot $RepoRoot `
    -SessionId $SessionId `
    -Text "git status" 2>&1
) -join "`n"
$StoppedExitCode = $LASTEXITCODE
$ErrorActionPreference = $PreviousErrorActionPreference

if($StoppedExitCode -eq 0){ throw "PIE_AGENT_SESSION_CONTRACT_STOPPED_ACCEPTED" }
if($StoppedOutput -notmatch "PIE_AGENT_SESSION_NOT_RUNNING"){ throw "PIE_AGENT_SESSION_CONTRACT_STOPPED_ERROR_BAD" }

Write-Host "PIE_AGENT_SESSION_CONTRACT_SELFTEST_OK" -ForegroundColor Green
