param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$RunId
)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
. (Join-Path $RepoRoot "scripts\_lib_pie_tier0_v1.ps1")
$RepoRoot=(Resolve-Path -LiteralPath $RepoRoot).Path
if($RunId -notmatch '^[a-z0-9][a-z0-9_\-]{1,63}$'){ Die ("BAD_RUNID: " + $RunId) }
$RunRoot = Join-Path $RepoRoot ("proofs\runs\" + $RunId)
Ensure-Dir $RunRoot
$stamp = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
$meta = [ordered]@{
  schema="pie.run.seal.v1"; run_id=$RunId; created_utc=$stamp;
  repo_root=$RepoRoot;
}
$metaPath = Join-Path $RunRoot "run_seal.json"
Write-CanonJsonFile $metaPath $meta
$tPath = Join-Path $RunRoot "seal_transcript.txt"
Write-Utf8NoBomLf $tPath ("PIE_SEAL_OK run_id=" + $RunId + "`n")
Write-Host ("PIE_SEAL_OK: " + $RunRoot) -ForegroundColor Green
