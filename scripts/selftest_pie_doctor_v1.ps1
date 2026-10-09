param([Parameter(Mandatory=$true)][string]$RepoRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
& (Join-Path $RepoRoot "scripts\pie_doctor_v1.ps1") -RepoRoot $RepoRoot -HaaiRepo "C:\dev\haai" | Out-Null
$Report = Get-Content -LiteralPath (Join-Path $RepoRoot "runs\doctor\latest.json") -Raw | ConvertFrom-Json
if([string]$Report.schema -ne "pie.doctor.report.v1" -or $Report.release_ready -ne $false){ throw "PIE_DOCTOR_SELFTEST_REPORT_BAD" }
$Ids = @($Report.components | ForEach-Object { [string]$_.id })
foreach($Id in @("cli","memory","models","runtime","conversations","workbench","backups","desktop","hosted","integrations","haai")){
  if($Id -notin $Ids){ throw ("PIE_DOCTOR_SELFTEST_COMPONENT_MISSING: " + $Id) }
}
$FailedRequired = @($Report.components | Where-Object { $_.required -and $_.status -eq "failed" })
if($FailedRequired.Count){ throw "PIE_DOCTOR_SELFTEST_REQUIRED_FAILURE" }
$Desktop = @($Report.components | Where-Object { [string]$_.id -eq "desktop" }) | Select-Object -First 1
if($null -eq $Desktop -or $null -eq $Desktop.details.release_verified -or $null -eq $Desktop.details.release_signed){ throw "PIE_DOCTOR_SELFTEST_DESKTOP_RELEASE_STATE_MISSING" }
$DesktopReceipt = Join-Path $RepoRoot "desktop\release\make\squirrel.windows\x64\PIE_DESKTOP_RELEASE.json"
if((Test-Path -LiteralPath $DesktopReceipt -PathType Leaf) -and $Desktop.details.release_verified -ne $true){ throw "PIE_DOCTOR_SELFTEST_DESKTOP_RECEIPT_NOT_RECOGNIZED" }
Write-Host "PIE_DOCTOR_SELFTEST_OK" -ForegroundColor Green
