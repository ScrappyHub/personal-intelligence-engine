param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$SessionId,
  [Parameter(Mandatory=$true)][string]$PlanPath,
  [Parameter(Mandatory=$false)][switch]$Confirm
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$PlanPath = (Resolve-Path -LiteralPath $PlanPath).Path

$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)
$OutRoot = Join-Path $RunRoot "cross_repo_execution"
$ReceiptPath = Join-Path $OutRoot "cross_repo_execution_receipts.ndjson"
$Enc = New-Object System.Text.UTF8Encoding($false)

function Write-Utf8NoBomLf {
  param(
    [Parameter(Mandatory=$true)][string]$Path,
    [Parameter(Mandatory=$true)][AllowEmptyString()][string]$Text
  )

  $Dir = Split-Path -Parent $Path
  if(-not (Test-Path -LiteralPath $Dir -PathType Container)){
    New-Item -ItemType Directory -Force -Path $Dir | Out-Null
  }

  $Clean = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $Clean.EndsWith("`n")){ $Clean += "`n" }

  [System.IO.File]::WriteAllText($Path,$Clean,$Enc)
}

function Append-Receipt {
  param([object]$Obj)
  [System.IO.File]::AppendAllText($ReceiptPath,(($Obj | ConvertTo-Json -Depth 40 -Compress) + "`n"),$Enc)
}

function Resolve-CapabilityCommand {
  param([string]$CapabilityId)

  if($CapabilityId -eq "repo.status"){
    return "git status"
  }

  if($CapabilityId -eq "repo.diff"){
    return "git diff"
  }

  throw ("PIE_CROSS_REPO_EXEC_UNKNOWN_CAPABILITY: " + $CapabilityId)
}

New-Item -ItemType Directory -Force -Path $OutRoot | Out-Null

$Plan = Get-Content -LiteralPath $PlanPath -Raw | ConvertFrom-Json

if($Plan.schema -ne "pie.cross.repo.exec.plan.v1"){
  throw "PIE_CROSS_REPO_EXEC_PLAN_SCHEMA_BAD"
}

$ProposalPath = Join-Path $OutRoot "latest_cross_repo_execution_proposal.json"

$Proposal = [ordered]@{
  schema = "pie.cross.repo.execution.proposal.v1"
  session_id = $SessionId
  plan = $PlanPath
  repo_plan_count = [int]$Plan.repo_plan_count
  requires_confirm = $true
  confirm = [bool]$Confirm
  execution_allowed = [bool]$Confirm
  created_utc = [DateTime]::UtcNow.ToString("o")
}

Write-Utf8NoBomLf -Path $ProposalPath -Text ($Proposal | ConvertTo-Json -Depth 30)

Write-Host ("PIE_CROSS_REPO_EXEC_PROPOSAL_OK: " + $ProposalPath) -ForegroundColor Green

if(-not $Confirm){
  Write-Host "NO_EXECUTION_PERFORMED"
  Write-Host "Re-run with -Confirm to execute."
  exit 0
}

$StepCount = 0

foreach($RepoPlan in @($Plan.repo_plans)){
  $TargetRepo = [string]$RepoPlan.repo

  if([string]::IsNullOrWhiteSpace($TargetRepo)){
    continue
  }

  if(-not (Test-Path -LiteralPath $TargetRepo -PathType Container)){
    throw ("PIE_CROSS_REPO_EXEC_TARGET_REPO_MISSING: " + $TargetRepo)
  }

  foreach($CapabilityId in @($RepoPlan.sequence)){
    $CapabilityId = [string]$CapabilityId
    if([string]::IsNullOrWhiteSpace($CapabilityId)){ continue }

    $Command = Resolve-CapabilityCommand -CapabilityId $CapabilityId

    $ChildSession = $SessionId + "_xrepo_" + ([string]$StepCount)
    $ChildRunRoot = Join-Path $RepoRoot ("runs\" + $ChildSession)
    New-Item -ItemType Directory -Force -Path $ChildRunRoot | Out-Null

    Write-Utf8NoBomLf -Path (Join-Path $ChildRunRoot "project_repo.txt") -Text $TargetRepo
    Write-Utf8NoBomLf -Path (Join-Path $ChildRunRoot "goal.txt") -Text ([string]$Plan.goal)

    Write-Host ("PIE_CROSS_REPO_EXEC_STEP_START: " + $CapabilityId + " :: " + $TargetRepo) -ForegroundColor Cyan

    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
      -File (Join-Path $RepoRoot "scripts\pie_exec_with_snapshot_v1.ps1") `
      -RepoRoot $RepoRoot `
      -SessionId $ChildSession `
      -WorkingDirectory $TargetRepo `
      -Command $Command `
      -Confirm | Out-Host

    if($LASTEXITCODE -ne 0){
      throw ("PIE_CROSS_REPO_EXEC_STEP_FAIL: " + $CapabilityId + " :: " + $TargetRepo)
    }

    $Receipt = [ordered]@{
      schema = "pie.cross.repo.execution.receipt.v1"
      session_id = $SessionId
      child_session_id = $ChildSession
      repo = $TargetRepo
      capability_id = $CapabilityId
      command = $Command
      status = "ok"
      created_utc = [DateTime]::UtcNow.ToString("o")
    }

    Append-Receipt -Obj $Receipt

    Write-Host ("PIE_CROSS_REPO_EXEC_STEP_OK: " + $CapabilityId) -ForegroundColor Green

    $StepCount += 1
  }
}

$SummaryPath = Join-Path $OutRoot "latest_cross_repo_execution_summary.json"

$Summary = [ordered]@{
  schema = "pie.cross.repo.execution.summary.v1"
  session_id = $SessionId
  plan = $PlanPath
  step_count = $StepCount
  receipts = $ReceiptPath
  status = "ok"
  created_utc = [DateTime]::UtcNow.ToString("o")
}

Write-Utf8NoBomLf -Path $SummaryPath -Text ($Summary | ConvertTo-Json -Depth 30)

Write-Host ("PIE_CROSS_REPO_EXECUTE_OK: " + $SummaryPath) -ForegroundColor Green
