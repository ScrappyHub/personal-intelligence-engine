param([Parameter(Mandatory=$true)][string]$RepoRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Pie = Join-Path $RepoRoot "pie.ps1"
$SessionId = "pie_agent_workflow_selftest"
$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)
if(Test-Path -LiteralPath $RunRoot -PathType Container){ Remove-Item -LiteralPath $RunRoot -Recurse -Force }

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Pie agent start -RepoRoot $RepoRoot -SessionId $SessionId -TargetRepo $RepoRoot -Goal "Read-only repository inspection" -Backend mock -Model workflow-mock | Out-Host
if($LASTEXITCODE -ne 0){ throw "PIE_AGENT_WORKFLOW_START_FAIL" }

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Pie agent plan -RepoRoot $RepoRoot -SessionId $SessionId -Goal "Read-only repository inspection" | Out-Host
if($LASTEXITCODE -ne 0){ throw "PIE_AGENT_WORKFLOW_PLAN_FAIL" }

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Pie agent capability -RepoRoot $RepoRoot -SessionId $SessionId -Capability repo.status | Out-Host
if($LASTEXITCODE -ne 0){ throw "PIE_AGENT_WORKFLOW_CAPABILITY_FAIL" }

$PolicyJson = @(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $RepoRoot "scripts\pie_exec_policy_v1.ps1") -RepoRoot $RepoRoot -Command "git reset --hard" -WorkingDirectory $RepoRoot -SessionProjectRepo $RepoRoot) -join "`n"
$Policy = $PolicyJson | ConvertFrom-Json
if($Policy.decision -ne "DENY"){ throw "PIE_AGENT_WORKFLOW_DESTRUCTIVE_NOT_DENIED" }

$Manifest = Get-Content -LiteralPath (Join-Path $RunRoot "session_manifest.json") -Raw | ConvertFrom-Json
if($Manifest.project_repo -ne $RepoRoot){ throw "PIE_AGENT_WORKFLOW_REPO_BINDING_BAD" }
if(-not (Test-Path -LiteralPath (Join-Path $RunRoot "execution\execution_receipts.ndjson") -PathType Leaf)){ throw "PIE_AGENT_WORKFLOW_RECEIPT_MISSING" }
if(-not (Test-Path -LiteralPath (Join-Path $RunRoot "plans") -PathType Container)){ throw "PIE_AGENT_WORKFLOW_PLAN_MISSING" }

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Pie agent stop -RepoRoot $RepoRoot -SessionId $SessionId | Out-Host
if($LASTEXITCODE -ne 0){ throw "PIE_AGENT_WORKFLOW_STOP_FAIL" }
Write-Host "PIE_AGENT_WORKFLOW_SELFTEST_OK" -ForegroundColor Green
