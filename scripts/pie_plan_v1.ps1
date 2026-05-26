param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$SessionId,
  [Parameter(Mandatory=$true)][string]$Goal
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)
$PlanRoot = Join-Path $RunRoot "plans"
$QueuePath = Join-Path $RunRoot "execution_queue.ndjson"
$Enc = New-Object System.Text.UTF8Encoding($false)

function Write-Utf8NoBomLf {
  param([string]$Path,[string]$Text)
  $Dir = Split-Path -Parent $Path
  if(-not (Test-Path -LiteralPath $Dir -PathType Container)){ New-Item -ItemType Directory -Force -Path $Dir | Out-Null }
  $Clean = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $Clean.EndsWith("`n")){ $Clean += "`n" }
  [System.IO.File]::WriteAllText($Path,$Clean,$Enc)
}

if(-not (Test-Path -LiteralPath $RunRoot -PathType Container)){
  throw ("PIE_PLAN_SESSION_NOT_FOUND: " + $SessionId)
}

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
$PlanId = "plan_" + $Stamp
$PlanFile = Join-Path $PlanRoot ($PlanId + ".json")

$Steps = @(
  [ordered]@{
    step_id = "01_resolve_memory"
    kind = "memory"
    description = "Resolve current session, repo, rank, execution receipts, and recent conversation context."
    command = ""
    requires_confirmation = $false
    status = "pending"
  },
  [ordered]@{
    step_id = "02_build_context"
    kind = "context"
    description = "Build governed context packet for the goal."
    command = ""
    requires_confirmation = $false
    status = "pending"
  },
  [ordered]@{
    step_id = "03_policy_review"
    kind = "policy"
    description = "Classify any proposed executable commands before running them."
    command = ""
    requires_confirmation = $false
    status = "pending"
  },
  [ordered]@{
    step_id = "04_operator_confirm"
    kind = "approval"
    description = "Require explicit confirmation for any mutation, sync, script, or unknown action."
    command = ""
    requires_confirmation = $true
    status = "pending"
  },
  [ordered]@{
    step_id = "05_execute_receipted"
    kind = "execution"
    description = "Execute only policy-approved commands and write stdout/stderr/receipt artifacts."
    command = ""
    requires_confirmation = $true
    status = "pending"
  },
  [ordered]@{
    step_id = "06_memory_writeback"
    kind = "memory"
    description = "Append successful results and receipts into memory resolution inputs."
    command = ""
    requires_confirmation = $false
    status = "pending"
  }
)

$Plan = [ordered]@{
  schema = "pie.plan.v1"
  plan_id = $PlanId
  session_id = $SessionId
  goal = $Goal
  status = "planned"
  steps = $Steps
  created_utc = [DateTime]::UtcNow.ToString("o")
}

Write-Utf8NoBomLf -Path $PlanFile -Text ($Plan | ConvertTo-Json -Depth 20)

foreach($Step in $Steps){
  $QueueItem = [ordered]@{
    schema = "pie.execution.queue_item.v1"
    plan_id = $PlanId
    session_id = $SessionId
    step_id = $Step.step_id
    kind = $Step.kind
    description = $Step.description
    command = $Step.command
    requires_confirmation = $Step.requires_confirmation
    status = "queued"
    created_utc = [DateTime]::UtcNow.ToString("o")
  }

  [System.IO.File]::AppendAllText($QueuePath,(($QueueItem | ConvertTo-Json -Depth 12 -Compress) + "`n"),$Enc)
}

Write-Host ("PIE_PLAN_OK: " + $PlanFile) -ForegroundColor Green
Write-Host ("queue: " + $QueuePath)
