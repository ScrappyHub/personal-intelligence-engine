param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$false)][string]$GoalContains = "",
  [Parameter(Mandatory=$false)][string]$Outcome = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$GraphLog = Join-Path $RepoRoot "memory\cognition_graph\cognition_graph.ndjson"

$Rows = New-Object System.Collections.Generic.List[object]

if(Test-Path -LiteralPath $GraphLog -PathType Leaf){
  foreach($Line in @(Get-Content -LiteralPath $GraphLog)){
    if([string]::IsNullOrWhiteSpace($Line)){ continue }
    $Obj = $Line | ConvertFrom-Json

    if(-not [string]::IsNullOrWhiteSpace($GoalContains)){
      if(([string]$Obj.goal).IndexOf($GoalContains,[System.StringComparison]::OrdinalIgnoreCase) -lt 0){ continue }
    }

    if(-not [string]::IsNullOrWhiteSpace($Outcome)){
      if([string]$Obj.outcome -ne $Outcome){ continue }
    }

    [void]$Rows.Add($Obj)
  }
}

$Scores = @{}

foreach($R in @($Rows.ToArray())){
  $Key = [string]$R.sequence_key
  if(-not $Scores.ContainsKey($Key)){ $Scores[$Key] = 0 }

  if([string]$R.outcome -eq "success"){ $Scores[$Key] = [int]$Scores[$Key] + 10 }
  elseif([string]$R.outcome -eq "partial"){ $Scores[$Key] = [int]$Scores[$Key] + 2 }
  elseif([string]$R.outcome -eq "failure"){ $Scores[$Key] = [int]$Scores[$Key] - 8 }
}

$Result = [ordered]@{
  schema = "pie.cognition.graph.query.v1"
  count = @($Rows.ToArray()).Count
  scores = $Scores
  results = $Rows.ToArray()
  created_utc = [DateTime]::UtcNow.ToString("o")
}

Write-Output ($Result | ConvertTo-Json -Depth 40)
