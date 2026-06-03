param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$SessionId,
  [Parameter(Mandatory=$true)][string]$SourceRepo,
  [Parameter(Mandatory=$true)][string]$Goal,
  [Parameter(Mandatory=$false)][string]$Relation = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$SourceRepo = (Resolve-Path -LiteralPath $SourceRepo).Path

$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)
$RouteRoot = Join-Path $RunRoot "cross_repo_routes"
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

New-Item -ItemType Directory -Force -Path $RunRoot | Out-Null
Write-Utf8NoBomLf -Path (Join-Path $RunRoot "project_repo.txt") -Text $SourceRepo
Write-Utf8NoBomLf -Path (Join-Path $RunRoot "goal.txt") -Text $Goal

$QueryArgs = @(
  "-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass",
  "-File",(Join-Path $RepoRoot "scripts\pie_cross_repo_graph_query_v1.ps1"),
  "-RepoRoot",$RepoRoot,
  "-SourceRepo",$SourceRepo
)

if(-not [string]::IsNullOrWhiteSpace($Relation)){
  $QueryArgs += "-Relation"
  $QueryArgs += $Relation
}

$QueryJson = @(& powershell.exe @QueryArgs) -join "`n"

if($LASTEXITCODE -ne 0){
  throw "PIE_CROSS_REPO_ROUTE_QUERY_FAIL"
}

$Query = $QueryJson | ConvertFrom-Json

$Repos = New-Object System.Collections.Generic.List[object]
[void]$Repos.Add([pscustomobject][ordered]@{
  role = "source"
  repo = $SourceRepo
  repo_name = Split-Path -Leaf $SourceRepo
  relation = "self"
})

foreach($Edge in @($Query.results)){
  [void]$Repos.Add([pscustomobject][ordered]@{
    role = "related"
    repo = [string]$Edge.target_repo
    repo_name = [string]$Edge.target_name
    relation = [string]$Edge.relation
    purpose = [string]$Edge.purpose
  })
}

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
$RoutePath = Join-Path $RouteRoot ("cross_repo_route_" + $Stamp + ".json")
$LatestPath = Join-Path $RouteRoot "latest_cross_repo_route.json"

$Route = [ordered]@{
  schema = "pie.cross.repo.route.v1"
  session_id = $SessionId
  goal = $Goal
  source_repo = $SourceRepo
  edge_count = [int]$Query.count
  repos = $Repos.ToArray()
  execution_allowed = $false
  requires_user_confirmation = $true
  note = "Cross-repo route proposal only. No execution performed by this script."
  created_utc = [DateTime]::UtcNow.ToString("o")
}

$Json = $Route | ConvertTo-Json -Depth 40
Write-Utf8NoBomLf -Path $RoutePath -Text $Json
Write-Utf8NoBomLf -Path $LatestPath -Text $Json

Write-Host ("PIE_CROSS_REPO_ROUTE_OK: " + $RoutePath) -ForegroundColor Green
Write-Host ("edge_count: " + [string]$Query.count)
Write-Host "NO_EXECUTION_PERFORMED"
