param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$false)][string]$OutputDirectory = "",
  [Parameter(Mandatory=$false)][string]$Version = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
if([string]::IsNullOrWhiteSpace($OutputDirectory)){ $OutputDirectory = Join-Path $RepoRoot "dist" }
if([string]::IsNullOrWhiteSpace($Version)){ $Version = (Get-Date).ToUniversalTime().ToString("yyyy.MM.dd.HHmmss") }
if($Version -notmatch '^[0-9A-Za-z][0-9A-Za-z._-]{0,63}$'){ throw "PIE_PACKAGE_VERSION_INVALID" }

$RequiredFiles = @("pie.ps1","install.ps1","README.md","LICENSE.txt","models\PIE_MODEL_REGISTRY.v1.json","workbench\server.js","workbench\public\index.html")
foreach($Relative in $RequiredFiles){
  if(-not (Test-Path -LiteralPath (Join-Path $RepoRoot $Relative) -PathType Leaf)){ throw ("PIE_PACKAGE_REQUIRED_FILE_MISSING: " + $Relative) }
}

$IncludedRoots = @("scripts","workbench","schemas","adapters","engine","policies","profiles","rules","docs")
$Files = New-Object System.Collections.Generic.List[System.IO.FileInfo]
foreach($Name in @("pie.ps1","install.ps1","README.md","LICENSE.txt","LAW.md","SPEC.md","project.contract.json")){
  $Path = Join-Path $RepoRoot $Name
  if(Test-Path -LiteralPath $Path -PathType Leaf){ [void]$Files.Add((Get-Item -LiteralPath $Path)) }
}
foreach($RootName in $IncludedRoots){
  $RootPath = Join-Path $RepoRoot $RootName
  if(-not (Test-Path -LiteralPath $RootPath -PathType Container)){ continue }
  foreach($File in @(Get-ChildItem -LiteralPath $RootPath -File -Recurse | Where-Object {
    $_.FullName -notmatch '[\\/]scripts[\\/]_(archive|scratch)[\\/]' -and
    $_.Name -notlike ".env*" -and
    $_.Extension.ToLowerInvariant() -notin @(".zip",".7z",".bin",".gguf",".safetensors",".onnx",".pt",".pth",".ckpt",".log",".tmp",".pem",".key")
  })){ [void]$Files.Add($File) }
}
foreach($Relative in @("models\PIE_MODEL_REGISTRY.v1.json","models\.gitkeep","memory\PIE_MEMORY_REGISTRY.v1.json","memory\policy.json","memory\README.md")){
  $Path = Join-Path $RepoRoot $Relative
  if(Test-Path -LiteralPath $Path -PathType Leaf){ [void]$Files.Add((Get-Item -LiteralPath $Path)) }
}

$SortedFiles = @($Files.ToArray() | Sort-Object FullName -Unique)
if($SortedFiles.Count -lt 10){ throw "PIE_PACKAGE_FILE_SET_TOO_SMALL" }

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$StageParent = Join-Path $OutputDirectory (".pie_package_stage_" + [Guid]::NewGuid().ToString("N"))
$PackageName = "pie-" + $Version
$StageRoot = Join-Path $StageParent $PackageName
$ZipPath = Join-Path $OutputDirectory ($PackageName + ".zip")
$ChecksumPath = $ZipPath + ".sha256"
$Enc = New-Object System.Text.UTF8Encoding($false)

function Get-PieSha256([string]$Path){
  $Stream = [IO.File]::OpenRead($Path)
  $Hasher = [Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($Hasher.ComputeHash($Stream))).Replace("-","").ToLowerInvariant() }
  finally { $Hasher.Dispose(); $Stream.Dispose() }
}

try {
  New-Item -ItemType Directory -Force -Path $StageRoot | Out-Null
  $ManifestFiles = New-Object System.Collections.Generic.List[object]
  foreach($File in $SortedFiles){
    if(($File.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){ throw ("PIE_PACKAGE_LINK_NOT_ALLOWED: " + $File.FullName) }
    $Relative = $File.FullName.Substring($RepoRoot.Length).TrimStart("\")
    $Destination = Join-Path $StageRoot $Relative
    $DestinationDir = Split-Path -Parent $Destination
    if(-not (Test-Path -LiteralPath $DestinationDir -PathType Container)){ New-Item -ItemType Directory -Force -Path $DestinationDir | Out-Null }
    Copy-Item -LiteralPath $File.FullName -Destination $Destination -Force
    $Hash = Get-PieSha256 -Path $Destination
    [void]$ManifestFiles.Add([ordered]@{ path=$Relative.Replace("\","/"); bytes=[int64]$File.Length; sha256=$Hash })
  }

  $Manifest = [ordered]@{
    schema = "pie.release.manifest.v1"
    version = $Version
    created_utc = [DateTime]::UtcNow.ToString("o")
    entry_point = "pie.ps1"
    requirements = [ordered]@{ os="windows"; powershell="5.1+"; node="18+"; model_runtime="ollama" }
    files = @($ManifestFiles.ToArray())
  }
  $ManifestPath = Join-Path $StageRoot "PIE_RELEASE_MANIFEST.json"
  [System.IO.File]::WriteAllText($ManifestPath,(($Manifest | ConvertTo-Json -Depth 12) + "`n"),$Enc)

  if(Test-Path -LiteralPath $ZipPath -PathType Leaf){ Remove-Item -LiteralPath $ZipPath -Force }
  Compress-Archive -LiteralPath $StageRoot -DestinationPath $ZipPath -CompressionLevel Optimal
  $ArchiveHash = Get-PieSha256 -Path $ZipPath
  [System.IO.File]::WriteAllText($ChecksumPath,($ArchiveHash + "  " + [IO.Path]::GetFileName($ZipPath) + "`n"),$Enc)

  $Receipt = [ordered]@{ schema="pie.package.receipt.v1"; version=$Version; package=$ZipPath; sha256=$ArchiveHash; file_count=$SortedFiles.Count; status="ok" }
  Write-Host ("PIE_PACKAGE_OK: " + $ZipPath) -ForegroundColor Green
  Write-Host ("sha256: " + $ArchiveHash)
  Write-Output ($Receipt | ConvertTo-Json -Depth 6 -Compress)
}
finally {
  if(Test-Path -LiteralPath $StageParent -PathType Container){ Remove-Item -LiteralPath $StageParent -Recurse -Force }
}
