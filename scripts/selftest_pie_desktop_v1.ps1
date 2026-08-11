param([Parameter(Mandatory=$true)][string]$RepoRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$DesktopRoot = Join-Path $RepoRoot "desktop"
$Node = Get-Command node -ErrorAction SilentlyContinue
if($null -eq $Node){ throw "PIE_DESKTOP_SELFTEST_NODE_REQUIRED" }

foreach($Relative in @("package.json","forge.config.js","main.js","preload.js","runtime-workspace.js","scripts\stage-runtime.ps1","scripts\selftest-runtime-workspace.js")){
  if(-not (Test-Path -LiteralPath (Join-Path $DesktopRoot $Relative) -PathType Leaf)){ throw ("PIE_DESKTOP_SELFTEST_FILE_MISSING: " + $Relative) }
}
if(-not (Test-Path -LiteralPath (Join-Path $RepoRoot "scripts\verify_pie_desktop_release_v1.ps1") -PathType Leaf)){ throw "PIE_DESKTOP_SELFTEST_RELEASE_VERIFIER_MISSING" }

foreach($JavaScript in @("main.js","preload.js","forge.config.js","runtime-workspace.js","scripts\selftest-runtime-workspace.js")){
  & $Node.Source --check (Join-Path $DesktopRoot $JavaScript)
  if($LASTEXITCODE -ne 0){ throw ("PIE_DESKTOP_SELFTEST_JS_INVALID: " + $JavaScript) }
}

& $Node.Source (Join-Path $DesktopRoot "scripts\selftest-runtime-workspace.js")
if($LASTEXITCODE -ne 0){ throw "PIE_DESKTOP_SELFTEST_RUNTIME_WORKSPACE_FAILED" }

$Package = Get-Content -LiteralPath (Join-Path $DesktopRoot "package.json") -Raw | ConvertFrom-Json
if(
  [string]$Package.main -ne "main.js" -or
  [string]$Package.devDependencies.electron -ne "43.2.0" -or
  [string]$Package.devDependencies.'@electron-forge/cli' -ne "7.11.2" -or
  [string]$Package.devDependencies.'@electron-forge/maker-squirrel' -ne "7.11.2" -or
  [string]$Package.overrides.tar -ne "7.5.21" -or
  [string]$Package.overrides.tmp -ne "0.2.7"
){
  throw "PIE_DESKTOP_SELFTEST_PACKAGE_INVALID"
}

$Main = Get-Content -LiteralPath (Join-Path $DesktopRoot "main.js") -Raw
foreach($SecurityMarker in @("show: false","mainWindow.show()","contextIsolation: true","nodeIntegration: false","sandbox: true","setPermissionRequestHandler","setWindowOpenHandler","taskkill.exe")){
  if($Main -notmatch [regex]::Escape($SecurityMarker)){ throw ("PIE_DESKTOP_SELFTEST_SECURITY_MARKER_MISSING: " + $SecurityMarker) }
}
foreach($ReliabilityMarker in @("desktop.log","ready-to-show","did-finish-load","startup-fallback","render-process-gone","--smoke-test","pie.desktop.smoke.v1","getNativeWindowHandle","isVisible()")){
  if($Main -notmatch [regex]::Escape($ReliabilityMarker)){ throw ("PIE_DESKTOP_SELFTEST_RELIABILITY_MARKER_MISSING: " + $ReliabilityMarker) }
}
foreach($StateMarker in @("materializeRuntime","runtime.materialized","app.getPath('userData'), 'workspace'")){
  if($Main -notmatch [regex]::Escape($StateMarker)){ throw ("PIE_DESKTOP_SELFTEST_STATE_MARKER_MISSING: " + $StateMarker) }
}
foreach($BackupMarker in @("pie:choose-session-backup","Restore a PIE conversation backup","extensions: ['piebak']")){
  if($Main -notmatch [regex]::Escape($BackupMarker)){ throw ("PIE_DESKTOP_SELFTEST_BACKUP_MARKER_MISSING: " + $BackupMarker) }
}
$Preload = Get-Content -LiteralPath (Join-Path $DesktopRoot "preload.js") -Raw
if($Preload -notmatch [regex]::Escape("chooseSessionBackup: () => ipcRenderer.invoke('pie:choose-session-backup')")){ throw "PIE_DESKTOP_SELFTEST_BACKUP_IPC_MISSING" }
$Forge = Get-Content -LiteralPath (Join-Path $DesktopRoot "forge.config.js") -Raw
foreach($SigningMarker in @("PIE_WINDOWS_CERTIFICATE_FILE","PIE_WINDOWS_CERTIFICATE_PASSWORD","PIE_DESKTOP_SIGNING_CONFIGURATION_INCOMPLETE")){
  if($Forge -notmatch [regex]::Escape($SigningMarker)){ throw ("PIE_DESKTOP_SELFTEST_SIGNING_MARKER_MISSING: " + $SigningMarker) }
}

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $DesktopRoot "scripts\stage-runtime.ps1")
if($LASTEXITCODE -ne 0){ throw "PIE_DESKTOP_SELFTEST_STAGE_FAILED" }
foreach($Relative in @("pie.ps1","PIE_RELEASE_MANIFEST.json","workbench\server.js","workbench\public\pie-icon.png")){
  if(-not (Test-Path -LiteralPath (Join-Path $DesktopRoot ("runtime\" + $Relative)) -PathType Leaf)){
    throw ("PIE_DESKTOP_SELFTEST_RUNTIME_FILE_MISSING: " + $Relative)
  }
}

Write-Host "PIE_DESKTOP_SELFTEST_OK" -ForegroundColor Green
