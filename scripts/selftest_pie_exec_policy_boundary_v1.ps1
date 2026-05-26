param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$SessionId = "pie_exec_policy_boundary_selftest"
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

New-Item -ItemType Directory -Force -Path $RunRoot | Out-Null
Write-Utf8NoBomLf -Path (Join-Path $RunRoot "project_repo.txt") -Text $RepoRoot

$Eval = Join-Path $RepoRoot "scripts\pie_exec_policy_v1.ps1"
$Exec = Join-Path $RepoRoot "scripts\pie_exec_v1.ps1"

$A = @(
  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File $Eval `
    -RepoRoot $RepoRoot `
    -Command "git status" `
    -WorkingDirectory $RepoRoot `
    -SessionProjectRepo $RepoRoot
) -join "`n"

if($LASTEXITCODE -ne 0){ throw "BOUNDARY_POLICY_EVAL_FAIL" }

$ObjA = $A | ConvertFrom-Json
if($ObjA.decision -ne "ALLOW"){ throw "BOUNDARY_EXPECT_GIT_STATUS_ALLOW" }
if($ObjA.auto_confirm_allowed -ne $true){ throw "BOUNDARY_EXPECT_AUTO_CONFIRM_TRUE" }

$B = @(
  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File $Eval `
    -RepoRoot $RepoRoot `
    -Command "git status" `
    -WorkingDirectory "C:\Windows" `
    -SessionProjectRepo $RepoRoot
) -join "`n"

$ObjB = $B | ConvertFrom-Json
if($ObjB.decision -ne "DENY"){ throw "BOUNDARY_EXPECT_OUTSIDE_REPO_DENY" }

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File $Exec `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -Command "Write-Output PIE_AUTO_EXEC_OK" `
  -AutoConfirmAllowed | Out-Host

if($LASTEXITCODE -ne 0){ throw "BOUNDARY_AUTO_EXEC_FAIL" }

Write-Host "PIE_EXEC_POLICY_BOUNDARY_SELFTEST_OK" -ForegroundColor Green
