param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$SessionId,
  [Parameter(Mandatory=$false)][string]$Model = "qwen2.5-coder:7b",
  [Parameter(Mandatory=$false)][ValidateSet("ollama","mock")][string]$Backend = "ollama"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
Write-Host "PIE_OFFLINE_PIPELINE_V1_START" -ForegroundColor DarkCyan

& (Join-Path $RepoRoot "scripts\pie_agent_start_v1.ps1") -RepoRoot $RepoRoot -SessionId $SessionId -Model $Model -Backend $Backend | Out-Host

Write-Host "PIE_OFFLINE_PIPELINE_V1_READY" -ForegroundColor Green
