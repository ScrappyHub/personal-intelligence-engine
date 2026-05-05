param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][int]$AgentIterations,
  [Parameter(Mandatory=$true)][int]$RuntimeIterations
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$m){ throw $m }

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$PSExe = "powershell.exe"

Write-Host "PIE_OFFLINE_PIPELINE_START" -ForegroundColor Cyan

# ------------------------------------------------------------
# 1. SELFTEST
# ------------------------------------------------------------
$p1 = Start-Process -FilePath $PSExe -ArgumentList @(
  "-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass",
  "-File",(Join-Path $RepoRoot "scripts\_selftest_pie_agent_offline_v1.ps1"),
  "-RepoRoot",$RepoRoot
) -Wait -PassThru

if($p1.ExitCode -ne 0){ Die "PIPELINE_FAIL_SELFTEST" }

# ------------------------------------------------------------
# 2. AGENT STRESS
# ------------------------------------------------------------
$p2 = Start-Process -FilePath $PSExe -ArgumentList @(
  "-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass",
  "-File",(Join-Path $RepoRoot "scripts\_RUN_pie_agent_stress_v1.ps1"),
  "-RepoRoot",$RepoRoot,
  "-Iterations",$AgentIterations
) -Wait -PassThru

if($p2.ExitCode -ne 0){ Die "PIPELINE_FAIL_AGENT_STRESS" }

# ------------------------------------------------------------
# 3. RUNTIME STRESS
# ------------------------------------------------------------
$p3 = Start-Process -FilePath $PSExe -ArgumentList @(
  "-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass",
  "-File",(Join-Path $RepoRoot "scripts\_RUN_pie_runtime_stress_v1.ps1"),
  "-RepoRoot",$RepoRoot,
  "-Iterations",$RuntimeIterations
) -Wait -PassThru

if($p3.ExitCode -ne 0){ Die "PIPELINE_FAIL_RUNTIME_STRESS" }

# ------------------------------------------------------------
# FINAL
# ------------------------------------------------------------
Write-Host "PIE_OFFLINE_PIPELINE_V1_OK" -ForegroundColor Green
exit 0