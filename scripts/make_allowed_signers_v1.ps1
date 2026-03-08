param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
. (Join-Path $RepoRoot "scripts\_lib_neverlost_v1.ps1")
[void](NL_MakeAllowedSigners $RepoRoot)
Write-Host "OK: allowed_signers regenerated" -ForegroundColor Green
