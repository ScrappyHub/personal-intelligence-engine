param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
Set-Location $RepoRoot

$RunRoot = Join-Path $RepoRoot "runs\pie_green_proof_chain_verify"
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

function Invoke-Step {
  param(
    [Parameter(Mandatory=$true)][string]$Name,
    [Parameter(Mandatory=$true)][string]$ScriptPath,
    [Parameter(Mandatory=$true)][string]$SuccessToken
  )

  $StdoutPath = Join-Path $CaseRoot ($Name + "_stdout.txt")
  $StderrPath = Join-Path $CaseRoot ($Name + "_stderr.txt")

  $P = Start-Process -FilePath "powershell.exe" `
    -ArgumentList @(
      "-NoProfile",
      "-NonInteractive",
      "-ExecutionPolicy",
      "Bypass",
      "-File",
      $ScriptPath,
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
    throw ("PIE_GREEN_PROOF_CHAIN_STEP_FAIL: " + $Name + " exit=" + [string]$P.ExitCode)
  }

  if($Stdout -notmatch [regex]::Escape($SuccessToken)){
    throw ("PIE_GREEN_PROOF_CHAIN_STEP_TOKEN_MISSING: " + $Name + " :: " + $SuccessToken)
  }

  if(-not [string]::IsNullOrWhiteSpace($Stderr)){
    throw ("PIE_GREEN_PROOF_CHAIN_STEP_STDERR_NOT_EMPTY: " + $Name)
  }

  return [ordered]@{
    name = $Name
    script = $ScriptPath
    exit_code = [int]$P.ExitCode
    stdout_path = $StdoutPath
    stderr_path = $StderrPath
    stdout_bytes = $(if(Test-Path -LiteralPath $StdoutPath -PathType Leaf){ [int64](Get-Item -LiteralPath $StdoutPath).Length } else { 0 })
    stderr_bytes = $(if(Test-Path -LiteralPath $StderrPath -PathType Leaf){ [int64](Get-Item -LiteralPath $StderrPath).Length } else { 0 })
    success_token = $SuccessToken
  }
}

$Required = @(
  @{ name="verify_green_lock_receipt"; path=(Join-Path $RepoRoot "scripts\verify_pie_green_lock_receipt_v1.ps1"); token="PIE_GREEN_LOCK_RECEIPT_VERIFY_OK" },
  @{ name="selftest_verify_green_lock_receipt"; path=(Join-Path $RepoRoot "scripts\selftest_verify_pie_green_lock_receipt_v1.ps1"); token="PIE_GREEN_LOCK_RECEIPT_VERIFY_SELFTEST_OK" },
  @{ name="verify_green_final_snapshot_v2"; path=(Join-Path $RepoRoot "scripts\verify_pie_green_final_snapshot_v2.ps1"); token="PIE_GREEN_FINAL_SNAPSHOT_V2_VERIFY_OK" },
  @{ name="selftest_verify_green_final_snapshot_v2"; path=(Join-Path $RepoRoot "scripts\selftest_verify_pie_green_final_snapshot_v2.ps1"); token="PIE_GREEN_FINAL_SNAPSHOT_V2_VERIFY_SELFTEST_OK" }
)

foreach($R in $Required){
  if(-not (Test-Path -LiteralPath $R.path -PathType Leaf)){
    throw ("PIE_GREEN_PROOF_CHAIN_REQUIRED_SCRIPT_MISSING: " + $R.path)
  }

  $tok=$null
  $err=$null
  [void][System.Management.Automation.Language.Parser]::ParseFile($R.path,[ref]$tok,[ref]$err)
  if(@($err).Count -gt 0){
    throw ("PIE_GREEN_PROOF_CHAIN_REQUIRED_SCRIPT_PARSE_FAIL: " + $R.path + " :: " + $err[0].ToString())
  }
}

$TrackedBefore = @(git -C $RepoRoot status --short --untracked-files=no)

New-Item -ItemType Directory -Force -Path $CaseRoot | Out-Null

$Steps = @()
foreach($R in $Required){
  $Steps += [pscustomobject](Invoke-Step -Name $R.name -ScriptPath $R.path -SuccessToken $R.token)
}

$TrackedAfter = @(git -C $RepoRoot status --short --untracked-files=no)

$BeforeJoined = ($TrackedBefore -join "`n")
$AfterJoined = ($TrackedAfter -join "`n")

if($BeforeJoined -ne $AfterJoined){
  throw "PIE_GREEN_PROOF_CHAIN_TRACKED_STATE_CHANGED"
}

$Summary = [ordered]@{
  schema = "pie.green.proof.chain.verify.v1"
  created_utc = [DateTime]::UtcNow.ToString("o")
  repo_root = $RepoRoot
  branch = ((git -C $RepoRoot rev-parse --abbrev-ref HEAD) -join "").Trim()
  commit = ((git -C $RepoRoot rev-parse --short HEAD) -join "").Trim()
  tracked_state_unchanged = $true
  step_count = @($Steps).Count
  steps = @($Steps)
}

$SummaryPath = Join-Path $CaseRoot "pie_green_proof_chain_verify_summary.json"
$LatestSummaryPath = Join-Path $RunRoot "latest_pie_green_proof_chain_verify_summary.json"

Write-Utf8NoBomLf -Path $SummaryPath -Text ($Summary | ConvertTo-Json -Depth 50)
Write-Utf8NoBomLf -Path $LatestSummaryPath -Text ($Summary | ConvertTo-Json -Depth 50)

Write-Host "PIE_GREEN_PROOF_CHAIN_VERIFY_OK" -ForegroundColor Green
Write-Host ("summary: " + $SummaryPath)
