param(
  [Parameter(Mandatory=$false)][string]$PackagePath = "",
  [Parameter(Mandatory=$false)][string]$PackageUri = "",
  [Parameter(Mandatory=$false)][string]$Sha256 = "",
  [Parameter(Mandatory=$false)][string]$InstallRoot = "",
  [Parameter(Mandatory=$false)][switch]$AddToUserPath,
  [Parameter(Mandatory=$false)][switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$Enc = New-Object System.Text.UTF8Encoding($false)
if([string]::IsNullOrWhiteSpace($InstallRoot)){ $InstallRoot = Join-Path $env:LOCALAPPDATA "PIE" }
$InstallRoot = [IO.Path]::GetFullPath($InstallRoot)
if(-not [string]::IsNullOrWhiteSpace($PackagePath) -and -not [string]::IsNullOrWhiteSpace($PackageUri)){ throw "PIE_INSTALL_SOURCE_AMBIGUOUS" }
if([string]::IsNullOrWhiteSpace($PackagePath) -and [string]::IsNullOrWhiteSpace($PackageUri)){ throw "PIE_INSTALL_SOURCE_REQUIRED: provide -PackagePath or -PackageUri" }

$TempRoot = Join-Path ([IO.Path]::GetTempPath()) ("pie_install_" + [Guid]::NewGuid().ToString("N"))
$ArchivePath = Join-Path $TempRoot "pie-release.zip"
$ExtractRoot = Join-Path $TempRoot "expanded"
$StageRoot = ""
$Downloaded = $false

function Write-JsonFile([string]$Path,$Value){
  $Parent = Split-Path -Parent $Path
  if(-not (Test-Path -LiteralPath $Parent -PathType Container)){ New-Item -ItemType Directory -Force -Path $Parent | Out-Null }
  [System.IO.File]::WriteAllText($Path,(($Value | ConvertTo-Json -Depth 12) + "`n"),$Enc)
}

function Get-PieSha256([string]$Path){
  $Stream = [IO.File]::OpenRead($Path)
  $Hasher = [Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($Hasher.ComputeHash($Stream))).Replace("-","").ToLowerInvariant() }
  finally { $Hasher.Dispose(); $Stream.Dispose() }
}

function Get-ExpectedHash([string]$LocalPackage){
  if(-not [string]::IsNullOrWhiteSpace($Sha256)){ return $Sha256.Trim().ToLowerInvariant() }
  $Sidecar = $LocalPackage + ".sha256"
  if(Test-Path -LiteralPath $Sidecar -PathType Leaf){
    $First = ((Get-Content -LiteralPath $Sidecar -Raw).Trim() -split '\s+')[0]
    if($First -match '^[0-9a-fA-F]{64}$'){ return $First.ToLowerInvariant() }
  }
  throw "PIE_INSTALL_SHA256_REQUIRED: provide -Sha256 or place a .sha256 file beside the package"
}

try {
  New-Item -ItemType Directory -Force -Path $TempRoot,$ExtractRoot | Out-Null
  if(-not [string]::IsNullOrWhiteSpace($PackageUri)){
    if($PackageUri -notmatch '^https://'){ throw "PIE_INSTALL_URI_HTTPS_REQUIRED" }
    if($Sha256 -notmatch '^[0-9a-fA-F]{64}$'){ throw "PIE_INSTALL_REMOTE_SHA256_REQUIRED" }
    Write-Host "PIE_INSTALL_DOWNLOAD_START" -ForegroundColor Cyan
    Invoke-WebRequest -Uri $PackageUri -OutFile $ArchivePath -UseBasicParsing
    $Downloaded = $true
    Write-Host "PIE_INSTALL_DOWNLOAD_OK" -ForegroundColor Green
  }
  else {
    $PackagePath = (Resolve-Path -LiteralPath $PackagePath).Path
    if([IO.Path]::GetExtension($PackagePath).ToLowerInvariant() -ne ".zip"){ throw "PIE_INSTALL_PACKAGE_TYPE_INVALID: expected .zip" }
    Copy-Item -LiteralPath $PackagePath -Destination $ArchivePath -Force
  }

  $ExpectedHash = Get-ExpectedHash -LocalPackage $(if($Downloaded){ $ArchivePath } else { $PackagePath })
  if($ExpectedHash -notmatch '^[0-9a-f]{64}$'){ throw "PIE_INSTALL_SHA256_INVALID" }
  $ActualHash = Get-PieSha256 -Path $ArchivePath
  if($ActualHash -ne $ExpectedHash){ throw ("PIE_INSTALL_ARCHIVE_HASH_MISMATCH: expected=" + $ExpectedHash + " actual=" + $ActualHash) }
  Write-Host "PIE_INSTALL_ARCHIVE_VERIFIED" -ForegroundColor Green

  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $Archive = [System.IO.Compression.ZipFile]::OpenRead($ArchivePath)
  try {
    if($Archive.Entries.Count -gt 10000){ throw "PIE_INSTALL_ARCHIVE_ENTRY_LIMIT_EXCEEDED" }
    $SeenEntries = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $ExpandedBytes = 0L
    foreach($Entry in $Archive.Entries){
      $EntryName = [string]$Entry.FullName
      if([string]::IsNullOrWhiteSpace($EntryName)){ continue }
      $Normalized = $EntryName.Replace("/","\")
      if([IO.Path]::IsPathRooted($Normalized) -or $Normalized -match '(^|[\\/])\.\.([\\/]|$)'){
        throw ("PIE_INSTALL_ARCHIVE_PATH_UNSAFE: " + $EntryName)
      }
      $Destination = [IO.Path]::GetFullPath((Join-Path $ExtractRoot $Normalized))
      if(-not $Destination.StartsWith(([IO.Path]::GetFullPath($ExtractRoot) + [IO.Path]::DirectorySeparatorChar),[StringComparison]::OrdinalIgnoreCase)){
        throw ("PIE_INSTALL_ARCHIVE_PATH_ESCAPE: " + $EntryName)
      }
      if(-not $SeenEntries.Add($EntryName)){ throw ("PIE_INSTALL_ARCHIVE_DUPLICATE_ENTRY: " + $EntryName) }
      $ExpandedBytes += [int64]$Entry.Length
      if($ExpandedBytes -gt 2GB){ throw "PIE_INSTALL_ARCHIVE_EXPANDED_SIZE_LIMIT_EXCEEDED" }
    }
  }
  finally { $Archive.Dispose() }
  Expand-Archive -LiteralPath $ArchivePath -DestinationPath $ExtractRoot -Force
  $Manifests = @(Get-ChildItem -LiteralPath $ExtractRoot -File -Recurse -Filter "PIE_RELEASE_MANIFEST.json")
  if($Manifests.Count -ne 1){ throw ("PIE_INSTALL_MANIFEST_COUNT_INVALID: " + $Manifests.Count) }
  $ManifestPath = $Manifests[0].FullName
  $PackageRoot = Split-Path -Parent $ManifestPath
  $Manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
  if([string]$Manifest.schema -ne "pie.release.manifest.v1"){ throw "PIE_INSTALL_MANIFEST_SCHEMA_INVALID" }
  $Version = [string]$Manifest.version
  if($Version -notmatch '^[0-9A-Za-z][0-9A-Za-z._-]{0,63}$'){ throw "PIE_INSTALL_VERSION_INVALID" }
  if(@($Manifest.files).Count -lt 10){ throw "PIE_INSTALL_MANIFEST_FILE_SET_TOO_SMALL" }

  foreach($Entry in @($Manifest.files)){
    $Relative = ([string]$Entry.path).Replace("/","\")
    if([IO.Path]::IsPathRooted($Relative) -or $Relative -match '(^|[\\/])\.\.([\\/]|$)'){ throw ("PIE_INSTALL_MANIFEST_PATH_UNSAFE: " + $Relative) }
    $Candidate = [IO.Path]::GetFullPath((Join-Path $PackageRoot $Relative))
    if(-not $Candidate.StartsWith(([IO.Path]::GetFullPath($PackageRoot) + [IO.Path]::DirectorySeparatorChar),[StringComparison]::OrdinalIgnoreCase)){
      throw ("PIE_INSTALL_MANIFEST_PATH_ESCAPE: " + $Relative)
    }
    if(-not (Test-Path -LiteralPath $Candidate -PathType Leaf)){ throw ("PIE_INSTALL_FILE_MISSING: " + $Relative) }
    $FileHash = Get-PieSha256 -Path $Candidate
    if($FileHash -ne ([string]$Entry.sha256).ToLowerInvariant()){ throw ("PIE_INSTALL_FILE_HASH_MISMATCH: " + $Relative) }
    if((Get-Item -LiteralPath $Candidate).Length -ne [int64]$Entry.bytes){ throw ("PIE_INSTALL_FILE_SIZE_MISMATCH: " + $Relative) }
  }
  $ManifestSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  foreach($Entry in @($Manifest.files)){ [void]$ManifestSet.Add(([string]$Entry.path).Replace("/","\")) }
  foreach($PackageFile in @(Get-ChildItem -LiteralPath $PackageRoot -File -Recurse)){
    $PackageRelative = $PackageFile.FullName.Substring($PackageRoot.Length).TrimStart("\")
    if($PackageRelative -eq "PIE_RELEASE_MANIFEST.json"){ continue }
    if(-not $ManifestSet.Contains($PackageRelative)){ throw ("PIE_INSTALL_UNMANIFESTED_FILE: " + $PackageRelative) }
  }
  Write-Host ("PIE_INSTALL_CONTENT_VERIFIED: " + @($Manifest.files).Count + " files") -ForegroundColor Green

  $VersionsRoot = Join-Path $InstallRoot "versions"
  $FinalRoot = Join-Path $VersionsRoot $Version
  $StageRoot = Join-Path $VersionsRoot (".staging_" + [Guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Force -Path $VersionsRoot | Out-Null
  $BackupRoot = ""
  if(Test-Path -LiteralPath $FinalRoot){
    if(-not $Force){ throw ("PIE_INSTALL_VERSION_EXISTS: " + $Version + " (use -Force to replace it)") }
  }
  Copy-Item -LiteralPath $PackageRoot -Destination $StageRoot -Recurse
  try {
    if(Test-Path -LiteralPath $FinalRoot){
      $BackupRoot = Join-Path $VersionsRoot (".backup_" + [Guid]::NewGuid().ToString("N"))
      Move-Item -LiteralPath $FinalRoot -Destination $BackupRoot
    }
    Move-Item -LiteralPath $StageRoot -Destination $FinalRoot
    $StageRoot = ""
    if(-not [string]::IsNullOrWhiteSpace($BackupRoot)){ Remove-Item -LiteralPath $BackupRoot -Recurse -Force; $BackupRoot = "" }
  }
  catch {
    if(-not (Test-Path -LiteralPath $FinalRoot) -and -not [string]::IsNullOrWhiteSpace($BackupRoot) -and (Test-Path -LiteralPath $BackupRoot)){
      Move-Item -LiteralPath $BackupRoot -Destination $FinalRoot
      $BackupRoot = ""
    }
    throw
  }

  $BinRoot = Join-Path $InstallRoot "bin"
  New-Item -ItemType Directory -Force -Path $BinRoot | Out-Null
  $Current = [ordered]@{ schema="pie.install.current.v1"; version=$Version; root=$FinalRoot; package_sha256=$ActualHash; installed_utc=[DateTime]::UtcNow.ToString("o") }
  Write-JsonFile -Path (Join-Path $InstallRoot "current.json") -Value $Current

  $LauncherPs1 = @'
$ErrorActionPreference = "Stop"
$InstallRoot = Split-Path -Parent $PSScriptRoot
$Current = Get-Content -LiteralPath (Join-Path $InstallRoot "current.json") -Raw | ConvertFrom-Json
$Pie = Join-Path ([string]$Current.root) "pie.ps1"
if(-not (Test-Path -LiteralPath $Pie -PathType Leaf)){ throw "PIE_INSTALL_CURRENT_ENTRY_MISSING" }
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Pie @args
exit $LASTEXITCODE
'@
  [System.IO.File]::WriteAllText((Join-Path $BinRoot "pie.ps1"),($LauncherPs1.Replace("`r`n","`n") + "`n"),$Enc)
  [System.IO.File]::WriteAllText((Join-Path $BinRoot "pie.cmd"),("@echo off`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"%~dp0pie.ps1`" %*`r`n"),[System.Text.Encoding]::ASCII)

  if($AddToUserPath){
    $UserPath = [Environment]::GetEnvironmentVariable("Path","User")
    $Parts = @($UserPath -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if(-not ($Parts -contains $BinRoot)){
      [Environment]::SetEnvironmentVariable("Path",(($Parts + $BinRoot) -join ';'),"User")
      Write-Host "PIE_INSTALL_USER_PATH_UPDATED: open a new terminal" -ForegroundColor Green
    }
  }

  $Receipt = [ordered]@{ schema="pie.install.receipt.v1"; version=$Version; root=$FinalRoot; package_sha256=$ActualHash; status="ok"; installed_utc=[DateTime]::UtcNow.ToString("o") }
  $ReceiptPath = Join-Path $InstallRoot ("receipts\install_" + (Get-Date -Format "yyyyMMdd_HHmmss_fff") + ".json")
  Write-JsonFile -Path $ReceiptPath -Value $Receipt
  Write-Host ("PIE_INSTALL_OK: " + $FinalRoot) -ForegroundColor Green
  Write-Host ("launcher: " + (Join-Path $BinRoot "pie.cmd"))
  Write-Host ("receipt: " + $ReceiptPath)
}
finally {
  if(-not [string]::IsNullOrWhiteSpace($StageRoot) -and (Test-Path -LiteralPath $StageRoot -PathType Container)){ Remove-Item -LiteralPath $StageRoot -Recurse -Force }
  if(Test-Path -LiteralPath $TempRoot -PathType Container){ Remove-Item -LiteralPath $TempRoot -Recurse -Force }
}
