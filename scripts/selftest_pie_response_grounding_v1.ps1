param([Parameter(Mandatory=$true)][string]$RepoRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $RepoRoot "scripts\_lib_pie_response_grounding_v1.ps1")

$Bad = @(
  'The repository is at `C:\dev\`.',
  'Memory has no concrete implementation yet.',
  '### Highest-Priority Gap: governance and security',
  'The implementation lacks robust mechanisms for tracking and auditing operations.',
  'Use `scripts\definitely_missing_grounding_fixture.ps1` next.'
) -join "`n"
$Result = PIE_GroundResponse -Response $Bad -ProjectRepo $RepoRoot
if($Result.correction_count -lt 4){ throw "PIE_RESPONSE_GROUNDING_CORRECTIONS_MISSING" }
$ExpectedRoot = [string][char]96 + $RepoRoot + [string][char]96
if($Result.response -notmatch [regex]::Escape($ExpectedRoot)){ throw "PIE_RESPONSE_GROUNDING_ROOT_NOT_CORRECTED" }
if($Result.response -notmatch "contradicted by repository evidence"){ throw "PIE_RESPONSE_GROUNDING_MEMORY_CONTRADICTION_MISSING" }
if($Result.response -notmatch "Broad claims that PIE lacks governance"){ throw "PIE_RESPONSE_GROUNDING_GOVERNANCE_CONTRADICTION_MISSING" }
if($Result.response -notmatch "definitely_missing_grounding_fixture.ps1"){ throw "PIE_RESPONSE_GROUNDING_INVALID_PATH_MISSING" }

$Good = 'Repository `C:\dev\pie` includes `scripts\pie_memory_resolve_v1.ps1`.'
$GoodResult = PIE_GroundResponse -Response $Good -ProjectRepo $RepoRoot
if($GoodResult.correction_count -ne 0){ throw "PIE_RESPONSE_GROUNDING_VALID_RESPONSE_CHANGED" }

Write-Host "PIE_RESPONSE_GROUNDING_SELFTEST_OK" -ForegroundColor Green
