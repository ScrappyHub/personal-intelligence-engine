param(
  [Parameter(Mandatory=$true)][string]$TargetRepo,
  [Parameter(Mandatory=$false)][string]$Project = "active",
  [Parameter(Mandatory=$false)][string]$Intent = "coding"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$TargetRepo = (Resolve-Path -LiteralPath $TargetRepo).Path
$PieRoot = Join-Path $TargetRepo ".pie"

New-Item -ItemType Directory -Force -Path $PieRoot | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $PieRoot "memory") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $PieRoot "rules") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $PieRoot "receipts") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $PieRoot "conversations") | Out-Null

$Enc = New-Object System.Text.UTF8Encoding($false)
$Now = [DateTime]::UtcNow.ToString("o")

$Profile = @"
{
  "schema": "pie.repo.profile.v1",
  "project": "$Project",
  "intent": "$Intent",
  "created_utc": "$Now"
}
"@

[System.IO.File]::WriteAllText((Join-Path $PieRoot "profile.json"), ($Profile.Replace("`r`n","`n") + "`n"), $Enc)
[System.IO.File]::WriteAllText((Join-Path $PieRoot "memory\active.ndjson"), "", $Enc)
[System.IO.File]::WriteAllText((Join-Path $PieRoot "memory\project.ndjson"), "", $Enc)

$Receipt = '{"ts":"' + $Now + '","event":"PIE_REPO_INIT","project":"' + $Project + '","intent":"' + $Intent + '"}' + "`n"
[System.IO.File]::AppendAllText((Join-Path $PieRoot "receipts\init.ndjson"), $Receipt, $Enc)

Write-Host ("PIE_REPO_INIT_OK: " + $PieRoot) -ForegroundColor Green