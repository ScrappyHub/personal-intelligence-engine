param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$false)][string]$TargetRepo = "",
  [Parameter(Mandatory=$false)][string]$TemplateId = "",
  [Parameter(Mandatory=$false)][string]$PurposeContains = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$TemplateLog = Join-Path $RepoRoot "memory\repo_templates\repo_templates.ndjson"

if(-not [string]::IsNullOrWhiteSpace($TargetRepo)){
  $TargetRepo = (Resolve-Path -LiteralPath $TargetRepo).Path
}

$Rows = New-Object System.Collections.Generic.List[object]

if(Test-Path -LiteralPath $TemplateLog -PathType Leaf){
  foreach($Line in @(Get-Content -LiteralPath $TemplateLog)){
    if([string]::IsNullOrWhiteSpace($Line)){ continue }

    $Obj = $Line | ConvertFrom-Json

    if(-not [string]::IsNullOrWhiteSpace($TargetRepo)){
      if([string]$Obj.repo -ne $TargetRepo){ continue }
    }

    if(-not [string]::IsNullOrWhiteSpace($TemplateId)){
      if([string]$Obj.template_id -ne $TemplateId){ continue }
    }

    if(-not [string]::IsNullOrWhiteSpace($PurposeContains)){
      if(([string]$Obj.purpose).IndexOf($PurposeContains,[System.StringComparison]::OrdinalIgnoreCase) -lt 0){ continue }
    }

    [void]$Rows.Add($Obj)
  }
}

$Result = [ordered]@{
  schema = "pie.repo.template.query.v1"
  count = @($Rows.ToArray()).Count
  results = $Rows.ToArray()
  created_utc = [DateTime]::UtcNow.ToString("o")
}

Write-Output ($Result | ConvertTo-Json -Depth 40)
