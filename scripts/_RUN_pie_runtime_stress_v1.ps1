param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$false)][int]$Iterations = 50
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

Write-Host "PIE_RUNTIME_STRESS_V1_START" -ForegroundColor DarkCyan

& (Join-Path $RepoRoot "scripts\_selftest_pie_agent_offline_v1.ps1") `
  -RepoRoot $RepoRoot | Out-Host

& (Join-Path $RepoRoot "scripts\_RUN_pie_agent_stress_v1.ps1") `
  -RepoRoot $RepoRoot `
  -Iterations $Iterations | Out-Host

Write-Host "PIE_RUNTIME_STRESS_COMPLETE" -ForegroundColor Green