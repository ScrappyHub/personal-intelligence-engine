param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$false)][string]$IntentId = "",
  [Parameter(Mandatory=$false)][string]$GoalContains = "",
  [Parameter(Mandatory=$false)][string]$SessionId = "pie_intent_resume"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)
$ResumeRoot = Join-Path $RunRoot "intent_resume"
$IntentLog = Join-Path $RepoRoot "memory\intent\intent.ndjson"
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

if(-not (Test-Path -LiteralPath $IntentLog -PathType Leaf)){
  throw ("PIE_INTENT_RESUME_LOG_MISSING: " + $IntentLog)
}

New-Item -ItemType Directory -Force -Path $RunRoot | Out-Null

$Candidates = New-Object System.Collections.Generic.List[object]

foreach($Line in @(Get-Content -LiteralPath $IntentLog)){
  if([string]::IsNullOrWhiteSpace($Line)){ continue }

  $Obj = $Line | ConvertFrom-Json

  if([string]$Obj.status -notin @("open","paused","blocked")){
    continue
  }

  if(-not [string]::IsNullOrWhiteSpace($IntentId)){
    if([string]$Obj.intent_id -ne $IntentId){ continue }
  }

  if(-not [string]::IsNullOrWhiteSpace($GoalContains)){
    if(([string]$Obj.goal).IndexOf($GoalContains,[System.StringComparison]::OrdinalIgnoreCase) -lt 0){ continue }
  }

  [void]$Candidates.Add($Obj)
}

if(@($Candidates.ToArray()).Count -lt 1){
  throw "PIE_INTENT_RESUME_NO_MATCH"
}

$Selected = @($Candidates.ToArray()) |
  Sort-Object @{ Expression = "created_utc"; Descending = $true }, @{ Expression = "intent_id"; Descending = $false } |
  Select-Object -First 1

$Goal = [string]$Selected.goal
$Repo = [string]$Selected.repo

if([string]::IsNullOrWhiteSpace($Repo)){
  $Repo = $RepoRoot
}

if(-not (Test-Path -LiteralPath $Repo -PathType Container)){
  $Repo = $RepoRoot
}

Write-Utf8NoBomLf -Path (Join-Path $RunRoot "project_repo.txt") -Text $Repo
Write-Utf8NoBomLf -Path (Join-Path $RunRoot "goal.txt") -Text $Goal

$SynthOut = @(
  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File (Join-Path $RepoRoot "scripts\pie_plan_synthesize_v1.ps1") `
    -RepoRoot $RepoRoot `
    -SessionId $SessionId `
    -Goal $Goal
) -join "`n"

if($LASTEXITCODE -ne 0){
  throw "PIE_INTENT_RESUME_SYNTH_FAIL"
}

$SynthPlan = Join-Path $RunRoot "synthesized_plans\latest_synth_plan.json"
if(-not (Test-Path -LiteralPath $SynthPlan -PathType Leaf)){
  throw "PIE_INTENT_RESUME_SYNTH_PLAN_MISSING"
}

$Plan = Get-Content -LiteralPath $SynthPlan -Raw | ConvertFrom-Json

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
$ResumePath = Join-Path $ResumeRoot ("intent_resume_" + $Stamp + ".json")
$LatestPath = Join-Path $ResumeRoot "latest_intent_resume.json"

$Proposal = [ordered]@{
  schema = "pie.intent.resume.proposal.v1"
  intent_id = [string]$Selected.intent_id
  session_id = $SessionId
  goal = $Goal
  repo = $Repo
  selected_sequence = @($Plan.sequence)
  selected_score = [int]$Plan.selected_score
  reason_code = [string]$Plan.reason_code
  synth_plan = $SynthPlan
  execution_allowed = $false
  requires_user_confirmation = $true
  note = "Resume proposal only. No execution performed by this script."
  created_utc = [DateTime]::UtcNow.ToString("o")
}

$Json = $Proposal | ConvertTo-Json -Depth 30
Write-Utf8NoBomLf -Path $ResumePath -Text $Json
Write-Utf8NoBomLf -Path $LatestPath -Text $Json

Write-Host ("PIE_INTENT_RESUME_OK: " + $ResumePath) -ForegroundColor Green
Write-Host ("intent_id: " + [string]$Selected.intent_id)
Write-Host ("sequence: " + (@($Plan.sequence) -join " -> "))
Write-Host "NO_EXECUTION_PERFORMED"
