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
  param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)][string]$Text)
  $Dir = Split-Path -Parent $Path
  if(-not (Test-Path -LiteralPath $Dir -PathType Container)){ New-Item -ItemType Directory -Force -Path $Dir | Out-Null }
  $Clean = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $Clean.EndsWith("`n")){ $Clean += "`n" }
  [System.IO.File]::WriteAllText($Path,$Clean,$Enc)
}

function Get-FileSha256 {
  param([Parameter(Mandatory=$true)][string]$Path)
  $Sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $Stream = [System.IO.File]::OpenRead($Path)
    try { $Hash = $Sha.ComputeHash($Stream) } finally { $Stream.Dispose() }
    return (($Hash | ForEach-Object { $_.ToString("x2") }) -join "")
  } finally { $Sha.Dispose() }
}

function Test-SafeRelativePath {
  param([Parameter(Mandatory=$true)][string]$RelativePath)

  if([string]::IsNullOrWhiteSpace($RelativePath)){ return $false }
  if($RelativePath -match '^[a-zA-Z]:'){ return $false }
  if($RelativePath -match ':'){ return $false }
  if($RelativePath.Contains([char]0xFFFD)){ return $false }

  foreach($C in $RelativePath.ToCharArray()){
    if([int][char]$C -lt 32){ return $false }
  }

  if($RelativePath -match '(^|\\)\.\.(\\|$)'){ return $false }

  return $true
}

if([string]::IsNullOrWhiteSpace($Project)){ $Project = Split-Path -Leaf $TargetRepo }

$PieRoot = Join-Path $TargetRepo ".pie"
$ScanRoot = Join-Path $PieRoot "scan"
$ArtifactRoot = Join-Path $ScanRoot "artifacts"
$Stamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
$ThisScan = Join-Path $ArtifactRoot $Stamp

New-Item -ItemType Directory -Force -Path $ThisScan | Out-Null

$IgnoreDirs = @(".git","node_modules","dist","build","bin","obj",".next",".venv","venv","__pycache__",".pie",".nfl-keytest")

$AllFiles = @(Get-ChildItem -LiteralPath $TargetRepo -Recurse -File -ErrorAction SilentlyContinue | Sort-Object FullName)
$Files = New-Object System.Collections.Generic.List[object]

foreach($File in $AllFiles){
  $Full = [string]$File.FullName
  $Keep = $true
  foreach($Dir in $IgnoreDirs){
    if($Full -like ("*\" + $Dir + "\*")){ $Keep = $false }
  }
  if($Keep){ [void]$Files.Add($File) }
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
  if([string]::IsNullOrWhiteSpace($Ext)){ $Ext = "[no_ext]" }
  if(-not $ExtGroups.ContainsKey($Ext)){ $ExtGroups[$Ext] = 0 }
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
  foreach($Item in @($Prev.files)){ $PrevMap[[string]$Item.path] = [string]$Item.sha256 }

  $NowMap = @{}
  foreach($Item in @($Records.ToArray())){ $NowMap[[string]$Item.path] = [string]$Item.sha256 }

  foreach($P in @($NowMap.Keys | Sort-Object)){
    if(-not $PrevMap.ContainsKey($P)){ [void]$DiffLines.Add("ADDED " + $P) }
    elseif($PrevMap[$P] -ne $NowMap[$P]){ [void]$DiffLines.Add("CHANGED " + $P) }
  }

  foreach($P in @($PrevMap.Keys | Sort-Object)){
    if(-not $NowMap.ContainsKey($P)){ [void]$DiffLines.Add("REMOVED " + $P) }
  }
} else {
  [void]$DiffLines.Add("BASELINE_SCAN_NO_PREVIOUS")
}

$DiffPath = Join-Path $ThisScan "diff.txt"
Write-Utf8NoBomLf -Path $DiffPath -Text ($DiffLines.ToArray() -join "`n")

$CandidateDocs = New-Object System.Collections.Generic.List[object]

foreach($File in @($Files.ToArray())){
  $FullName = [string]$File.FullName
  if(-not $FullName.StartsWith($TargetRepo,[System.StringComparison]::OrdinalIgnoreCase)){ continue }

  $Rel = $FullName.Substring($TargetRepo.Length).TrimStart("\")
  if(-not (Test-SafeRelativePath -RelativePath $Rel)){ continue }

  if($File.Name -match '(README|WBS|SPEC|ROADMAP|PLAN|ARCHITECTURE|TODO|CHANGELOG|CONSTITUTION|LAW|DESIGN)'){
    if(@($CandidateDocs.ToArray()).Count -lt 15){ [void]$CandidateDocs.Add($File) }
  }
}

$DocText = New-Object System.Collections.Generic.List[string]

foreach($Doc in @($CandidateDocs.ToArray())){
  $DocFull = [string]$Doc.FullName
  $DocRel = $DocFull.Substring($TargetRepo.Length).TrimStart("\")
  [void]$DocText.Add("FILE: " + $DocRel)

  try {
    $Raw = Get-Content -LiteralPath $DocFull -Raw -ErrorAction Stop
    if($Raw.Length -gt 2500){ $Raw = $Raw.Substring(0,2500) }
    [void]$DocText.Add($Raw)
  }
  catch { [void]$DocText.Add("UNREADABLE_DOC") }

  [void]$DocText.Add("")
}

$ExtSummaryLines = New-Object System.Collections.Generic.List[string]
foreach($Key in @($ExtGroups.Keys | Sort-Object)){
  [void]$ExtSummaryLines.Add(([string]$Key) + "=" + ([string]$ExtGroups[$Key]))
}

$TopExtLines = @($ExtSummaryLines.ToArray() | Select-Object -First 30)
$DocPathLines = New-Object System.Collections.Generic.List[string]

foreach($Doc in @($CandidateDocs.ToArray())){
  $DocFull = [string]$Doc.FullName

  if($DocFull.StartsWith($TargetRepo,[System.StringComparison]::OrdinalIgnoreCase)){
    $DocRel = $DocFull.Substring($TargetRepo.Length).TrimStart("\")
    if(Test-SafeRelativePath -RelativePath $DocRel){
      [void]$DocPathLines.Add($DocRel)
    }
  }
}

$ReadmePath = Join-Path $TargetRepo "README.md"
$DeterministicFacts = New-Object System.Collections.Generic.List[string]

[void]$DeterministicFacts.Add("# Deterministic Repo Facts")
[void]$DeterministicFacts.Add("")
[void]$DeterministicFacts.Add("project=" + $Project)
[void]$DeterministicFacts.Add("repo=" + $TargetRepo)
[void]$DeterministicFacts.Add("file_count=" + [string]@($Records.ToArray()).Count)
[void]$DeterministicFacts.Add("")

if(Test-Path -LiteralPath $ReadmePath -PathType Leaf){
  $ReadmeText = Get-Content -LiteralPath $ReadmePath -Raw
  $ReadmeShort = $ReadmeText
  if($ReadmeShort.Length -gt 3000){
    $ReadmeShort = $ReadmeShort.Substring(0,3000)
  }

  [void]$DeterministicFacts.Add("## README.md excerpt")
  [void]$DeterministicFacts.Add($ReadmeShort)
  [void]$DeterministicFacts.Add("")
}

[void]$DeterministicFacts.Add("## Top extensions")
foreach($Line in @($ExtSummaryLines.ToArray() | Select-Object -First 20)){
  [void]$DeterministicFacts.Add($Line)
}

[void]$DeterministicFacts.Add("")
[void]$DeterministicFacts.Add("## Candidate docs")
foreach($Doc in @($CandidateDocs.ToArray())){
  $DocFull = [string]$Doc.FullName
  if($DocFull.StartsWith($TargetRepo,[System.StringComparison]::OrdinalIgnoreCase)){
    $DocRel = $DocFull.Substring($TargetRepo.Length).TrimStart("\")
    if(Test-SafeRelativePath -RelativePath $DocRel){
      [void]$DeterministicFacts.Add("- " + $DocRel)
    }
  }
}

$DeterministicFactsPath = Join-Path $ThisScan "deterministic_repo_facts.md"
Write-Utf8NoBomLf -Path $DeterministicFactsPath -Text ($DeterministicFacts.ToArray() -join "`n")

$DeterministicFactsText = $DeterministicFacts.ToArray() -join "`n"

$Prompt = @"
You are PIE creating a repo-level intelligence artifact. The deterministic repo facts are authoritative.

Return MARKDOWN ONLY.

Rules:
- Do not invent files.
- Do not summarize a single script as if it is the whole repo.
- Use the deterministic repo facts first. If README identifies the project, that identity overrides guesses from the repo name.
- Describe what this repository appears to be at a project level.
- List likely languages/stacks.
- List important docs found by relative path only.
- List changes since previous scan.
- Include "What PIE should remember".
- Include "Recommended next read targets".
- State uncertainty clearly.
- AI is assistant only, not executor.

DETERMINISTIC REPO FACTS:
$DeterministicFactsText

PROJECT:
$Project

REPO:
$TargetRepo

INVENTORY FILE COUNT:
$(@($Records.ToArray()).Count)

TOP EXTENSION COUNTS:
$($TopExtLines -join "`n")

DIFF:
$($DiffLines.ToArray() -join "`n")

CANDIDATE DOC PATHS:
$($DocPathLines.ToArray() -join "`n")
"@

$PromptPath = Join-Path $ThisScan "ai_prompt.txt"
Write-Utf8NoBomLf -Path $PromptPath -Text $Prompt

$Backend = Join-Path $RepoRoot "scripts\pie_backend_ollama_cmd_v1.ps1"
if(-not (Test-Path -LiteralPath $Backend -PathType Leaf)){ throw "PIE_BACKEND_SCRIPT_MISSING" }

$AiOut = Join-Path $ThisScan "ai_backend_stdout.txt"
$AiErr = Join-Path $ThisScan "ai_backend_stderr.txt"

$AiArgs = @(
  "-NoProfile",
  "-NonInteractive",
  "-ExecutionPolicy","Bypass",
  "-File",$Backend,
  "-Model",$Model,
  "-MessagePath",$PromptPath
)

$Proc = Start-Process -FilePath "powershell.exe" -ArgumentList $AiArgs -NoNewWindow -PassThru -RedirectStandardOutput $AiOut -RedirectStandardError $AiErr
$TimeoutSeconds = 120

if(-not $Proc.WaitForExit($TimeoutSeconds * 1000)){
  try { $Proc.Kill() } catch { }
  $AiText = "PIE repo scan AI description timed out after " + [string]$TimeoutSeconds + " seconds.`n`nUse inventory.json, diff.txt, and ai_prompt.txt as authoritative scan artifacts."
}
else {
  if($Proc.ExitCode -ne 0){
    $ErrText = ""
    if(Test-Path -LiteralPath $AiErr -PathType Leaf){ $ErrText = Get-Content -LiteralPath $AiErr -Raw }
    $AiText = "PIE repo scan AI description failed.`n`n" + $ErrText
  }
  else {
    $AiText = ""
    if(Test-Path -LiteralPath $AiOut -PathType Leaf){ $AiText = Get-Content -LiteralPath $AiOut -Raw }
    if([string]::IsNullOrWhiteSpace($AiText)){ $AiText = "PIE repo scan completed, but AI description output was empty." }
  }
}

$AiPath = Join-Path $ThisScan "ai_repo_description.md"

$DeterministicDescription = New-Object System.Collections.Generic.List[string]
[void]$DeterministicDescription.Add("# PIE Repo Intelligence Artifact")
[void]$DeterministicDescription.Add("")
[void]$DeterministicDescription.Add("## Deterministic Summary")
[void]$DeterministicDescription.Add("")
[void]$DeterministicDescription.Add("- Project: " + $Project)
[void]$DeterministicDescription.Add("- Repo: " + $TargetRepo)
[void]$DeterministicDescription.Add("- File count: " + [string]@($Records.ToArray()).Count)
[void]$DeterministicDescription.Add("- Scan ID: " + $Stamp)
[void]$DeterministicDescription.Add("")
[void]$DeterministicDescription.Add("## Known Identity")
[void]$DeterministicDescription.Add("")

if(Test-Path -LiteralPath (Join-Path $TargetRepo "README.md") -PathType Leaf){
  $ReadmeText = Get-Content -LiteralPath (Join-Path $TargetRepo "README.md") -Raw
  if($ReadmeText -match "Never Forgetting Ledger"){
    [void]$DeterministicDescription.Add("This repository identifies itself as Never Forgetting Ledger (NFL), a witness-only hash/integrity ledger.")
  }
  else {
    [void]$DeterministicDescription.Add("README.md exists. Project identity should be derived from README.md before model guesses.")
  }
}
else {
  [void]$DeterministicDescription.Add("No README.md found at repo root.")
}

[void]$DeterministicDescription.Add("")
[void]$DeterministicDescription.Add("## Top Extensions")
foreach($Line in @($ExtSummaryLines.ToArray() | Select-Object -First 25)){
  [void]$DeterministicDescription.Add("- " + $Line)
}

[void]$DeterministicDescription.Add("")
[void]$DeterministicDescription.Add("## Candidate Docs")
foreach($Doc in @($CandidateDocs.ToArray())){
  $DocFull = [string]$Doc.FullName
  if($DocFull.StartsWith($TargetRepo,[System.StringComparison]::OrdinalIgnoreCase)){
    $DocRel = $DocFull.Substring($TargetRepo.Length).TrimStart("\")
    if(Test-SafeRelativePath -RelativePath $DocRel){
      [void]$DeterministicDescription.Add("- " + $DocRel)
    }
  }
}

[void]$DeterministicDescription.Add("")
[void]$DeterministicDescription.Add("## Diff Since Previous Scan")
foreach($Line in @($DiffLines.ToArray())){
  [void]$DeterministicDescription.Add("- " + $Line)
}

[void]$DeterministicDescription.Add("")
[void]$DeterministicDescription.Add("## AI Assistant Notes")
[void]$DeterministicDescription.Add("")
if([string]::IsNullOrWhiteSpace($AiText)){
  [void]$DeterministicDescription.Add("AI description unavailable or empty. Deterministic facts above are authoritative.")
}
elseif($AiText -match "failed" -or $AiText -match "timed out"){
  [void]$DeterministicDescription.Add($AiText)
}
else {
  [void]$DeterministicDescription.Add($AiText)
}

Write-Utf8NoBomLf -Path $AiPath -Text ($DeterministicDescription.ToArray() -join "`n")

$Artifact = [ordered]@{
  schema = "pie.repo.scan.artifact.v1"
  project = $Project
  target_repo = $TargetRepo
  scan_id = $Stamp
  inventory = $InventoryPath
  diff = $DiffPath
  deterministic_facts = $DeterministicFactsPath
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
if($Preview.Length -gt 4000){ $Preview = $Preview.Substring(0,4000) + "`n`n[preview truncated]" }

Write-Host $Preview
Write-Host "--------------------------------"



