param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$Text,
  [Parameter(Mandatory=$false)][string]$Lane = "active",
  [Parameter(Mandatory=$false)][string]$Project = "",
  [Parameter(Mandatory=$false)][string]$ProjectRepo = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Enc = New-Object System.Text.UTF8Encoding($false)

if($Lane -eq "active"){
  $MemoryDir = Join-Path $RepoRoot "memory\active"
  $MemoryPath = Join-Path $MemoryDir "memory.ndjson"
} elseif($Lane -eq "coding"){
  $MemoryDir = Join-Path $RepoRoot "memory\coding"
  $MemoryPath = Join-Path $MemoryDir "memory.ndjson"
} elseif($Lane -eq "project"){
  if([string]::IsNullOrWhiteSpace($Project)){ throw "PIE_MEMORY_PROJECT_REQUIRED" }
  $SafeProjectName = ($Project.ToLowerInvariant() -replace '[^a-z0-9_-]','-')
  $MemoryDir = Join-Path $RepoRoot ("memory\projects\" + $SafeProjectName)
  $MemoryPath = Join-Path $MemoryDir "memory.ndjson"
} else {
  throw ("PIE_MEMORY_LANE_INVALID: " + $Lane)
}

New-Item -ItemType Directory -Force -Path $MemoryDir | Out-Null

$Now = [DateTime]::UtcNow.ToString("o")
$SafeText = $Text.Replace("\","\\").Replace('"','\"')
$SafeProject = $Project.Replace("\","\\").Replace('"','\"')

$Line = '{"ts":"' + $Now + '","lane":"' + $Lane + '","project":"' + $SafeProject + '","text":"' + $SafeText + '"}' + "`n"
[System.IO.File]::AppendAllText($MemoryPath,$Line,$Enc)

if(-not [string]::IsNullOrWhiteSpace($ProjectRepo)){
  $ProjectRepo = (Resolve-Path -LiteralPath $ProjectRepo).Path
  $PieMemoryDir = Join-Path $ProjectRepo ".pie\memory"
  New-Item -ItemType Directory -Force -Path $PieMemoryDir | Out-Null
  [System.IO.File]::AppendAllText((Join-Path $PieMemoryDir "project.ndjson"),$Line,$Enc)
}

Write-Host ("PIE_MEMORY_ACCEPT_OK: " + $MemoryPath) -ForegroundColor Green