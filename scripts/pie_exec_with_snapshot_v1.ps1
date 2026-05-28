param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$SessionId,
  [Parameter(Mandatory=$true)][string]$Command,
  [Parameter(Mandatory=$false)][string]$WorkingDirectory = "",
  [Parameter(Mandatory=$false)][switch]$Confirm,
  [Parameter(Mandatory=$false)][switch]$AutoConfirmAllowed
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

function Extract-PathFromToken {
  param(
    [string]$Text,
    [string]$Prefix
  )

  foreach($Line in @($Text -split "`n")){
    if($Line -like ($Prefix + "*")){
      return $Line.Substring($Prefix.Length).Trim()
    }
  }

  return ""
}

$BeforeOut = @(
  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File (Join-Path $RepoRoot "scripts\pie_state_snapshot_v1.ps1") `
    -RepoRoot $RepoRoot `
    -SessionId $SessionId `
    -TargetPath $WorkingDirectory
) -join "`n"

if($LASTEXITCODE -ne 0){ throw "PIE_EXEC_SNAPSHOT_BEFORE_FAIL" }

$BeforeSnapshot = Extract-PathFromToken -Text $BeforeOut -Prefix "PIE_STATE_SNAPSHOT_OK:"

$ExecArgs = @(
  "-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass",
  "-File",(Join-Path $RepoRoot "scripts\pie_exec_v1.ps1"),
  "-RepoRoot",$RepoRoot,
  "-SessionId",$SessionId,
  "-Command",$Command,
  "-WorkingDirectory",$WorkingDirectory
)

if($Confirm){ $ExecArgs += "-Confirm" }
if($AutoConfirmAllowed){ $ExecArgs += "-AutoConfirmAllowed" }

& powershell.exe @ExecArgs | Out-Host

$ExecExit = $LASTEXITCODE

$AfterOut = @(
  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File (Join-Path $RepoRoot "scripts\pie_state_snapshot_v1.ps1") `
    -RepoRoot $RepoRoot `
    -SessionId $SessionId `
    -TargetPath $WorkingDirectory
) -join "`n"

if($LASTEXITCODE -ne 0){ throw "PIE_EXEC_SNAPSHOT_AFTER_FAIL" }

$AfterSnapshot = Extract-PathFromToken -Text $AfterOut -Prefix "PIE_STATE_SNAPSHOT_OK:"

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_state_diff_v1.ps1") `
  -BeforeSnapshot $BeforeSnapshot `
  -AfterSnapshot $AfterSnapshot | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_EXEC_SNAPSHOT_DIFF_FAIL" }

if($ExecExit -ne 0){ exit $ExecExit }

Write-Host "PIE_EXEC_WITH_SNAPSHOT_OK" -ForegroundColor Green
