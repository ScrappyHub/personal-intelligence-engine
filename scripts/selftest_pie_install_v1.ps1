param([Parameter(Mandatory=$true)][string]$RepoRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$TestRoot = Join-Path $RepoRoot "runs\pie_install_selftest"
$OutputRoot = Join-Path $TestRoot "packages"
$InstallRoot = Join-Path $TestRoot "installed"
$Version = "selftest.1"
if(Test-Path -LiteralPath $TestRoot -PathType Container){ Remove-Item -LiteralPath $TestRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_package_v1.ps1") `
  -RepoRoot $RepoRoot -OutputDirectory $OutputRoot -Version $Version | Out-Host
if($LASTEXITCODE -ne 0){ throw "PIE_INSTALL_SELFTEST_PACKAGE_FAIL" }

$Package = Join-Path $OutputRoot ("pie-" + $Version + ".zip")
$Sidecar = $Package + ".sha256"
if(-not (Test-Path -LiteralPath $Package -PathType Leaf) -or -not (Test-Path -LiteralPath $Sidecar -PathType Leaf)){
  throw "PIE_INSTALL_SELFTEST_PACKAGE_OUTPUT_MISSING"
}
$ExpectedHash = ((Get-Content -LiteralPath $Sidecar -Raw).Trim() -split '\s+')[0]
if($ExpectedHash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $Package).Hash.ToLowerInvariant()){
  throw "PIE_INSTALL_SELFTEST_PACKAGE_HASH_BAD"
}

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "install.ps1") -PackagePath $Package -InstallRoot $InstallRoot | Out-Host
if($LASTEXITCODE -ne 0){ throw "PIE_INSTALL_SELFTEST_INSTALL_FAIL" }

$CurrentPath = Join-Path $InstallRoot "current.json"
$Launcher = Join-Path $InstallRoot "bin\pie.ps1"
if(-not (Test-Path -LiteralPath $CurrentPath -PathType Leaf) -or -not (Test-Path -LiteralPath $Launcher -PathType Leaf)){
  throw "PIE_INSTALL_SELFTEST_INSTALL_OUTPUT_MISSING"
}
$Current = Get-Content -LiteralPath $CurrentPath -Raw | ConvertFrom-Json
if([string]$Current.version -ne $Version -or -not (Test-Path -LiteralPath ([string]$Current.root) -PathType Container)){
  throw "PIE_INSTALL_SELFTEST_CURRENT_BAD"
}
$Manifest = Get-Content -LiteralPath (Join-Path ([string]$Current.root) "PIE_RELEASE_MANIFEST.json") -Raw | ConvertFrom-Json
if([string]$Manifest.schema -ne "pie.release.manifest.v1" -or @($Manifest.files).Count -lt 10){
  throw "PIE_INSTALL_SELFTEST_MANIFEST_BAD"
}
$Help = @(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Launcher help) -join "`n"
if($LASTEXITCODE -ne 0 -or $Help -notmatch "Personal Intelligence Engine"){
  throw "PIE_INSTALL_SELFTEST_LAUNCHER_FAIL"
}

$BadHashRejected = $false
try {
  & (Join-Path $RepoRoot "install.ps1") -PackagePath $Package -Sha256 ("0" * 64) -InstallRoot (Join-Path $TestRoot "bad_hash") | Out-Null
}
catch { if($_.Exception.Message -like "PIE_INSTALL_ARCHIVE_HASH_MISMATCH:*"){ $BadHashRejected = $true } }
if(-not $BadHashRejected){ throw "PIE_INSTALL_SELFTEST_BAD_HASH_ALLOWED" }

$ExistingRejected = $false
try { & (Join-Path $RepoRoot "install.ps1") -PackagePath $Package -InstallRoot $InstallRoot | Out-Null }
catch { if($_.Exception.Message -like "PIE_INSTALL_VERSION_EXISTS:*"){ $ExistingRejected = $true } }
if(-not $ExistingRejected){ throw "PIE_INSTALL_SELFTEST_EXISTING_VERSION_REPLACED" }

Write-Host "PIE_INSTALL_SELFTEST_OK" -ForegroundColor Green
