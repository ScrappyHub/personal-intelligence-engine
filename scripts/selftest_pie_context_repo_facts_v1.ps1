param([Parameter(Mandatory=$true)][string]$RepoRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$SessionId = "pie_context_repo_facts_selftest"
$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)

if(Test-Path -LiteralPath $RunRoot -PathType Container){ Remove-Item -LiteralPath $RunRoot -Recurse -Force }

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_agent_start_v1.ps1") `
  -RepoRoot $RepoRoot -SessionId $SessionId -Backend mock -Model context-facts-mock `
  -ProjectRepo $RepoRoot -Goal "Verify deterministic repository facts" | Out-Host
if($LASTEXITCODE -ne 0){ throw "PIE_CONTEXT_REPO_FACTS_START_FAIL" }

$ContextOutput = @(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_context_build_v1.ps1") `
  -RepoRoot $RepoRoot -SessionId $SessionId -UserMessage "Summarize this repository") -join "`n"
if($LASTEXITCODE -ne 0){ throw "PIE_CONTEXT_REPO_FACTS_BUILD_FAIL" }

$PromptPath = ""
foreach($Line in @($ContextOutput -split "`n")){
  if($Line -like "PIE_CONTEXT_BUILD_OK:*"){ $PromptPath = $Line.Substring("PIE_CONTEXT_BUILD_OK:".Length).Trim() }
}
if([string]::IsNullOrWhiteSpace($PromptPath)){ throw "PIE_CONTEXT_REPO_FACTS_PROMPT_MISSING" }

$Prompt = Get-Content -LiteralPath $PromptPath -Raw
foreach($Marker in @("CURRENT DETERMINISTIC REPOSITORY FACTS (AUTHORITATIVE FOR THIS ANSWER):","ANSWER GROUNDING RULES:","IMPLEMENTED PIE CAPABILITY EVIDENCE:","governance_audit=implemented","README EXCERPT:","SCRIPT INVENTORY:","pie_agent_send_v1.ps1","GIT STATUS:")){
  if($Prompt -notmatch [regex]::Escape($Marker)){ throw ("PIE_CONTEXT_REPO_FACTS_MARKER_MISSING: " + $Marker) }
}

$Packet = Get-ChildItem -LiteralPath (Join-Path $RunRoot "context_packets") -Filter "context_packet_*.json" -File |
  Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1 |
  ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json }
if($null -eq $Packet -or -not [bool]$Packet.has_repo_facts){ throw "PIE_CONTEXT_REPO_FACTS_PACKET_FLAG_BAD" }

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_agent_stop_v1.ps1") -RepoRoot $RepoRoot -SessionId $SessionId | Out-Host
if($LASTEXITCODE -ne 0){ throw "PIE_CONTEXT_REPO_FACTS_STOP_FAIL" }

Write-Host "PIE_CONTEXT_REPO_FACTS_SELFTEST_OK" -ForegroundColor Green
