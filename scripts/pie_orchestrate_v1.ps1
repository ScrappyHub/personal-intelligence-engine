param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$SessionId,
  [Parameter(Mandatory=$true)][string]$ChainId,
  [Parameter(Mandatory=$false)][switch]$Confirm,
  [Parameter(Mandatory=$false)][switch]$AutoConfirmAllowed
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)
$GraphPath = Join-Path $RepoRoot "policies\PIE_CAPABILITY_GRAPH.v1.json"
$PlanRoot = Join-Path $RunRoot "orchestration"
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

if(-not (Test-Path -LiteralPath $RunRoot -PathType Container)){
  throw ("PIE_ORCH_SESSION_NOT_FOUND: " + $SessionId)
}

if(-not (Test-Path -LiteralPath $GraphPath -PathType Leaf)){
  throw ("PIE_ORCH_GRAPH_MISSING: " + $GraphPath)
}

$Graph = Get-Content -LiteralPath $GraphPath -Raw | ConvertFrom-Json
$Chain = $null

foreach($C in @($Graph.chains)){
  if([string]$C.id -eq $ChainId){
    $Chain = $C
    break
  }
}

if($null -eq $Chain){
  throw ("PIE_ORCH_CHAIN_NOT_FOUND: " + $ChainId)
}

$StepRows = New-Object System.Collections.Generic.List[object]

foreach($StepId in @($Chain.steps)){
  $Node = $null

  foreach($N in @($Graph.nodes)){
    if([string]$N.id -eq [string]$StepId){
      $Node = $N
      break
    }
  }

  if($null -eq $Node){
    throw ("PIE_ORCH_NODE_NOT_FOUND: " + [string]$StepId)
  }

  [void]$StepRows.Add([pscustomobject][ordered]@{
    capability_id = [string]$StepId
    depends_on = @($Node.depends_on)
    produces = @($Node.produces)
    risk = [string]$Node.risk
    status = "planned"
  })
}

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
$PlanPath = Join-Path $PlanRoot ("orchestration_plan_" + $Stamp + ".json")

$Plan = [ordered]@{
  schema = "pie.orchestration.plan.v1"
  session_id = $SessionId
  chain_id = $ChainId
  description = [string]$Chain.description
  steps = $StepRows.ToArray()
  confirm = [bool]$Confirm
  auto_confirm_allowed = [bool]$AutoConfirmAllowed
  created_utc = [DateTime]::UtcNow.ToString("o")
}

Write-Utf8NoBomLf -Path $PlanPath -Text ($Plan | ConvertTo-Json -Depth 30)

Write-Host ("PIE_ORCH_PLAN_OK: " + $PlanPath) -ForegroundColor Green

$CapabilityScript = Join-Path $RepoRoot "scripts\pie_capability_v1.ps1"

foreach($Step in @($StepRows.ToArray())){
  $Args = @(
    "-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass",
    "-File",$CapabilityScript,
    "-RepoRoot",$RepoRoot,
    "-SessionId",$SessionId,
    "-CapabilityId",[string]$Step.capability_id
  )

  if($Confirm){ $Args += "-Confirm" }
  if($AutoConfirmAllowed){ $Args += "-AutoConfirmAllowed" }

  Write-Host ("PIE_ORCH_STEP_START: " + [string]$Step.capability_id) -ForegroundColor Cyan

  & powershell.exe @Args | Out-Host

  if($LASTEXITCODE -ne 0){
    throw ("PIE_ORCH_STEP_FAIL: " + [string]$Step.capability_id)
  }

  Write-Host ("PIE_ORCH_STEP_OK: " + [string]$Step.capability_id) -ForegroundColor Green
}

Write-Host ("PIE_ORCH_OK: " + $ChainId) -ForegroundColor Green
