param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$SessionId = "pie_intent_resume_selftest"
$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)

if(Test-Path -LiteralPath $RunRoot -PathType Container){
  Remove-Item -LiteralPath $RunRoot -Recurse -Force
}

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_intent_record_v1.ps1") `
  -RepoRoot $RepoRoot `
  -Goal "Resume persistent cognition safely" `
  -Status "open" `
  -SessionId $SessionId `
  -Repo $RepoRoot `
  -Notes "resume selftest seed" | Out-Host

if($LASTEXITCODE -ne 0){
  throw "PIE_INTENT_RESUME_RECORD_FAIL"
}

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_intent_resume_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -GoalContains "persistent cognition" | Out-Host

if($LASTEXITCODE -ne 0){
  throw "PIE_INTENT_RESUME_CHILD_FAIL"
}

$Latest = Join-Path $RunRoot "intent_resume\latest_intent_resume.json"

if(-not (Test-Path -LiteralPath $Latest -PathType Leaf)){
  throw "PIE_INTENT_RESUME_LATEST_MISSING"
}

$Obj = Get-Content -LiteralPath $Latest -Raw | ConvertFrom-Json

if($Obj.schema -ne "pie.intent.resume.proposal.v1"){
  throw "PIE_INTENT_RESUME_SCHEMA_BAD"
}

if([bool]$Obj.execution_allowed -ne $false){
  throw "PIE_INTENT_RESUME_EXECUTION_SHOULD_BE_FALSE"
}

if([bool]$Obj.requires_user_confirmation -ne $true){
  throw "PIE_INTENT_RESUME_CONFIRMATION_REQUIRED_BAD"
}

if(-not (@($Obj.selected_sequence) -contains "repo.status")){
  throw "PIE_INTENT_RESUME_SEQUENCE_MISSING_STATUS"
}

Write-Host "PIE_INTENT_RESUME_SELFTEST_OK" -ForegroundColor Green
