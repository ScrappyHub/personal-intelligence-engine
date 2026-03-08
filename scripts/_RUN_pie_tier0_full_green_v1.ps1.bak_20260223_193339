param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
function Die([string]$m){ throw $m }
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$PSExe = (Get-Command powershell.exe -ErrorAction Stop).Source
$Scripts = Join-Path $RepoRoot "scripts"
function Read-Utf8NoBom([string]$Path){ if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("MISSING_FILE: " + $Path) }; $enc=New-Object System.Text.UTF8Encoding($false); return [System.IO.File]::ReadAllText($Path,$enc) }
function Parse-GateFile([string]$Path){ [void][ScriptBlock]::Create((Read-Utf8NoBom $Path)) }

Write-Host "PIE_TIER0_FULL_GREEN_V1_START" -ForegroundColor Yellow

# Parse-gate the Tier-0 surface
$must = @(
  (Join-Path $Scripts "_lib_pie_tier0_v1.ps1"),
  (Join-Path $Scripts "pie_seal_run_v1.ps1"),
  (Join-Path $Scripts "pie_build_packet_optionA_v1.ps1"),
  (Join-Path $Scripts "pie_verify_packet_optionA_v1.ps1"),
  (Join-Path $Scripts "pie_run_packet_sign_v1.ps1"),
  (Join-Path $Scripts "_selftest_pie_tier0_v1.ps1")
)
foreach($p in $must){ Parse-GateFile $p }
Write-Host "PARSE_GATE_OK" -ForegroundColor Green

# Run selftest in a clean child process (explicit args, no hashtable binding)
& $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $Scripts "_selftest_pie_tier0_v1.ps1") -RepoRoot $RepoRoot | Out-Host
if($LASTEXITCODE -ne 0){ Die ("SELFTEST_CHILD_FAIL exit=" + $LASTEXITCODE) }
Write-Host "PIE_TIER0_FULL_GREEN_V1_OK" -ForegroundColor Green
