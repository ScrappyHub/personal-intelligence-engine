param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$DesktopRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $DesktopRoot "..")).Path
$StageRoot = Join-Path $DesktopRoot "runtime"
$TempRoot = Join-Path ([IO.Path]::GetTempPath()) ("pie_desktop_stage_" + [Guid]::NewGuid().ToString("N"))

try {
  New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null
  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $RepoRoot "scripts\pie_package_v1.ps1") -RepoRoot $RepoRoot -OutputDirectory $TempRoot -Version "desktop"
  if($LASTEXITCODE -ne 0){ throw "PIE_DESKTOP_RUNTIME_PACKAGE_FAILED" }
  $Archive = Get-ChildItem -LiteralPath $TempRoot -File -Filter "pie-desktop.zip" | Select-Object -First 1
  if($null -eq $Archive){ throw "PIE_DESKTOP_RUNTIME_ARCHIVE_MISSING" }
  $Expanded = Join-Path $TempRoot "expanded"
  Expand-Archive -LiteralPath $Archive.FullName -DestinationPath $Expanded -Force
  $Source = Join-Path $Expanded "pie-desktop"
  if(-not (Test-Path -LiteralPath $Source -PathType Container)){ throw "PIE_DESKTOP_RUNTIME_ROOT_MISSING" }
  if(Test-Path -LiteralPath $StageRoot -PathType Container){ Remove-Item -LiteralPath $StageRoot -Recurse -Force }
  Move-Item -LiteralPath $Source -Destination $StageRoot
  Write-Host ("PIE_DESKTOP_RUNTIME_STAGED: " + $StageRoot) -ForegroundColor Green
}
finally {
  if(Test-Path -LiteralPath $TempRoot -PathType Container){ Remove-Item -LiteralPath $TempRoot -Recurse -Force }
}
