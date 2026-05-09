param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$TargetRepo,
  [Parameter(Mandatory=$false)][string]$Project = "",
  [Parameter(Mandatory=$false)][string]$Language = "",
  [Parameter(Mandatory=$false)][string]$Intent = "coding"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$TargetRepo = (Resolve-Path -LiteralPath $TargetRepo).Path
$Enc = New-Object System.Text.UTF8Encoding($false)

function Write-Utf8NoBomLf {
  param(
    [Parameter(Mandatory=$true)][string]$Path,
    [Parameter(Mandatory=$true)][string]$Text
  )

  $Dir = Split-Path -Parent $Path

  if(-not (Test-Path -LiteralPath $Dir -PathType Container)){
    New-Item -ItemType Directory -Force -Path $Dir | Out-Null
  }

  $Clean = $Text.Replace("`r`n","`n").Replace("`r","`n")

  if(-not $Clean.EndsWith("`n")){
    $Clean += "`n"
  }

  [System.IO.File]::WriteAllText($Path,$Clean,$Enc)
}

if([string]::IsNullOrWhiteSpace($Project)){
  $Project = Split-Path -Leaf $TargetRepo
}

$PieRoot = Join-Path $TargetRepo ".pie"

$PolicyRoot = Join-Path $PieRoot "policies"
$MemoryRoot = Join-Path $PieRoot "memory"
$ReceiptsRoot = Join-Path $PieRoot "receipts"
$ScanRoot = Join-Path $PieRoot "scan"

New-Item -ItemType Directory -Force -Path $PolicyRoot | Out-Null
New-Item -ItemType Directory -Force -Path $MemoryRoot | Out-Null
New-Item -ItemType Directory -Force -Path $ReceiptsRoot | Out-Null
New-Item -ItemType Directory -Force -Path $ScanRoot | Out-Null

$IgnoreDirs = @(
  ".git",
  "node_modules",
  "dist",
  "build",
  "bin",
  "obj",
  ".next",
  ".venv",
  "venv",
  "__pycache__",
  ".pie"
)

$Files = @(
  Get-ChildItem `
    -LiteralPath $TargetRepo `
    -Recurse `
    -File `
    -ErrorAction SilentlyContinue |
  Where-Object {

    $Full = $_.FullName
    $Keep = $true

    foreach($Dir in $IgnoreDirs){
      if($Full -like ("*\" + $Dir + "\*")){
        $Keep = $false
      }
    }

    $Keep
  }
)

$ExtGroups = @{}

foreach($File in $Files){

  $Ext = [System.IO.Path]::GetExtension($File.FullName).ToLowerInvariant()

  if([string]::IsNullOrWhiteSpace($Ext)){
    $Ext = "[no_ext]"
  }

  if(-not $ExtGroups.ContainsKey($Ext)){
    $ExtGroups[$Ext] = 0
  }

  $ExtGroups[$Ext] = [int]$ExtGroups[$Ext] + 1
}

$SuggestedLanguage = $Language

if([string]::IsNullOrWhiteSpace($SuggestedLanguage)){

  if($ExtGroups.ContainsKey(".ps1")){
    $SuggestedLanguage = "PowerShell 5.1"
  }
  elseif($ExtGroups.ContainsKey(".py")){
    $SuggestedLanguage = "Python"
  }
  elseif($ExtGroups.ContainsKey(".ts") -or $ExtGroups.ContainsKey(".js")){
    $SuggestedLanguage = "JavaScript/TypeScript"
  }
  elseif($ExtGroups.ContainsKey(".sql")){
    $SuggestedLanguage = "SQL"
  }
  elseif($ExtGroups.ContainsKey(".rs")){
    $SuggestedLanguage = "Rust"
  }
  elseif($ExtGroups.ContainsKey(".go")){
    $SuggestedLanguage = "Go"
  }
  elseif($ExtGroups.ContainsKey(".cs")){
    $SuggestedLanguage = "C#"
  }
  else {
    $SuggestedLanguage = "Unknown"
  }
}

$Interesting = @(
  Get-ChildItem `
    -LiteralPath $TargetRepo `
    -Recurse `
    -File `
    -ErrorAction SilentlyContinue |
  Where-Object {
    $_.Name -match '(README|WBS|SPEC|ROADMAP|PLAN|ARCHITECTURE|TODO|CHANGELOG)' -and
    $_.FullName -notlike "*\.git\*" -and
    $_.FullName -notlike "*\node_modules\*" -and
    $_.FullName -notlike "*\.pie\*"
  } |
  Select-Object -First 50
)

$Manifest = [ordered]@{
  schema = "pie.repo.integration.v1"
  project = $Project
  target_repo = $TargetRepo
  language = $SuggestedLanguage
  requested_language = $Language
  intent = $Intent
  pie_runtime_repo = $RepoRoot
  file_count = @($Files).Count
  extension_counts = $ExtGroups
  candidate_docs = @(
    $Interesting | ForEach-Object { $_.FullName }
  )
  ai_role = "assistant_only_not_executor"
  created_utc = [DateTime]::UtcNow.ToString("o")
}

Write-Utf8NoBomLf `
  -Path (Join-Path $PieRoot "manifest.json") `
  -Text ($Manifest | ConvertTo-Json -Depth 20)

$Overlay = [ordered]@{
  schema = "pie.policy.overlay.v1"
  project = $Project
  scope = "repo"
  target_repo = $TargetRepo
  rules = @(
    [ordered]@{
      event = "repo_scan"
      decision = "ALLOW"
      reason_code = "REPO_SCAN_ALLOWED"
    },
    [ordered]@{
      event = "repo_write"
      decision = "ASK_CONFIRMATION"
      reason_code = "REPO_WRITE_REQUIRES_CONFIRMATION"
    },
    [ordered]@{
      event = "external_sync"
      decision = "ASK_CONFIRMATION"
      reason_code = "EXTERNAL_SYNC_REQUIRES_CONFIRMATION"
    },
    [ordered]@{
      event = "dangerous_command"
      decision = "DENY"
      reason_code = "DANGEROUS_COMMAND_BLOCKED"
    },
    [ordered]@{
      event = "ai_execute_code"
      decision = "DENY"
      reason_code = "AI_ASSISTANT_NOT_EXECUTOR"
    }
  )
}

Write-Utf8NoBomLf `
  -Path (Join-Path $PolicyRoot "overlay.policy.json") `
  -Text ($Overlay | ConvertTo-Json -Depth 20)

$SummaryLines = @()

$SummaryLines += "PIE REPO PROFILE"
$SummaryLines += ("project=" + $Project)
$SummaryLines += ("repo=" + $TargetRepo)
$SummaryLines += ("suggested_language=" + $SuggestedLanguage)
$SummaryLines += ("file_count=" + @($Files).Count)
$SummaryLines += ""
$SummaryLines += "Candidate docs:"

foreach($Doc in $Interesting){
  $SummaryLines += ("- " + $Doc.FullName)
}

Write-Utf8NoBomLf `
  -Path (Join-Path $ScanRoot "repo_profile.txt") `
  -Text ($SummaryLines -join "`n")

$MemorySeed = '{"schema":"pie.repo.memory.v1","lane":"project","text":"Repo integrated with PIE. Treat this repo as a separate artifact. Scan/read before describing files. Do not invent repo structure. AI is assistant, not executor.","created_utc":"' + [DateTime]::UtcNow.ToString("o") + '"}'

Write-Utf8NoBomLf `
  -Path (Join-Path $MemoryRoot "memory.ndjson") `
  -Text $MemorySeed

$Receipt = [ordered]@{
  schema = "pie.repo.integration.receipt.v1"
  project = $Project
  target_repo = $TargetRepo
  pie_root = $PieRoot
  status = "integrated"
  suggested_language = $SuggestedLanguage
  created_utc = [DateTime]::UtcNow.ToString("o")
}

Write-Utf8NoBomLf `
  -Path (Join-Path $ReceiptsRoot "repo_integration.receipt.json") `
  -Text ($Receipt | ConvertTo-Json -Depth 12)

Write-Host ("PIE_REPO_INTEGRATE_OK: " + $PieRoot) -ForegroundColor Green
Write-Host ("suggested_language: " + $SuggestedLanguage)
Write-Host ("repo_profile: " + (Join-Path $ScanRoot "repo_profile.txt"))

