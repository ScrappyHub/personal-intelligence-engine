param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$SessionId,
  [Parameter(Mandatory=$true)][string]$Goal,
  [Parameter(Mandatory=$false)][string]$DefaultChainId = "repo.health.basic",
  [Parameter(Mandatory=$false)][switch]$Confirm,
  [Parameter(Mandatory=$false)][switch]$AutoConfirmAllowed
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)
$DecisionRoot = Join-Path $RunRoot "orchestration_decisions"
$ExperienceLog = Join-Path $RepoRoot "memory\experience\experience.ndjson"
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
  throw ("PIE_ORCH_SELECT_SESSION_NOT_FOUND: " + $SessionId)
}

$Scores = @{}
$Evidence = New-Object System.Collections.Generic.List[object]

if(Test-Path -LiteralPath $ExperienceLog -PathType Leaf){
  foreach($Line in @(Get-Content -LiteralPath $ExperienceLog)){
    if([string]::IsNullOrWhiteSpace($Line)){ continue }

    $Entry = $Line | ConvertFrom-Json
    $Chain = [string]$Entry.chain_id

    if([string]::IsNullOrWhiteSpace($Chain)){ continue }

    if(-not $Scores.ContainsKey($Chain)){
      $Scores[$Chain] = 0
    }

    if([string]$Entry.outcome -eq "success"){
      $Scores[$Chain] = [int]$Scores[$Chain] + 10
    }
    elseif([string]$Entry.outcome -eq "partial"){
      $Scores[$Chain] = [int]$Scores[$Chain] + 2
    }
    elseif([string]$Entry.outcome -eq "failure"){
      $Scores[$Chain] = [int]$Scores[$Chain] - 8
    }

    [void]$Evidence.Add([pscustomobject][ordered]@{
      chain_id = $Chain
      outcome = [string]$Entry.outcome
      goal = [string]$Entry.goal
      created_utc = [string]$Entry.created_utc
      replay_sha256 = [string]$Entry.replay_sha256
      reason_trace_sha256 = [string]$Entry.reason_trace_sha256
      freeze_hash = [string]$Entry.freeze_hash
    })
  }
}

$SelectedChain = $DefaultChainId
$SelectedScore = 0
$Reason = "DEFAULT_CHAIN_NO_EXPERIENCE"

if($Scores.Count -gt 0){
  $Best = $Scores.GetEnumerator() |
    Sort-Object @{ Expression = "Value"; Descending = $true }, @{ Expression = "Key"; Descending = $false } |
    Select-Object -First 1

  if($null -ne $Best -and [int]$Best.Value -gt 0){
    $SelectedChain = [string]$Best.Key
    $SelectedScore = [int]$Best.Value
    $Reason = "EXPERIENCE_BEST_POSITIVE_SCORE"
  }
  else {
    $Reason = "NO_POSITIVE_EXPERIENCE_SCORE_DEFAULT_USED"
  }
}

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
$DecisionPath = Join-Path $DecisionRoot ("orchestration_decision_" + $Stamp + ".json")
$LatestPath = Join-Path $DecisionRoot "latest_orchestration_decision.json"

$Decision = [ordered]@{
  schema = "pie.orchestration.decision.v1"
  session_id = $SessionId
  goal = $Goal
  default_chain_id = $DefaultChainId
  selected_chain_id = $SelectedChain
  selected_score = $SelectedScore
  reason_code = $Reason
  scores = $Scores
  evidence = $Evidence.ToArray()
  created_utc = [DateTime]::UtcNow.ToString("o")
}

$Json = $Decision | ConvertTo-Json -Depth 40
Write-Utf8NoBomLf -Path $DecisionPath -Text $Json
Write-Utf8NoBomLf -Path $LatestPath -Text $Json

Write-Host ("PIE_ORCH_DECISION_OK: " + $DecisionPath) -ForegroundColor Green
Write-Host ("selected_chain: " + $SelectedChain)

$Orch = Join-Path $RepoRoot "scripts\pie_orchestrate_v1.ps1"

$Args = @(
  "-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass",
  "-File",$Orch,
  "-RepoRoot",$RepoRoot,
  "-SessionId",$SessionId,
  "-ChainId",$SelectedChain
)

if($Confirm){ $Args += "-Confirm" }
if($AutoConfirmAllowed){ $Args += "-AutoConfirmAllowed" }

& powershell.exe @Args | Out-Host

if($LASTEXITCODE -ne 0){
  throw ("PIE_ORCH_SELECT_EXEC_FAIL: " + $SelectedChain)
}

Write-Host ("PIE_ORCH_SELECT_OK: " + $SelectedChain) -ForegroundColor Green
