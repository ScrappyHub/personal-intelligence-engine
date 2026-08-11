param([Parameter(Mandatory=$true)][string]$RepoRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Script = Join-Path $RepoRoot "scripts\pie_integrations_v1.ps1"
$Names = @("SUPABASE_ACCESS_TOKEN","FIGMA_ACCESS_TOKEN","VERCEL_TOKEN","CLOUDFLARE_API_TOKEN")
$Original = @{}

foreach($Name in $Names){
  $Original[$Name] = [Environment]::GetEnvironmentVariable($Name,"Process")
  [Environment]::SetEnvironmentVariable($Name,("secret-selftest-" + $Name),"Process")
}

try {
  $Status = @(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Script -RepoRoot $RepoRoot -Action status) -join "`n"
  if($LASTEXITCODE -ne 0){ throw "PIE_INTEGRATIONS_SELFTEST_STATUS_FAIL" }
  foreach($Name in $Names){
    if($Status -notmatch [regex]::Escape($Name)){ throw ("PIE_INTEGRATIONS_SELFTEST_ENV_MISSING: " + $Name) }
    if($Status -match [regex]::Escape("secret-selftest-" + $Name)){ throw ("PIE_INTEGRATIONS_SELFTEST_SECRET_LEAK: " + $Name) }
  }

  [Environment]::SetEnvironmentVariable("FIGMA_ACCESS_TOKEN",$null,"Process")
  $PreviousErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  $Verify = @(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Script -RepoRoot $RepoRoot -Action verify -Provider figma 2>&1) -join "`n"
  $VerifyExitCode = $LASTEXITCODE
  $ErrorActionPreference = $PreviousErrorActionPreference

  if($VerifyExitCode -eq 0){ throw "PIE_INTEGRATIONS_SELFTEST_MISSING_TOKEN_ACCEPTED" }
  if($Verify -notmatch "PIE_INTEGRATION_UNAVAILABLE"){ throw "PIE_INTEGRATIONS_SELFTEST_UNAVAILABLE_MISSING" }
}
finally {
  foreach($Name in $Names){ [Environment]::SetEnvironmentVariable($Name,$Original[$Name],"Process") }
}

Write-Host "PIE_INTEGRATIONS_SELFTEST_OK" -ForegroundColor Green
