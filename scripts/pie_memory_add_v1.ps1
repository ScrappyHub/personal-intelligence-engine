param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$Text,
  [Parameter(Mandatory=$false)][string]$Scope = "active",
  [Parameter(Mandatory=$false)][string]$Project = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Enc = New-Object System.Text.UTF8Encoding($false)

if($Scope -eq "active"){
  $Dir = Join-Path $RepoRoot "memory\active"
} elseif($Scope -eq "coding"){
  $Dir = Join-Path $RepoRoot "memory\coding"
} elseif($Scope -eq "project"){
  if([string]::IsNullOrWhiteSpace($Project)){ throw "PIE_MEMORY_PROJECT_REQUIRED" }
  $SafeProject = ($Project.ToLowerInvariant() -replace '[^a-z0-9_-]','-')
  $Dir = Join-Path $RepoRoot ("memory\projects\" + $SafeProject)
} else {
  throw ("PIE_MEMORY_SCOPE_UNKNOWN: " + $Scope)
}

New-Item -ItemType Directory -Force -Path $Dir | Out-Null
$Path = Join-Path $Dir "memory.ndjson"

$Now = [DateTime]::UtcNow.ToString("o")
$SafeText = $Text.Replace("\","\\").Replace('"','\"')
$Line = '{"ts":"' + $Now + '","scope":"' + $Scope + '","project":"' + $Project + '","text":"' + $SafeText + '"}' + "`n"

[System.IO.File]::AppendAllText($Path,$Line,$Enc)

Write-Host ("PIE_MEMORY_ADD_OK: " + $Path) -ForegroundColor Green