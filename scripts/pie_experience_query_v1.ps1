param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$false)][string]$GoalContains = "",
  [Parameter(Mandatory=$false)][string]$ChainId = "",
  [Parameter(Mandatory=$false)][string]$Outcome = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$ExperienceLog = Join-Path $RepoRoot "memory\experience\experience.ndjson"

if(-not (Test-Path -LiteralPath $ExperienceLog -PathType Leaf)){
  Write-Host "PIE_EXPERIENCE_QUERY_EMPTY" -ForegroundColor Yellow
  exit 0
}

$Rows = New-Object System.Collections.Generic.List[object]

foreach($Line in @(Get-Content -LiteralPath $ExperienceLog)){
  if([string]::IsNullOrWhiteSpace($Line)){ continue }
  $Obj = $Line | ConvertFrom-Json

  if(-not [string]::IsNullOrWhiteSpace($GoalContains)){
    if(([string]$Obj.goal).IndexOf($GoalContains,[System.StringComparison]::OrdinalIgnoreCase) -lt 0){ continue }
  }

  if(-not [string]::IsNullOrWhiteSpace($ChainId)){
    if([string]$Obj.chain_id -ne $ChainId){ continue }
  }

  if(-not [string]::IsNullOrWhiteSpace($Outcome)){
    if([string]$Obj.outcome -ne $Outcome){ continue }
  }

  [void]$Rows.Add($Obj)
}

$Result = [ordered]@{
  schema = "pie.experience.query.v1"
  count = @($Rows.ToArray()).Count
  results = $Rows.ToArray()
  created_utc = [DateTime]::UtcNow.ToString("o")
}

Write-Output ($Result | ConvertTo-Json -Depth 40)
