param([Parameter(Mandatory=$true)][string]$RepoRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Output = Join-Path $RepoRoot "runs\hosted_build_selftest"
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $RepoRoot "scripts\pie_hosted_build_v1.ps1") -RepoRoot $RepoRoot -ApiBase "https://api.pie.invalid" -OutputDirectory $Output
if($LASTEXITCODE -ne 0){ throw "PIE_HOSTED_BUILD_SELFTEST_BUILD_FAILED" }
foreach($Name in @("index.html","styles.css","app.js","manifest.webmanifest","service-worker.js","pie-icon.png","_headers","vercel.json")){
  if(-not (Test-Path -LiteralPath (Join-Path $Output $Name) -PathType Leaf)){ throw ("PIE_HOSTED_BUILD_SELFTEST_FILE_MISSING: " + $Name) }
}
$Html = Get-Content -LiteralPath (Join-Path $Output "index.html") -Raw
if($Html -match '__PIE_(BOOTSTRAP_JSON|STYLES|APP_JS)__' -or $Html -notmatch 'https://api\.pie\.invalid' -or $Html -match 'requestToken'){ throw "PIE_HOSTED_BUILD_SELFTEST_BOOTSTRAP_BAD" }
$App = Get-Content -LiteralPath (Join-Path $Output "app.js") -Raw
foreach($Boundary in @("const isHosted = surface === 'hosted'","el.targetRepo.readOnly = true","el.catalogBlock.hidden = true","el.runtimeButton.hidden = isHosted || ready","el.backupButton.hidden = isHosted ||","if (!window.pieDesktop) return")){
  if($App -notmatch [regex]::Escape($Boundary)){ throw ("PIE_HOSTED_BUILD_SELFTEST_CAPABILITY_GUARD_MISSING: " + $Boundary) }
}
$Gateway = Get-Content -LiteralPath (Join-Path $RepoRoot "workbench\contracts\PIE_HOSTED_GATEWAY.v1.json") -Raw | ConvertFrom-Json
$Routes = @($Gateway.routes | ForEach-Object { ([string]$_.method).ToUpperInvariant() + " " + [string]$_.path })
if("POST /api/models/select" -notin $Routes -or "POST /api/runtime/install" -in $Routes -or "POST /api/models/pull" -in $Routes -or "POST /api/session/backup" -in $Routes -or "POST /api/session/restore" -in $Routes){ throw "PIE_HOSTED_BUILD_SELFTEST_GATEWAY_BOUNDARY_BAD" }
$Headers = Get-Content -LiteralPath (Join-Path $Output "_headers") -Raw
if($Headers -notmatch "connect-src 'self' https://api\.pie\.invalid" -or $Headers -notmatch "frame-ancestors 'none'"){ throw "PIE_HOSTED_BUILD_SELFTEST_HEADERS_BAD" }
Write-Host "PIE_HOSTED_BUILD_SELFTEST_OK" -ForegroundColor Green
