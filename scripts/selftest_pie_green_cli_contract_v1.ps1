param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
Set-Location $RepoRoot

$CliPath = Join-Path $RepoRoot "pie.ps1"
$RunRoot = Join-Path $RepoRoot "runs\pie_green_cli_contract_selftest"
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

function Invoke-CommandCapture {
  param(
    [Parameter(Mandatory=$true)][string]$Name,
    [Parameter(Mandatory=$true)][string[]]$Args,
    [switch]$RequireSilent
  )

  $OutPath = Join-Path $CaseRoot ($Name + "_stdout.txt")
  $ErrPath = Join-Path $CaseRoot ($Name + "_stderr.txt")

  Remove-Item -LiteralPath $OutPath -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $ErrPath -Force -ErrorAction SilentlyContinue

  $P = Start-Process -FilePath "powershell.exe" `
    -ArgumentList $Args `
    -Wait `
    -PassThru `
    -WindowStyle Hidden `
    -RedirectStandardOutput $OutPath `
    -RedirectStandardError $ErrPath

  $Stdout = [string]""
  $Stderr = [string]""

  if(Test-Path -LiteralPath $OutPath -PathType Leaf){
    $Stdout = [string](Get-Content -LiteralPath $OutPath -Raw)
  }

  if(Test-Path -LiteralPath $ErrPath -PathType Leaf){
    $Stderr = [string](Get-Content -LiteralPath $ErrPath -Raw)
  }

  if($P.ExitCode -ne 0){
    throw ("PIE_GREEN_CLI_CONTRACT_STEP_FAIL: " + $Name + " exit=" + [string]$P.ExitCode)
  }

  if($RequireSilent){
    if(-not [string]::IsNullOrWhiteSpace($Stdout)){
      throw ("PIE_GREEN_CLI_CONTRACT_STEP_NOT_SILENT_STDOUT: " + $Name)
    }
    if(-not [string]::IsNullOrWhiteSpace($Stderr)){
      throw ("PIE_GREEN_CLI_CONTRACT_STEP_NOT_SILENT_STDERR: " + $Name)
    }
  }

  return [ordered]@{
    name = $Name
    exit_code = [int]$P.ExitCode
    stdout_path = $OutPath
    stderr_path = $ErrPath
    stdout_chars = $Stdout.Length
    stderr_chars = $Stderr.Length
    silent_required = [bool]$RequireSilent
  }
}

New-Item -ItemType Directory -Force -Path $CaseRoot | Out-Null

$Common = @(
  "-NoProfile",
  "-NonInteractive",
  "-ExecutionPolicy",
  "Bypass",
  "-File",
  $CliPath,
  "green"
)

$Results = @(
  [pscustomobject](Invoke-CommandCapture -Name "status" -Args ($Common + @("status")))
  [pscustomobject](Invoke-CommandCapture -Name "list" -Args ($Common + @("list")))
  [pscustomobject](Invoke-CommandCapture -Name "manifest" -Args ($Common + @("manifest")))
  [pscustomobject](Invoke-CommandCapture -Name "evidence" -Args ($Common + @("evidence")))
  [pscustomobject](Invoke-CommandCapture -Name "audit" -Args ($Common + @("audit")) -RequireSilent)
)

$AuditRoot = Join-Path $RepoRoot "runs\green_audit"
$LatestAudit = $null
if(Test-Path -LiteralPath $AuditRoot -PathType Container){
  $LatestAudit = Get-ChildItem -LiteralPath $AuditRoot -File -Filter "green_audit_*.json" |
    Sort-Object Name -Descending |
    Select-Object -First 1
}

if($null -eq $LatestAudit){
  throw "PIE_GREEN_CLI_CONTRACT_AUDIT_RECEIPT_MISSING"
}

$Audit = Get-Content -LiteralPath $LatestAudit.FullName -Raw | ConvertFrom-Json

if([string]$Audit.status -ne "ok"){
  throw ("PIE_GREEN_CLI_CONTRACT_AUDIT_STATUS_BAD: " + [string]$Audit.status)
}

if([int]$Audit.finding_count -ne 0){
  throw ("PIE_GREEN_CLI_CONTRACT_AUDIT_FINDINGS_BAD: " + [string]$Audit.finding_count)
}

$TrackedStatus = @(git -C $RepoRoot status --short --untracked-files=no)
if(@($TrackedStatus).Count -gt 0){
  throw ("PIE_GREEN_CLI_CONTRACT_TRACKED_DIRTY: " + ($TrackedStatus -join " | "))
}

$Summary = [ordered]@{
  schema = "pie.green.cli.contract.selftest.v1"
  created_utc = [DateTime]::UtcNow.ToString("o")
  repo_root = $RepoRoot
  branch = ((git -C $RepoRoot rev-parse --abbrev-ref HEAD) -join "").Trim()
  commit = ((git -C $RepoRoot rev-parse --short HEAD) -join "").Trim()
  latest_audit_receipt = $LatestAudit.FullName
  audit_status = [string]$Audit.status
  audit_finding_count = [int]$Audit.finding_count
  steps = @($Results)
}

$SummaryPath = Join-Path $CaseRoot "pie_green_cli_contract_selftest_summary.json"
$LatestSummaryPath = Join-Path $RunRoot "latest_pie_green_cli_contract_selftest_summary.json"

Write-Utf8NoBomLf -Path $SummaryPath -Text ($Summary | ConvertTo-Json -Depth 50)
Write-Utf8NoBomLf -Path $LatestSummaryPath -Text ($Summary | ConvertTo-Json -Depth 50)

Write-Host "PIE_GREEN_CLI_CONTRACT_SELFTEST_OK" -ForegroundColor Green
Write-Host ("summary: " + $SummaryPath)

