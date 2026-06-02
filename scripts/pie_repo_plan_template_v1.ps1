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
$OutRoot = Join-Path $RunRoot "repo_template_plans"
$Enc = New-Object System.Text.UTF8Encoding($false)

function Write-Utf8NoBomLf {
  param([string]$Path,[string]$Text)

  $Dir = Split-Path -Parent $Path
  if(-not (Test-Path -LiteralPath $Dir -PathType Container)){
    New-Item -ItemType Directory -Force -Path $Dir | Out-Null
  }

  $Clean = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $Clean.EndsWith("`n")){ $Clean += "`n" }

  [System.IO.File]::WriteAllText($Path,$Clean,$Enc)
}

if(-not (Test-Path -LiteralPath $RunRoot -PathType Container)){
  New-Item -ItemType Directory -Force -Path $RunRoot | Out-Null
}

Write-Utf8NoBomLf -Path (Join-Path $RunRoot "project_repo.txt") -Text $TargetRepo
Write-Utf8NoBomLf -Path (Join-Path $RunRoot "goal.txt") -Text $Goal

$QueryArgs = @(
  "-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass",
  "-File",(Join-Path $RepoRoot "scripts\pie_repo_template_query_v1.ps1"),
  "-RepoRoot",$RepoRoot,
  "-TargetRepo",$TargetRepo
)

if(-not [string]::IsNullOrWhiteSpace($PurposeContains)){
  $QueryArgs += "-PurposeContains"
  $QueryArgs += $PurposeContains
}

$QueryJson = @(& powershell.exe @QueryArgs) -join "`n"

if($LASTEXITCODE -ne 0){
  throw "PIE_REPO_TEMPLATE_PLAN_QUERY_FAIL"
}

$Query = $QueryJson | ConvertFrom-Json

$Selected = $null
$Reason = "NO_TEMPLATE_DEFAULT_SEQUENCE"
$Sequence = @("repo.status","repo.diff")

if([int]$Query.count -gt 0){
  $Selected = @($Query.results) |
    Sort-Object @{ Expression = "created_utc"; Descending = $true }, @{ Expression = "template_id"; Descending = $false } |
    Select-Object -First 1

  if($null -ne $Selected){
    $Sequence = @($Selected.sequence)
    $Reason = "REPO_TEMPLATE_SELECTED"
  }
}

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
$OutPath = Join-Path $OutRoot ("repo_template_plan_" + $Stamp + ".json")
$LatestPath = Join-Path $OutRoot "latest_repo_template_plan.json"

$Plan = [ordered]@{
  schema = "pie.repo.template.plan.v1"
  session_id = $SessionId
  goal = $Goal
  repo = $TargetRepo
  selected_template_id = $(if($null -ne $Selected){ [string]$Selected.template_id } else { "" })
  reason_code = $Reason
  sequence = $Sequence
  created_utc = [DateTime]::UtcNow.ToString("o")
}

$Json = $Plan | ConvertTo-Json -Depth 30
Write-Utf8NoBomLf -Path $OutPath -Text $Json
Write-Utf8NoBomLf -Path $LatestPath -Text $Json

Write-Host ("PIE_REPO_TEMPLATE_PLAN_OK: " + $OutPath) -ForegroundColor Green
Write-Host ("sequence: " + (@($Sequence) -join " -> "))
