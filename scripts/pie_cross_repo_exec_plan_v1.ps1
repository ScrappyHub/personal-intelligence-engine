param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$SessionId,
  [Parameter(Mandatory=$true)][string]$SourceRepo,
  [Parameter(Mandatory=$true)][string]$Goal,
  [Parameter(Mandatory=$false)][string]$Relation = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$SourceRepo = (Resolve-Path -LiteralPath $SourceRepo).Path

$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)
$OutRoot = Join-Path $RunRoot "cross_repo_exec_plans"
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

New-Item -ItemType Directory -Force -Path $RunRoot | Out-Null
Write-Utf8NoBomLf -Path (Join-Path $RunRoot "project_repo.txt") -Text $SourceRepo
Write-Utf8NoBomLf -Path (Join-Path $RunRoot "goal.txt") -Text $Goal

# Build or refresh cross-repo route first.
$RouteArgs = @(
  "-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass",
  "-File",(Join-Path $RepoRoot "scripts\pie_cross_repo_route_v1.ps1"),
  "-RepoRoot",$RepoRoot,
  "-SessionId",$SessionId,
  "-SourceRepo",$SourceRepo,
  "-Goal",$Goal
)

if(-not [string]::IsNullOrWhiteSpace($Relation)){
  $RouteArgs += "-Relation"
  $RouteArgs += $Relation
}

& powershell.exe @RouteArgs | Out-Host

if($LASTEXITCODE -ne 0){
  throw "PIE_CROSS_REPO_EXEC_PLAN_ROUTE_FAIL"
}

$RoutePath = Join-Path $RunRoot "cross_repo_routes\latest_cross_repo_route.json"

if(-not (Test-Path -LiteralPath $RoutePath -PathType Leaf)){
  throw "PIE_CROSS_REPO_EXEC_PLAN_ROUTE_MISSING"
}

$Route = Get-Content -LiteralPath $RoutePath -Raw | ConvertFrom-Json

$RepoPlans = New-Object System.Collections.Generic.List[object]

foreach($RepoItem in @($Route.repos)){
  $TargetRepo = [string]$RepoItem.repo

  if([string]::IsNullOrWhiteSpace($TargetRepo)){
    continue
  }

  if(-not (Test-Path -LiteralPath $TargetRepo -PathType Container)){
    continue
  }

  $TemplateJson = @(
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
      -File (Join-Path $RepoRoot "scripts\pie_repo_template_query_v1.ps1") `
      -RepoRoot $RepoRoot `
      -TargetRepo $TargetRepo
  ) -join "`n"

  if($LASTEXITCODE -ne 0){
    throw ("PIE_CROSS_REPO_EXEC_PLAN_TEMPLATE_QUERY_FAIL: " + $TargetRepo)
  }

  $TemplateQuery = $TemplateJson | ConvertFrom-Json

  $Mode = "default"
  $TemplateId = ""
  $Sequence = @("repo.status","repo.diff")
  $Reason = "NO_TEMPLATE_DEFAULT_REPO_HEALTH"

  if([int]$TemplateQuery.count -gt 0){
    $T = @($TemplateQuery.results) |
      Sort-Object @{ Expression = "created_utc"; Descending = $true }, @{ Expression = "template_id"; Descending = $false } |
      Select-Object -First 1

    if($null -ne $T){
      $Mode = "repo_template"
      $TemplateId = [string]$T.template_id
      $Sequence = @($T.sequence)
      $Reason = "REPO_TEMPLATE_SELECTED"
    }
  }

  [void]$RepoPlans.Add([pscustomobject][ordered]@{
    repo_role = [string]$RepoItem.role
    repo = $TargetRepo
    repo_name = [string]$RepoItem.repo_name
    relation = [string]$RepoItem.relation
    mode = $Mode
    selected_template_id = $TemplateId
    reason_code = $Reason
    sequence = $Sequence
    execution_allowed = $false
    requires_user_confirmation = $true
  })
}

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
$OutPath = Join-Path $OutRoot ("cross_repo_exec_plan_" + $Stamp + ".json")
$LatestPath = Join-Path $OutRoot "latest_cross_repo_exec_plan.json"

$Plan = [ordered]@{
  schema = "pie.cross.repo.exec.plan.v1"
  session_id = $SessionId
  goal = $Goal
  source_repo = $SourceRepo
  cross_repo_route = $RoutePath
  repo_plan_count = @($RepoPlans.ToArray()).Count
  repo_plans = $RepoPlans.ToArray()
  execution_allowed = $false
  requires_user_confirmation = $true
  note = "Cross-repo execution plan only. No execution performed by this script."
  created_utc = [DateTime]::UtcNow.ToString("o")
}

$Json = $Plan | ConvertTo-Json -Depth 60
Write-Utf8NoBomLf -Path $OutPath -Text $Json
Write-Utf8NoBomLf -Path $LatestPath -Text $Json

Write-Host ("PIE_CROSS_REPO_EXEC_PLAN_OK: " + $OutPath) -ForegroundColor Green
Write-Host ("repo_plan_count: " + [string]@($RepoPlans.ToArray()).Count)
Write-Host "NO_EXECUTION_PERFORMED"
