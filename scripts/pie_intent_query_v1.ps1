param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$false)][string]$Status = "",
  [Parameter(Mandatory=$false)][string]$GoalContains = "",
  [Parameter(Mandatory=$false)][string]$Repo = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$IntentLog = Join-Path $RepoRoot "memory\intent\intent.ndjson"

$Rows = New-Object System.Collections.Generic.List[object]

if(Test-Path -LiteralPath $IntentLog -PathType Leaf){
  foreach($Line in @(Get-Content -LiteralPath $IntentLog)){
    if([string]::IsNullOrWhiteSpace($Line)){ continue }

    $Obj = $Line | ConvertFrom-Json

    if(-not [string]::IsNullOrWhiteSpace($Status)){
      if([string]$Obj.status -ne $Status){ continue }
    }

    if(-not [string]::IsNullOrWhiteSpace($GoalContains)){
      if(([string]$Obj.goal).IndexOf($GoalContains,[System.StringComparison]::OrdinalIgnoreCase) -lt 0){ continue }
    }

    if(-not [string]::IsNullOrWhiteSpace($Repo)){
      if([string]$Obj.repo -ne $Repo){ continue }
    }

    [void]$Rows.Add($Obj)
  }
}

$Result = [ordered]@{
  schema = "pie.intent.query.v1"
  count = @($Rows.ToArray()).Count
  results = $Rows.ToArray()
  created_utc = [DateTime]::UtcNow.ToString("o")
}

Write-Output ($Result | ConvertTo-Json -Depth 40)
