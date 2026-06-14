param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
Set-Location $RepoRoot

$VerifierPath = Join-Path $RepoRoot "scripts\verify_pie_green_final_snapshot_v2.ps1"
$RunRoot = Join-Path $RepoRoot "runs\pie_green_final_snapshot_v2_verify_selftest"
$CaseId = Get-Date -Format "yyyyMMdd_HHmmss_fff"
$CaseRoot = Join-Path $RunRoot $CaseId
$Enc = New-Object System.Text.UTF8Encoding($false)

function Write-Utf8NoBomLf {
  param(
    [Parameter(Mandatory=$true)][string]$Path,
    [Parameter(Mandatory=$true)][AllowEmptyString()][string]$Text
  )

  $Dir = Split-Path -Parent $Path
  if($Dir -and -not (Test-Path -LiteralPath $Dir -PathType Container)){
    New-Item -ItemType Directory -Force -Path $Dir | Out-Null
  }

  $Clean = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $Clean.EndsWith("`n")){ $Clean += "`n" }

  [System.IO.File]::WriteAllText($Path,$Clean,$Enc)
}

if(-not (Test-Path -LiteralPath $VerifierPath -PathType Leaf)){
  throw "PIE_GREEN_FINAL_SNAPSHOT_V2_VERIFY_SELFTEST_VERIFIER_MISSING"
}

$tok=$null
$err=$null
[void][System.Management.Automation.Language.Parser]::ParseFile($VerifierPath,[ref]$tok,[ref]$err)
if(@($err).Count -gt 0){
  throw ("PIE_GREEN_FINAL_SNAPSHOT_V2_VERIFY_SELFTEST_VERIFIER_PARSE_FAIL: " + $err[0].ToString())
}

$TrackedBefore = @(git -C $RepoRoot status --short --untracked-files=no)

New-Item -ItemType Directory -Force -Path $CaseRoot | Out-Null

$StdoutPath = Join-Path $CaseRoot "verify_stdout.txt"
$StderrPath = Join-Path $CaseRoot "verify_stderr.txt"

$P = Start-Process -FilePath "powershell.exe" `
  -ArgumentList @(
    "-NoProfile",
    "-NonInteractive",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    $VerifierPath,
    "-RepoRoot",
    $RepoRoot
  ) `
  -Wait `
  -PassThru `
  -WindowStyle Hidden `
  -RedirectStandardOutput $StdoutPath `
  -RedirectStandardError $StderrPath

$Stdout = [string]""
$Stderr = [string]""

if(Test-Path -LiteralPath $StdoutPath -PathType Leaf){
  $Stdout = [System.IO.File]::ReadAllText($StdoutPath,[System.Text.UTF8Encoding]::new($false))
}

if(Test-Path -LiteralPath $StderrPath -PathType Leaf){
  $Stderr = [System.IO.File]::ReadAllText($StderrPath,[System.Text.UTF8Encoding]::new($false))
}

if($P.ExitCode -ne 0){
  throw ("PIE_GREEN_FINAL_SNAPSHOT_V2_VERIFY_SELFTEST_CHILD_FAIL: exit=" + [string]$P.ExitCode)
}

if($Stdout -notmatch 'PIE_GREEN_FINAL_SNAPSHOT_V2_VERIFY_OK'){
  throw "PIE_GREEN_FINAL_SNAPSHOT_V2_VERIFY_SELFTEST_TOKEN_MISSING"
}

if(-not [string]::IsNullOrWhiteSpace($Stderr)){
  throw "PIE_GREEN_FINAL_SNAPSHOT_V2_VERIFY_SELFTEST_STDERR_NOT_EMPTY"
}

$TrackedAfter = @(git -C $RepoRoot status --short --untracked-files=no)

$BeforeJoined = ($TrackedBefore -join "`n")
$AfterJoined = ($TrackedAfter -join "`n")

if($BeforeJoined -ne $AfterJoined){
  throw "PIE_GREEN_FINAL_SNAPSHOT_V2_VERIFY_SELFTEST_TRACKED_STATE_CHANGED"
}

$Summary = [ordered]@{
  schema = "pie.green.final.snapshot.verify.selftest.v1"
  created_utc = [DateTime]::UtcNow.ToString("o")
  repo_root = $RepoRoot
  verifier_path = $VerifierPath
  exit_code = [int]$P.ExitCode
  stdout_path = $StdoutPath
  stderr_path = $StderrPath
  stdout_bytes = $(if(Test-Path -LiteralPath $StdoutPath -PathType Leaf){ [int64](Get-Item -LiteralPath $StdoutPath).Length } else { 0 })
  stderr_bytes = $(if(Test-Path -LiteralPath $StderrPath -PathType Leaf){ [int64](Get-Item -LiteralPath $StderrPath).Length } else { 0 })
  tracked_state_unchanged = $true
}

$SummaryPath = Join-Path $CaseRoot "pie_green_final_snapshot_v2_verify_selftest_summary.json"
$LatestSummaryPath = Join-Path $RunRoot "latest_pie_green_final_snapshot_v2_verify_selftest_summary.json"

Write-Utf8NoBomLf -Path $SummaryPath -Text ($Summary | ConvertTo-Json -Depth 50)
Write-Utf8NoBomLf -Path $LatestSummaryPath -Text ($Summary | ConvertTo-Json -Depth 50)

Write-Host "PIE_GREEN_FINAL_SNAPSHOT_V2_VERIFY_SELFTEST_OK" -ForegroundColor Green
Write-Host ("summary: " + $SummaryPath)
