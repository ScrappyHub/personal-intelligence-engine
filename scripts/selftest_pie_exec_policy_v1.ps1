param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Eval = Join-Path $RepoRoot "scripts\pie_exec_policy_v1.ps1"

function Eval-Policy {
  param([string]$Command)

  $Json = @(
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
      -File $Eval `
      -RepoRoot $RepoRoot `
      -Command $Command `
      -WorkingDirectory $RepoRoot
  ) -join "`n"

  if($LASTEXITCODE -ne 0){
    throw ("POLICY_EVAL_CHILD_FAIL: " + $Command)
  }

  return ($Json | ConvertFrom-Json)
}

$A = Eval-Policy -Command "git status"
if($A.decision -ne "ALLOW"){ throw "POLICY_EXPECT_ALLOW_GIT_STATUS" }

$B = Eval-Policy -Command "git add pie.ps1"
if($B.decision -ne "ASK_CONFIRMATION"){ throw "POLICY_EXPECT_ASK_GIT_ADD" }

$C = Eval-Policy -Command "Remove-Item C:\dev\pie -Recurse -Force"
if($C.decision -ne "DENY"){ throw "POLICY_EXPECT_DENY_REMOVE_RECURSE_FORCE" }

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\selftest_pie_exec_v1.ps1") `
  -RepoRoot $RepoRoot | Out-Host

if($LASTEXITCODE -ne 0){
  throw "POLICY_EXEC_SELFTEST_CHILD_FAIL"
}

Write-Host "PIE_EXEC_POLICY_SELFTEST_OK" -ForegroundColor Green
