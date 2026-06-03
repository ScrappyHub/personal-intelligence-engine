param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$SessionId,
  [Parameter(Mandatory=$true)][string]$TargetRepo,
  [Parameter(Mandatory=$true)][string]$Goal,
  [Parameter(Mandatory=$false)][string]$PurposeContains = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$TargetRepo = (Resolve-Path -LiteralPath $TargetRepo).Path

$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)
$RouteRoot = Join-Path $RunRoot "multi_repo_routes"
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
Write-Utf8NoBomLf -Path (Join-Path $RunRoot "project_repo.txt") -Text $TargetRepo
Write-Utf8NoBomLf -Path (Join-Path $RunRoot "goal.txt") -Text $Goal

$RepoName = Split-Path -Leaf $TargetRepo

$TemplateArgs = @(
  "-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass",
  "-File",(Join-Path $RepoRoot "scripts\pie_repo_template_query_v1.ps1"),
  "-RepoRoot",$RepoRoot,
  "-TargetRepo",$TargetRepo
)

if(-not [string]::IsNullOrWhiteSpace($PurposeContains)){
  $TemplateArgs += "-PurposeContains"
  $TemplateArgs += $PurposeContains
}

$TemplateJson = @(& powershell.exe @TemplateArgs) -join "`n"

if($LASTEXITCODE -ne 0){
  throw "PIE_MULTI_REPO_TEMPLATE_QUERY_FAIL"
}

$TemplateQuery = $TemplateJson | ConvertFrom-Json

$SelectedMode = "fallback_synthesized_plan"
$SelectedTemplateId = ""
$Reason = "NO_REPO_TEMPLATE_FOUND"
$Sequence = @("repo.status","repo.diff")
$PlanPath = ""

if([int]$TemplateQuery.count -gt 0){
  $SelectedTemplate = @($TemplateQuery.results) |
    Sort-Object @{ Expression = "created_utc"; Descending = $true }, @{ Expression = "template_id"; Descending = $false } |
    Select-Object -First 1

  if($null -ne $SelectedTemplate){
    $SelectedMode = "repo_template"
    $SelectedTemplateId = [string]$SelectedTemplate.template_id
    $Reason = "REPO_TEMPLATE_SELECTED"
    $Sequence = @($SelectedTemplate.sequence)
  }
}

if($SelectedMode -eq "fallback_synthesized_plan"){
  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File (Join-Path $RepoRoot "scripts\pie_plan_synthesize_v1.ps1") `
    -RepoRoot $RepoRoot `
    -SessionId $SessionId `
    -Goal $Goal | Out-Host

  if($LASTEXITCODE -ne 0){
    throw "PIE_MULTI_REPO_SYNTH_FAIL"
  }

  $Synth = Join-Path $RunRoot "synthesized_plans\latest_synth_plan.json"
  if(Test-Path -LiteralPath $Synth -PathType Leaf){
    $PlanPath = $Synth
    $Obj = Get-Content -LiteralPath $Synth -Raw | ConvertFrom-Json
    $Sequence = @($Obj.sequence)
    $Reason = "SYNTHESIZED_PLAN_SELECTED"
  }
}

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
$RoutePath = Join-Path $RouteRoot ("multi_repo_route_" + $Stamp + ".json")
$LatestPath = Join-Path $RouteRoot "latest_multi_repo_route.json"

$Route = [ordered]@{
  schema = "pie.multi.repo.route.v1"
  session_id = $SessionId
  goal = $Goal
  target_repo = $TargetRepo
  target_repo_name = $RepoName
  selected_mode = $SelectedMode
  selected_template_id = $SelectedTemplateId
  reason_code = $Reason
  sequence = $Sequence
  synthesized_plan = $PlanPath
  execution_allowed = $false
  requires_user_confirmation = $true
  note = "Routing decision only. No execution performed by this script."
  created_utc = [DateTime]::UtcNow.ToString("o")
}

$Json = $Route | ConvertTo-Json -Depth 30
Write-Utf8NoBomLf -Path $RoutePath -Text $Json
Write-Utf8NoBomLf -Path $LatestPath -Text $Json

Write-Host ("PIE_MULTI_REPO_ROUTE_OK: " + $RoutePath) -ForegroundColor Green
Write-Host ("repo: " + $TargetRepo)
Write-Host ("mode: " + $SelectedMode)
Write-Host ("sequence: " + (@($Sequence) -join " -> "))
Write-Host "NO_EXECUTION_PERFORMED"
