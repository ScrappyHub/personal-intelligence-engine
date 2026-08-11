param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$SessionId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $RepoRoot "scripts\_lib_pie_agent_session_v1.ps1")
$Session = PIE_GetAgentSession -RepoRoot $RepoRoot -SessionId $SessionId
$RunRoot = $Session.run_root

$Turns = @($Session.conversation_turns).Count
$Receipts = @(Get-Content -LiteralPath (Join-Path $RunRoot "execution\execution_receipts.ndjson") -ErrorAction SilentlyContinue | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count
$Proposals = @(Get-ChildItem -LiteralPath (Join-Path $RunRoot "execution") -File -Filter "proposal_*.json" -ErrorAction SilentlyContinue).Count

Write-Host "PIE AGENT SESSION" -ForegroundColor Cyan
Write-Host ("session: " + $SessionId)
Write-Host ("status: " + $Session.status)
Write-Host ("integrity: " + $Session.integrity)
Write-Host ("backend: " + $Session.backend)
Write-Host ("model: " + $Session.model)
Write-Host ("project repo: " + $Session.project_repo)
Write-Host ("goal: " + $Session.goal)
Write-Host ("conversation turns: " + [string]$Turns)
Write-Host ("execution proposals: " + [string]$Proposals)
Write-Host ("execution receipts: " + [string]$Receipts)
Write-Host ("artifacts: " + $RunRoot)
Write-Host "PIE_AGENT_STATUS_OK" -ForegroundColor Green
