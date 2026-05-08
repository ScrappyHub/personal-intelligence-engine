param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$TargetRepo,
  [Parameter(Mandatory=$false)][string]$Project = "",
  [Parameter(Mandatory=$false)][string]$Model = "qwen2.5-coder:7b"
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

function Get-FileSha256 {
  param(
    [Parameter(Mandatory=$true)][string]$Path
  )

  $Sha = [System.Security.Cryptography.SHA256]::Create()

  try {
    $Stream = [System.IO.File]::OpenRead($Path)

    try {
      $Hash = $Sha.ComputeHash($Stream)
    }
    finally {
      $Stream.Dispose()
    }

    return (($Hash | ForEach-Object { $_.ToString("x2") }) -join "")
  }
  finally {
    $Sha.Dispose()
  }
}

function Test-SafeRelativePath {
  param(
    [Parameter(Mandatory=$true)][string]$RelativePath
  )

  if([string]::IsNullOrWhiteSpace($RelativePath)){
    return $false
  }

  # No absolute Windows drive leakage.
  if($RelativePath -match '^[a-zA-Z]:'){
    return $false
  }

  # No colon anywhere in repo-relative path.
  if($RelativePath -match ':'){
    return $false
  }

  # No mojibake / replacement chars from broken encodings.
  if($RelativePath -match '[ïÃ�]'){
    return $false
  }

  # No traversal.
  if($RelativePath -match '(^|\\)\.\.(\\|$)'){
    return $false
  }

  return $true
}

if([string]::IsNullOrWhiteSpace($Project)){
  $Project = Split-Path -Leaf $TargetRepo
}

$PieRoot = Join-Path $TargetRepo ".pie"
$ScanRoot = Join-Path $PieRoot "scan"
$ArtifactRoot = Join-Path $ScanRoot "artifacts"
$Stamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
$ThisScan = Join-Path $ArtifactRoot $Stamp

New-Item -ItemType Directory -Force -Path $ThisScan | Out-Null

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
  ".pie",
  ".nfl-keytest"
)

$AllFiles = @(
  Get-ChildItem `
    -LiteralPath $TargetRepo `
    -Recurse `
    -File `
    -ErrorAction SilentlyContinue |
  Sort-Object FullName
)

$Files = New-Object System.Collections.Generic.List[object]

foreach($File in $AllFiles){

  $Full = [string]$File.FullName
  $Keep = $true

  foreach($Dir in $IgnoreDirs){
    if($Full -like ("*\" + $Dir + "\*")){
      $Keep = $false
    }
  }

  if($Keep){
    [void]$Files.Add($File)
  }
}

$Records = New-Object System.Collections.Generic.List[object]
$ExtGroups = @{}
$SkippedUnsafe = New-Object System.Collections.Generic.List[string]

foreach($File in @($Files.ToArray())){

  $FullName = [string]$File.FullName

  if(-not $FullName.StartsWith($TargetRepo,[System.StringComparison]::OrdinalIgnoreCase)){
    [void]$SkippedUnsafe.Add($FullName)
    continue
  }

  $Rel = $FullName.Substring($TargetRepo.Length).TrimStart("\")

  if(-not (Test-SafeRelativePath -RelativePath $Rel)){
    [void]$SkippedUnsafe.Add($Rel)
    continue
  }

  $Ext = [System.IO.Path]::GetExtension($FullName).ToLowerInvariant()

  if([string]::IsNullOrWhiteSpace($Ext)){
    $Ext = "[no_ext]"
  }

  if(-not $ExtGroups.ContainsKey($Ext)){
    $ExtGroups[$Ext] = 0
  }

  $ExtGroups[$Ext] = [int]$ExtGroups[$Ext] + 1

  $Obj = New-Object PSObject
  $Obj | Add-Member -NotePropertyName path -NotePropertyValue $Rel
  $Obj | Add-Member -NotePropertyName bytes -NotePropertyValue ([int64]$File.Length)
  $Obj | Add-Member -NotePropertyName sha256 -NotePropertyValue (Get-FileSha256 -Path $FullName)
  $Obj | Add-Member -NotePropertyName extension -NotePropertyValue $Ext

  [void]$Records.Add($Obj)
}

$Inventory = [ordered]@{
  schema = "pie.repo.scan.inventory.v1"
  project = $Project
  target_repo = $TargetRepo
  file_count = @($Records.ToArray()).Count
  skipped_unsafe_path_count = @($SkippedUnsafe.ToArray()).Count
  extension_counts = $ExtGroups
  files = @($Records.ToArray())
  created_utc = [DateTime]::UtcNow.ToString("o")
}

$InventoryPath = Join-Path $ThisScan "inventory.json"
Write-Utf8NoBomLf -Path $InventoryPath -Text ($Inventory | ConvertTo-Json -Depth 40)

if(@($SkippedUnsafe.ToArray()).Count -gt 0){
  Write-Utf8NoBomLf -Path (Join-Path $ThisScan "skipped_unsafe_paths.txt") -Text ($SkippedUnsafe.ToArray() -join "`n")
}

$LatestPath = Join-Path $ScanRoot "latest_inventory.json"

$DiffLines = New-Object System.Collections.Generic.List[string]
[void]$DiffLines.Add("PIE REPO SCAN DIFF")
[void]$DiffLines.Add("project=" + $Project)
[void]$DiffLines.Add("repo=" + $TargetRepo)
[void]$DiffLines.Add("scan=" + $Stamp)
[void]$DiffLines.Add("")

if(Test-Path -LiteralPath $LatestPath -PathType Leaf){

  $Prev = Get-Content -LiteralPath $LatestPath -Raw | ConvertFrom-Json

  $PrevMap = @{}
  foreach($Item in @($Prev.files)){
    $PrevMap[[string]$Item.path] = [string]$Item.sha256
  }

  $NowMap = @{}
  foreach($Item in @($Records.ToArray())){
    $NowMap[[string]$Item.path] = [string]$Item.sha256
  }

  foreach($P in @($NowMap.Keys | Sort-Object)){
    if(-not $PrevMap.ContainsKey($P)){
      [void]$DiffLines.Add("ADDED " + $P)
    }
    elseif($PrevMap[$P] -ne $NowMap[$P]){
      [void]$DiffLines.Add("CHANGED " + $P)
    }
  }

  foreach($P in @($PrevMap.Keys | Sort-Object)){
    if(-not $NowMap.ContainsKey($P)){
      [void]$DiffLines.Add("REMOVED " + $P)
    }
  }
}
else {
  [void]$DiffLines.Add("BASELINE_SCAN_NO_PREVIOUS")
}

$DiffPath = Join-Path $ThisScan "diff.txt"
Write-Utf8NoBomLf -Path $DiffPath -Text ($DiffLines.ToArray() -join "`n")

$CandidateDocs = New-Object System.Collections.Generic.List[object]

foreach($File in @($Files.ToArray())){

  $FullName = [string]$File.FullName

  if(-not $FullName.StartsWith($TargetRepo,[System.StringComparison]::OrdinalIgnoreCase)){
    continue
  }

  $Rel = $FullName.Substring($TargetRepo.Length).TrimStart("\")

  if(-not (Test-SafeRelativePath -RelativePath $Rel)){
    continue
  }

  if($File.Name -match '(README|WBS|SPEC|ROADMAP|PLAN|ARCHITECTURE|TODO|CHANGELOG|CONSTITUTION|LAW|DESIGN)'){
    if(@($CandidateDocs.ToArray()).Count -lt 25){
      [void]$CandidateDocs.Add($File)
    }
  }
}

$DocText = New-Object System.Collections.Generic.List[string]

foreach($Doc in @($CandidateDocs.ToArray())){

  $DocFull = [string]$Doc.FullName
  $DocRel = $DocFull.Substring($TargetRepo.Length).TrimStart("\")

  [void]$DocText.Add("FILE: " + $DocRel)

  try {
    $Raw = Get-Content -LiteralPath $DocFull -Raw -ErrorAction Stop

    if($Raw.Length -gt 12000){
      $Raw = $Raw.Substring(0,12000)
    }

    [void]$DocText.Add($Raw)
  }
  catch {
    [void]$DocText.Add("UNREADABLE_DOC")
  }

  [void]$DocText.Add("")
}

$ExtSummaryLines = New-Object System.Collections.Generic.List[string]

foreach($Key in @($ExtGroups.Keys | Sort-Object)){
  [void]$ExtSummaryLines.Add(([string]$Key) + "=" + ([string]$ExtGroups[$Key]))
}

$DiffText = $DiffLines.ToArray() -join "`n"
$DocTextJoined = $DocText.ToArray() -join "`n"
$FileCount = @($Records.ToArray()).Count
$ExtSummary = $ExtSummaryLines.ToArray() -join "`n"

$Prompt = @"
You are PIE creating a repo-level intelligence artifact.

Return MARKDOWN ONLY.

Rules:
- Do not invent files.
- Do not summarize a single script as if it is the whole repo.
- Use only the inventory summary, candidate docs, extension counts, and diff provided.
- Describe what this repository appears to be at a project level.
- List likely languages/stacks.
- List important docs found by relative path only.
- List changes since previous scan.
- State uncertainty clearly.
- AI is assistant only, not executor.
- Do not output JSON unless the candidate docs themselves require JSON.

PROJECT:
$Project

REPO:
$TargetRepo

INVENTORY FILE COUNT:
$FileCount

EXTENSION COUNTS:
$ExtSummary

DIFF:
$DiffText

CANDIDATE DOC CONTENT:
$DocTextJoined
"@

$PromptPath = Join-Path $ThisScan "ai_prompt.txt"
Write-Utf8NoBomLf -Path $PromptPath -Text $Prompt

$Backend = Join-Path $RepoRoot "scripts\pie_backend_ollama_cmd_v1.ps1"

if(-not (Test-Path -LiteralPath $Backend -PathType Leaf)){
  throw "PIE_BACKEND_SCRIPT_MISSING"
}

$AiText = @(
  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File $Backend `
    -Model $Model `
    -MessagePath $PromptPath
) -join "`n"

if($LASTEXITCODE -ne 0){
  throw "PIE_REPO_SCAN_AI_DESCRIPTION_FAIL"
}

$AiPath = Join-Path $ThisScan "ai_repo_description.md"
Write-Utf8NoBomLf -Path $AiPath -Text $AiText

$Artifact = [ordered]@{
  schema = "pie.repo.scan.artifact.v1"
  project = $Project
  target_repo = $TargetRepo
  scan_id = $Stamp
  inventory = $InventoryPath
  diff = $DiffPath
  ai_prompt = $PromptPath
  ai_description = $AiPath
  status = "scan_complete"
  created_utc = [DateTime]::UtcNow.ToString("o")
}

Write-Utf8NoBomLf -Path (Join-Path $ThisScan "artifact.json") -Text ($Artifact | ConvertTo-Json -Depth 12)

Copy-Item -LiteralPath $InventoryPath -Destination $LatestPath -Force

Write-Host ("PIE_REPO_SCAN_OK: " + $ThisScan) -ForegroundColor Green
Write-Host ("ai_prompt: " + $PromptPath)
Write-Host ("ai_description: " + $AiPath)
Write-Host ("diff: " + $DiffPath)

if(@($SkippedUnsafe.ToArray()).Count -gt 0){
  Write-Host ("skipped_unsafe_paths: " + @($SkippedUnsafe.ToArray()).Count) -ForegroundColor Yellow
}

Write-Host ""

Write-Host "PIE_REPO_SCAN_DESCRIPTION_PREVIEW" -ForegroundColor Cyan
Write-Host "--------------------------------"

$Preview = Get-Content -LiteralPath $AiPath -Raw

if($Preview.Length -gt 4000){
  $Preview = $Preview.Substring(0,4000) + "`n`n[preview truncated]"
}

Write-Host $Preview
Write-Host "--------------------------------"
