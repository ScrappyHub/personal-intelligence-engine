param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$false)][switch]$AllowUnsigned
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$DesktopRoot = Join-Path $RepoRoot "desktop"
$OutRoot = Join-Path $DesktopRoot "release"
$AppRoot = Join-Path $OutRoot "PIE-win32-x64"
$MakeRoot = Join-Path $OutRoot "make\squirrel.windows\x64"
$Setup = Join-Path $MakeRoot "PIE-Setup.exe"
$Nuget = Join-Path $MakeRoot "pie_desktop-0.1.0-full.nupkg"
$Releases = Join-Path $MakeRoot "RELEASES"
$Executable = Join-Path $AppRoot "PIE.exe"
$RuntimeRoot = Join-Path $AppRoot "resources\runtime"
$ManifestPath = Join-Path $RuntimeRoot "PIE_RELEASE_MANIFEST.json"
$Enc = New-Object System.Text.UTF8Encoding($false)
$SecurityModule = Join-Path $PSHOME "Modules\Microsoft.PowerShell.Security\Microsoft.PowerShell.Security.psd1"
if(-not (Test-Path -LiteralPath $SecurityModule -PathType Leaf)){ throw "PIE_DESKTOP_RELEASE_SECURITY_MODULE_MISSING" }
Import-Module -Name $SecurityModule -Force

function Get-PieSha256([string]$Path){
  $Stream = [IO.File]::OpenRead($Path)
  $Hasher = [Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($Hasher.ComputeHash($Stream))).Replace("-","").ToLowerInvariant() }
  finally { $Hasher.Dispose(); $Stream.Dispose() }
}

foreach($Required in @($Setup,$Nuget,$Releases,$Executable,$ManifestPath)){
  if(-not (Test-Path -LiteralPath $Required -PathType Leaf)){ throw ("PIE_DESKTOP_RELEASE_FILE_MISSING: " + $Required) }
}
if((Get-Item -LiteralPath $Setup).Length -lt 50MB){ throw "PIE_DESKTOP_RELEASE_SETUP_TOO_SMALL" }
if((Get-Item -LiteralPath $Executable).Length -lt 50MB){ throw "PIE_DESKTOP_RELEASE_EXECUTABLE_TOO_SMALL" }

$Manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
if([string]$Manifest.schema -ne "pie.release.manifest.v1" -or @($Manifest.files).Count -lt 10){ throw "PIE_DESKTOP_RELEASE_MANIFEST_INVALID" }
$ManifestSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach($Entry in @($Manifest.files)){
  $Relative = ([string]$Entry.path).Replace("/","\")
  if([IO.Path]::IsPathRooted($Relative) -or $Relative -match '(^|[\/])\.\.([\/]|$)'){ throw ("PIE_DESKTOP_RELEASE_MANIFEST_PATH_UNSAFE: " + $Relative) }
  $Candidate = [IO.Path]::GetFullPath((Join-Path $RuntimeRoot $Relative))
  if(-not $Candidate.StartsWith(([IO.Path]::GetFullPath($RuntimeRoot) + [IO.Path]::DirectorySeparatorChar),[StringComparison]::OrdinalIgnoreCase)){ throw ("PIE_DESKTOP_RELEASE_MANIFEST_PATH_ESCAPE: " + $Relative) }
  if(-not (Test-Path -LiteralPath $Candidate -PathType Leaf)){ throw ("PIE_DESKTOP_RELEASE_RUNTIME_FILE_MISSING: " + $Relative) }
  if((Get-Item -LiteralPath $Candidate).Length -ne [int64]$Entry.bytes){ throw ("PIE_DESKTOP_RELEASE_RUNTIME_SIZE_MISMATCH: " + $Relative) }
  if((Get-PieSha256 -Path $Candidate) -ne ([string]$Entry.sha256).ToLowerInvariant()){ throw ("PIE_DESKTOP_RELEASE_RUNTIME_HASH_MISMATCH: " + $Relative) }
  [void]$ManifestSet.Add($Relative)
}
foreach($RuntimeFile in @(Get-ChildItem -LiteralPath $RuntimeRoot -File -Recurse)){
  $Relative = $RuntimeFile.FullName.Substring($RuntimeRoot.Length).TrimStart("\")
  if($Relative -eq "PIE_RELEASE_MANIFEST.json"){ continue }
  if(-not $ManifestSet.Contains($Relative)){ throw ("PIE_DESKTOP_RELEASE_RUNTIME_FILE_UNMANIFESTED: " + $Relative) }
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$Archive = [IO.Compression.ZipFile]::OpenRead($Nuget)
try {
  if($Archive.Entries.Count -lt 3 -or -not @($Archive.Entries | Where-Object { $_.FullName -match '^lib[/\\]net45[/\\].+\.exe$' }).Count){ throw "PIE_DESKTOP_RELEASE_NUGET_INVALID" }
}
finally { $Archive.Dispose() }

$SetupSignature = Get-AuthenticodeSignature -LiteralPath $Setup
$ExecutableSignature = Get-AuthenticodeSignature -LiteralPath $Executable
if(-not $AllowUnsigned -and ($SetupSignature.Status -ne "Valid" -or $ExecutableSignature.Status -ne "Valid")){ throw "PIE_DESKTOP_RELEASE_SIGNATURE_REQUIRED" }

$SetupHash = Get-PieSha256 -Path $Setup
$ExecutableHash = Get-PieSha256 -Path $Executable
$NugetHash = Get-PieSha256 -Path $Nuget
$Receipt = [ordered]@{
  schema = "pie.desktop.release.receipt.v1"
  version = "0.1.0"
  platform = "win32-x64"
  setup = [ordered]@{ path=$Setup; bytes=(Get-Item -LiteralPath $Setup).Length; sha256=$SetupHash; signature=[string]$SetupSignature.Status }
  executable = [ordered]@{ path=$Executable; bytes=(Get-Item -LiteralPath $Executable).Length; sha256=$ExecutableHash; signature=[string]$ExecutableSignature.Status }
  nuget = [ordered]@{ path=$Nuget; bytes=(Get-Item -LiteralPath $Nuget).Length; sha256=$NugetHash }
  runtime_manifest_sha256 = Get-PieSha256 -Path $ManifestPath
  runtime_file_count = @($Manifest.files).Count
  unsigned_development_release = [bool]($SetupSignature.Status -ne "Valid" -or $ExecutableSignature.Status -ne "Valid")
  verified_utc = [DateTime]::UtcNow.ToString("o")
  status = "ok"
}
$ReceiptPath = Join-Path $MakeRoot "PIE_DESKTOP_RELEASE.json"
[IO.File]::WriteAllText($ReceiptPath,(($Receipt | ConvertTo-Json -Depth 8) + "`n"),$Enc)
[IO.File]::WriteAllText(($Setup + ".sha256"),($SetupHash + "  PIE-Setup.exe`n"),$Enc)
Write-Host ("PIE_DESKTOP_RELEASE_OK: " + $Setup) -ForegroundColor Green
Write-Host ("sha256: " + $SetupHash)
Write-Host ("receipt: " + $ReceiptPath)
