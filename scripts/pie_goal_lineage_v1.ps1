param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$SessionId,
  [Parameter(Mandatory=$true)][string]$Goal,
  [Parameter(Mandatory=$false)][string]$IntentId = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)
$LineageRoot = Join-Path $RunRoot "goal_lineage"
$IntentLog = Join-Path $RepoRoot "memory\intent\intent.ndjson"
$ExperienceLog = Join-Path $RepoRoot "memory\experience\experience.ndjson"
$CogGraphLog = Join-Path $RepoRoot "memory\cognition_graph\cognition_graph.ndjson"
$CogConv = Join-Path $RepoRoot "memory\cognition_convergence\cognition_convergence.latest.json"
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

function Add-ExistingFileRef {
  param(
    [System.Collections.Generic.List[object]]$List,
    [string]$Kind,
    [string]$Path
  )

  if(Test-Path -LiteralPath $Path -PathType Leaf){
    $Sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
    [void]$List.Add([pscustomobject][ordered]@{
      kind = $Kind
      path = $Path
      sha256 = $Sha
    })
  }
}

function Add-LatestFileRef {
  param(
    [System.Collections.Generic.List[object]]$List,
    [string]$Kind,
    [string]$Dir,
    [string]$Filter
  )

  if(Test-Path -LiteralPath $Dir -PathType Container){
    $Latest = Get-ChildItem -LiteralPath $Dir -File -Filter $Filter -ErrorAction SilentlyContinue |
      Sort-Object Name -Descending |
      Select-Object -First 1

    if($null -ne $Latest){
      Add-ExistingFileRef -List $List -Kind $Kind -Path $Latest.FullName
    }
  }
}

if(-not (Test-Path -LiteralPath $RunRoot -PathType Container)){
  New-Item -ItemType Directory -Force -Path $RunRoot | Out-Null
}

$IntentMatches = New-Object System.Collections.Generic.List[object]

if(Test-Path -LiteralPath $IntentLog -PathType Leaf){
  foreach($Line in @(Get-Content -LiteralPath $IntentLog)){
    if([string]::IsNullOrWhiteSpace($Line)){ continue }

    $Obj = $Line | ConvertFrom-Json

    if(-not [string]::IsNullOrWhiteSpace($IntentId)){
      if([string]$Obj.intent_id -ne $IntentId){ continue }
    }
    else {
      if(([string]$Obj.goal).IndexOf($Goal,[System.StringComparison]::OrdinalIgnoreCase) -lt 0 -and
         $Goal.IndexOf([string]$Obj.goal,[System.StringComparison]::OrdinalIgnoreCase) -lt 0){
        continue
      }
    }

    [void]$IntentMatches.Add($Obj)
  }
}

$ExperienceMatches = New-Object System.Collections.Generic.List[object]

if(Test-Path -LiteralPath $ExperienceLog -PathType Leaf){
  foreach($Line in @(Get-Content -LiteralPath $ExperienceLog)){
    if([string]::IsNullOrWhiteSpace($Line)){ continue }

    $Obj = $Line | ConvertFrom-Json

    if(([string]$Obj.goal).IndexOf($Goal,[System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
       $Goal.IndexOf([string]$Obj.goal,[System.StringComparison]::OrdinalIgnoreCase) -ge 0){
      [void]$ExperienceMatches.Add($Obj)
    }
  }
}

$CogMatches = New-Object System.Collections.Generic.List[object]

if(Test-Path -LiteralPath $CogGraphLog -PathType Leaf){
  foreach($Line in @(Get-Content -LiteralPath $CogGraphLog)){
    if([string]::IsNullOrWhiteSpace($Line)){ continue }

    $Obj = $Line | ConvertFrom-Json

    if(([string]$Obj.goal).IndexOf($Goal,[System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
       $Goal.IndexOf([string]$Obj.goal,[System.StringComparison]::OrdinalIgnoreCase) -ge 0){
      [void]$CogMatches.Add($Obj)
    }
  }
}

$Artifacts = New-Object System.Collections.Generic.List[object]

Add-LatestFileRef -List $Artifacts -Kind "intent_resume" -Dir (Join-Path $RunRoot "intent_resume") -Filter "intent_resume_*.json"
Add-LatestFileRef -List $Artifacts -Kind "synthesized_plan" -Dir (Join-Path $RunRoot "synthesized_plans") -Filter "synth_plan_*.json"
Add-LatestFileRef -List $Artifacts -Kind "orchestration_decision" -Dir (Join-Path $RunRoot "orchestration_decisions") -Filter "orchestration_decision_*.json"
Add-LatestFileRef -List $Artifacts -Kind "orchestration_plan" -Dir (Join-Path $RunRoot "orchestration") -Filter "orchestration_plan_*.json"
Add-LatestFileRef -List $Artifacts -Kind "reason_trace" -Dir (Join-Path $RunRoot "reason_traces") -Filter "reason_trace_*.json"
Add-LatestFileRef -List $Artifacts -Kind "execution_replay" -Dir (Join-Path $RunRoot "replay") -Filter "execution_replay_*.json"
Add-ExistingFileRef -List $Artifacts -Kind "execution_receipts" -Path (Join-Path $RunRoot "execution\execution_receipts.ndjson")
Add-ExistingFileRef -List $Artifacts -Kind "cognition_convergence" -Path $CogConv

$LineageIdSource = $Goal + "|" + $SessionId + "|" + $IntentId
$Bytes = [System.Text.Encoding]::UTF8.GetBytes($LineageIdSource)
$Sha = [System.Security.Cryptography.SHA256]::Create()
$LineageId = ([BitConverter]::ToString($Sha.ComputeHash($Bytes)).Replace("-","").ToLowerInvariant()).Substring(0,24)

$Lineage = [ordered]@{
  schema = "pie.goal.lineage.v1"
  lineage_id = $LineageId
  session_id = $SessionId
  goal = $Goal
  intent_id = $IntentId
  intents = $IntentMatches.ToArray()
  experiences = $ExperienceMatches.ToArray()
  cognition_graph_entries = $CogMatches.ToArray()
  artifacts = $Artifacts.ToArray()
  created_utc = [DateTime]::UtcNow.ToString("o")
}

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
$OutPath = Join-Path $LineageRoot ("goal_lineage_" + $Stamp + ".json")
$LatestPath = Join-Path $LineageRoot "latest_goal_lineage.json"

$Json = $Lineage | ConvertTo-Json -Depth 50
Write-Utf8NoBomLf -Path $OutPath -Text $Json
Write-Utf8NoBomLf -Path $LatestPath -Text $Json

Write-Host ("PIE_GOAL_LINEAGE_OK: " + $OutPath) -ForegroundColor Green
Write-Host ("lineage_id: " + $LineageId)
