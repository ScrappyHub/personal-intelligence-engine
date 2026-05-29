param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$SessionId = "pie_reason_trace_selftest"
$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)
$Enc = New-Object System.Text.UTF8Encoding($false)

function Write-Utf8NoBomLf {
  param([string]$Path,[string]$Text)
  $Dir = Split-Path -Parent $Path
  if(-not (Test-Path -LiteralPath $Dir -PathType Container)){ New-Item -ItemType Directory -Force -Path $Dir | Out-Null }
  $Clean = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $Clean.EndsWith("`n")){ $Clean += "`n" }
  [System.IO.File]::WriteAllText($Path,$Clean,$Enc)
}

if(Test-Path -LiteralPath $RunRoot -PathType Container){
  Remove-Item -LiteralPath $RunRoot -Recurse -Force
}

New-Item -ItemType Directory -Force -Path $RunRoot | Out-Null
Write-Utf8NoBomLf -Path (Join-Path $RunRoot "project_repo.txt") -Text $RepoRoot
Write-Utf8NoBomLf -Path (Join-Path $RunRoot "goal.txt") -Text "reason trace selftest"

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_reason_trace_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -Goal "Prove reasoning trace lane." `
  -SelectedCommand "git status" `
  -WorkingDirectory $RepoRoot | Out-Host

if($LASTEXITCODE -ne 0){
  throw "PIE_REASON_TRACE_CHILD_FAIL"
}

$Latest = Join-Path $RunRoot "reason_traces\latest_reason_trace.json"
if(-not (Test-Path -LiteralPath $Latest -PathType Leaf)){
  throw "PIE_REASON_TRACE_LATEST_MISSING"
}

$Trace = Get-Content -LiteralPath $Latest -Raw | ConvertFrom-Json

if($Trace.schema -ne "pie.reason.trace.v1"){
  throw "PIE_REASON_TRACE_SCHEMA_BAD"
}

if($Trace.policy_result.decision -ne "ALLOW"){
  throw "PIE_REASON_TRACE_EXPECT_POLICY_ALLOW"
}

if($Trace.selected_action.action_id -ne "execute_selected_command"){
  throw "PIE_REASON_TRACE_SELECTED_ACTION_BAD"
}

if(@($Trace.constraints).Count -lt 3){
  throw "PIE_REASON_TRACE_CONSTRAINTS_TOO_FEW"
}

Write-Host "PIE_REASON_TRACE_SELFTEST_OK" -ForegroundColor Green
