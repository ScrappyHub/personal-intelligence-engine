param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$false)][string]$SourceRepo = "",
  [Parameter(Mandatory=$false)][string]$TargetRepo = "",
  [Parameter(Mandatory=$false)][string]$Relation = "",
  [Parameter(Mandatory=$false)][string]$PurposeContains = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$GraphLog = Join-Path $RepoRoot "memory\cross_repo_graph\cross_repo_graph.ndjson"

if(-not [string]::IsNullOrWhiteSpace($SourceRepo)){
  $SourceRepo = (Resolve-Path -LiteralPath $SourceRepo).Path
}

if(-not [string]::IsNullOrWhiteSpace($TargetRepo)){
  $TargetRepo = (Resolve-Path -LiteralPath $TargetRepo).Path
}

$Rows = New-Object System.Collections.Generic.List[object]

if(Test-Path -LiteralPath $GraphLog -PathType Leaf){
  foreach($Line in @(Get-Content -LiteralPath $GraphLog)){
    if([string]::IsNullOrWhiteSpace($Line)){ continue }

    $Obj = $Line | ConvertFrom-Json

    if(-not [string]::IsNullOrWhiteSpace($SourceRepo)){
      if([string]$Obj.source_repo -ne $SourceRepo){ continue }
    }

    if(-not [string]::IsNullOrWhiteSpace($TargetRepo)){
      if([string]$Obj.target_repo -ne $TargetRepo){ continue }
    }

    if(-not [string]::IsNullOrWhiteSpace($Relation)){
      if([string]$Obj.relation -ne $Relation){ continue }
    }

    if(-not [string]::IsNullOrWhiteSpace($PurposeContains)){
      if(([string]$Obj.purpose).IndexOf($PurposeContains,[System.StringComparison]::OrdinalIgnoreCase) -lt 0){ continue }
    }

    [void]$Rows.Add($Obj)
  }
}

$Result = [ordered]@{
  schema = "pie.cross.repo.graph.query.v1"
  count = @($Rows.ToArray()).Count
  results = $Rows.ToArray()
  created_utc = [DateTime]::UtcNow.ToString("o")
}

Write-Output ($Result | ConvertTo-Json -Depth 40)
