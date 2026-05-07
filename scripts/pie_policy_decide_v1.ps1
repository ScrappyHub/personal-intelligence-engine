param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$Event,
  [Parameter(Mandatory=$false)][string]$Project = "",
  [Parameter(Mandatory=$false)][string]$Text = "",
  [Parameter(Mandatory=$false)][string]$Source = "pie"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$RulesPath = Join-Path $RepoRoot "policies\PIE_POLICY_RULES.v1.json"

if(-not (Test-Path -LiteralPath $RulesPath -PathType Leaf)){
  throw "PIE_POLICY_RULES_MISSING"
}

$Rules = Get-Content -LiteralPath $RulesPath -Raw | ConvertFrom-Json

$Decision = [string]$Rules.default_decision
$Reason = "DEFAULT_ALLOW"

foreach($Rule in @($Rules.rules)){
  if([string]$Rule.event -eq $Event){
    $Decision = [string]$Rule.decision
    $Reason = [string]$Rule.reason_code
    break
  }
}

$CreatedUtc = [DateTime]::UtcNow.ToString("o")

$Obj = [ordered]@{
  schema = "pie.policy.decision.v1"
  source = $Source
  event = $Event
  project = $Project
  text = $Text
  decision = $Decision
  reason_code = $Reason
  created_utc = $CreatedUtc
}

$OutRoot = Join-Path $RepoRoot "proofs\policy_decisions"
New-Item -ItemType Directory -Force -Path $OutRoot | Out-Null

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
$EventSafe = ($Event -replace '[^a-zA-Z0-9._-]','_')
$ReasonSafe = ($Reason -replace '[^a-zA-Z0-9._-]','_')

$OutPath = Join-Path $OutRoot ("policy_decision_" + $Stamp + "_" + $EventSafe + "_" + $ReasonSafe + ".json")

$Json = $Obj | ConvertTo-Json -Depth 8

[System.IO.File]::WriteAllText(
  $OutPath,
  ($Json.Replace("`r`n","`n") + "`n"),
  (New-Object System.Text.UTF8Encoding($false))
)

Write-Host ("PIE_POLICY_DECISION: " + $Decision + " reason_code=" + $Reason) -ForegroundColor Green
Write-Host ("decision_path: " + $OutPath)