param([Parameter(Mandatory=$true)][string]$RepoRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$RegistryPath = Join-Path $RepoRoot "policies\PIE_CAPABILITY_REGISTRY.v1.json"
if(-not (Test-Path -LiteralPath $RegistryPath -PathType Leaf)){ throw "PIE_CAPABILITY_REGISTRY_MISSING" }
try { $Registry = Get-Content -LiteralPath $RegistryPath -Raw | ConvertFrom-Json }
catch { throw ("PIE_CAPABILITY_REGISTRY_INVALID: " + $_.Exception.Message) }

Write-Host "PIE AGENT CAPABILITIES" -ForegroundColor Cyan
foreach($Capability in @($Registry.capabilities)){
  $Confirm = if([bool]$Capability.requires_confirmation){ "confirmation required" } else { "read-only auto-confirm eligible" }
  Write-Output ([string]$Capability.id + " :: " + [string]$Capability.name + " :: " + $Confirm)
}
Write-Host "PIE_CAPABILITY_LIST_OK" -ForegroundColor Green
