param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$SessionId = "pie_experience_selftest"
$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)
$ExperienceLog = Join-Path $RepoRoot "memory\experience\experience.ndjson"
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

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_orchestrate_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -ChainId "repo.health.basic" `
  -AutoConfirmAllowed | Out-Host

if($LASTEXITCODE -ne 0){
  throw "PIE_EXPERIENCE_ORCH_FAIL"
}

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_execution_replay_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId | Out-Host

if($LASTEXITCODE -ne 0){
  throw "PIE_EXPERIENCE_REPLAY_FAIL"
}

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_reason_trace_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -Goal "Record successful repo health experience." `
  -SelectedCommand "git status" `
  -WorkingDirectory $RepoRoot | Out-Host

if($LASTEXITCODE -ne 0){
  throw "PIE_EXPERIENCE_REASON_TRACE_FAIL"
}

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_experience_record_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -Goal "Record successful repo health experience." `
  -Outcome "success" `
  -ChainId "repo.health.basic" `
  -Notes "selftest success" | Out-Host

if($LASTEXITCODE -ne 0){
  throw "PIE_EXPERIENCE_RECORD_FAIL"
}

if(-not (Test-Path -LiteralPath $ExperienceLog -PathType Leaf)){
  throw "PIE_EXPERIENCE_LOG_MISSING"
}

$Query = @(
  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File (Join-Path $RepoRoot "scripts\pie_experience_query_v1.ps1") `
    -RepoRoot $RepoRoot `
    -ChainId "repo.health.basic" `
    -Outcome "success"
) -join "`n"

if($LASTEXITCODE -ne 0){
  throw "PIE_EXPERIENCE_QUERY_FAIL"
}

$Obj = $Query | ConvertFrom-Json

if($Obj.count -lt 1){
  throw "PIE_EXPERIENCE_QUERY_EMPTY_BAD"
}

Write-Host "PIE_EXPERIENCE_SELFTEST_OK" -ForegroundColor Green
