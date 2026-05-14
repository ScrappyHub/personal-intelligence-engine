param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$SessionId,
  [Parameter(Mandatory=$true)][string]$TargetRepo,
  [Parameter(Mandatory=$false)][string]$Role = "related"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$TargetRepo = (Resolve-Path -LiteralPath $TargetRepo).Path
$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)
$LinksPath = Join-Path $RunRoot "repo_links.ndjson"
$Enc = New-Object System.Text.UTF8Encoding($false)

if(-not (Test-Path -LiteralPath $RunRoot -PathType Container)){
  throw ("PIE_SESSION_NOT_STARTED: " + $SessionId)
}

$Obj = [ordered]@{
  schema = "pie.repo.link.v1"
  session_id = $SessionId
  target_repo = $TargetRepo
  role = $Role
  created_utc = [DateTime]::UtcNow.ToString("o")
}

$Line = ($Obj | ConvertTo-Json -Depth 8 -Compress) + "`n"
[System.IO.File]::AppendAllText($LinksPath,$Line,$Enc)

Write-Host ("PIE_REPO_LINK_OK: " + $TargetRepo) -ForegroundColor Green
Write-Host ("role: " + $Role)
