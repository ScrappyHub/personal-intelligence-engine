param(
[Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$ManifestPath = Join-Path $RepoRoot "docs\PIE_GREEN_COMMANDS.manifest.json"
$DocPath = Join-Path $RepoRoot "docs\PIE_GREEN_COMMANDS.md"
$CliPath = Join-Path $RepoRoot "pie.ps1"
$RunnerPath = Join-Path $RepoRoot "scripts\GOVERNANCE_GREEN_RUNNER_PIE_v1.ps1"

function Assert-File {
param([string]$Path,[string]$Code)
if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){
throw $Code
}
}

Assert-File -Path $ManifestPath -Code "PIE_GREEN_MANIFEST_MISSING"
Assert-File -Path $DocPath -Code "PIE_GREEN_DOC_MISSING"
Assert-File -Path $CliPath -Code "PIE_GREEN_CLI_MISSING"
Assert-File -Path $RunnerPath -Code "PIE_GREEN_RUNNER_MISSING"

$Manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
$Doc = Get-Content -LiteralPath $DocPath -Raw
$Cli = Get-Content -LiteralPath $CliPath -Raw
$Runner = Get-Content -LiteralPath $RunnerPath -Raw

if($Manifest.schema -ne "pie.green.commands.manifest.v1"){
throw "PIE_GREEN_MANIFEST_SCHEMA_BAD"
}

if($Manifest.command_root -ne "pie green"){
throw "PIE_GREEN_MANIFEST_ROOT_BAD"
}

$Commands = @($Manifest.commands)

if($Commands.Count -ne 5){
throw "PIE_GREEN_MANIFEST_COMMAND_COUNT_BAD"
}

$Expected = @(
@{ command="pie green status"; mode="status"; runs_tests=$false; produces_freeze=$false },
@{ command="pie green manifest"; mode="manifest"; runs_tests=$false; produces_freeze=$false },
@{ command="pie green governance"; mode="latest_governance"; runs_tests=$true; produces_freeze=$true },
@{ command="pie green governance-full"; mode="trusted_baseline_lifecycle"; runs_tests=$true; produces_freeze=$true },
@{ command="pie green full"; mode="full"; runs_tests=$true; produces_freeze=$true }
)

foreach($E in $Expected){
$Found = @($Commands | Where-Object { $_.command -eq $E.command })

if($Found.Count -ne 1){
throw ("PIE_GREEN_MANIFEST_COMMAND_ENTRY_BAD: " + $E.command)
}

$C = $Found[0]

if($C.mode -ne $E.mode){
throw ("PIE_GREEN_MANIFEST_MODE_BAD: " + $E.command)
}

if([bool]$C.runs_tests -ne [bool]$E.runs_tests){
throw ("PIE_GREEN_MANIFEST_RUNS_TESTS_BAD: " + $E.command)
}

if([bool]$C.produces_freeze -ne [bool]$E.produces_freeze){
throw ("PIE_GREEN_MANIFEST_PRODUCES_FREEZE_BAD: " + $E.command)
}

if($Doc -notlike ("" + $E.command + "")){
throw ("PIE_GREEN_DOC_COMMAND_MISSING: " + $E.command)
}
}

foreach($Needle in @(
'if($ModeArg -eq "status")',
'if($ModeArg -eq "manifest")',
'if($ModeArg -eq "governance")',
'if($ModeArg -eq "governance-full")',
'if($ModeArg -eq "full")'
)){
if($Cli -notlike ("" + $Needle + "")){
throw ("PIE_GREEN_CLI_ROUTE_MISSING: " + $Needle)
}
}

foreach($Needle in @(
'latest_governance',
'trusted_baseline_lifecycle',
'cross_repo_regression_negative',
'cross_repo_baseline_enforce',
'cross_repo_baseline_governance_report',
'PIE_GOVERNANCE_GREEN_OK'
)){
if($Runner -notlike ("" + $Needle + "")){
throw ("PIE_GREEN_RUNNER_CONTRACT_MISSING: " + $Needle)
}
}

$Governance = @($Commands | Where-Object { $.command -eq "pie green governance" })[0]
$GovernanceFull = @($Commands | Where-Object { $.command -eq "pie green governance-full" })[0]
$Full = @($Commands | Where-Object { $_.command -eq "pie green full" })[0]

foreach($Evidence in @("FREEZE_SUMMARY.json","child_receipts.ndjson","parse_gate_sha256s.txt","sha256sums.txt")){
if(@($Governance.evidence) -notcontains $Evidence){
throw ("PIE_GREEN_GOVERNANCE_EVIDENCE_MISSING: " + $Evidence)
}
if(@($GovernanceFull.evidence) -notcontains $Evidence){
throw ("PIE_GREEN_GOVERNANCE_FULL_EVIDENCE_MISSING: " + $Evidence)
}
if(@($Full.evidence) -notcontains $Evidence){
throw ("PIE_GREEN_FULL_EVIDENCE_MISSING: " + $Evidence)
}
}

foreach($Life in @("promote","revoke","replace_supersede","lineage_audit","readable_governance_report")){
if(@($GovernanceFull.lifecycle_covered_by_report) -notcontains $Life){
throw ("PIE_GREEN_LIFECYCLE_COVERAGE_MISSING: " + $Life)
}
}

if(-not [bool]$Manifest.rules.use_smallest_green_lane_that_proves_change){
throw "PIE_GREEN_RULE_SMALLEST_LANE_BAD"
}

if(-not [bool]$Manifest.rules.failed_partial_freezes_must_not_be_committed){
throw "PIE_GREEN_RULE_FAILED_FREEZE_BAD"
}

if(-not [bool]$Manifest.rules.full_green_required_before_major_release){
throw "PIE_GREEN_RULE_FULL_RELEASE_BAD"
}

Write-Host "PIE_GREEN_MANIFEST_VALIDATE_OK" -ForegroundColor Green
Write-Host ("manifest: " + $ManifestPath)
Write-Host ("commands: " + [string]$Commands.Count)
