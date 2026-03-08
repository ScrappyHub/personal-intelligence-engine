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
if(-not (Test-Path -LiteralPath $RunRoot -PathType Container)){ Die ("MISSING_RUNROOT: " + $RunRoot) }
$PktRoot = Join-Path $RunRoot "packet"
Ensure-Dir $PktRoot
$payloadDir = Join-Path $PktRoot "payload"
Ensure-Dir $payloadDir
# Minimal deterministic payload for Tier-0 (placeholder).
$payloadPath = Join-Path $payloadDir "hello.txt"
Write-Utf8NoBomLf $payloadPath ("hello from PIE run " + $RunId + "`n")

# Option A: manifest.json MUST NOT contain packet_id
$manifest = [ordered]@{
  schema="pcv1.manifest.v1";
  created_utc=[DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ");
  producer="pie.tier0";
  run_id=$RunId;
  files=@(
    [ordered]@{ relpath="payload/hello.txt"; kind="payload"; required=$true }
  )
}
$manPath = Join-Path $PktRoot "manifest.json"
Write-CanonJsonFile $manPath $manifest

# PacketId = SHA-256(canonical bytes of manifest-without-id) â€” we use on-disk manifest.json bytes (already canonical)
$packetId = Sha256-Bytes (Read-Bytes $manPath)
$pidPath = Join-Path $PktRoot "packet_id.txt"
Write-Utf8NoBomLf $pidPath ($packetId + "`n")

# sha256sums.txt generated LAST over final on-disk bytes
$shaPath = Join-Path $PktRoot "sha256sums.txt"
$lines = New-Object System.Collections.Generic.List[string]
$rel = @("manifest.json","packet_id.txt","payload/hello.txt")
foreach($rp in $rel){
  $fp = Join-Path $PktRoot ($rp.Replace("/","\"))
  if(-not (Test-Path -LiteralPath $fp -PathType Leaf)){ Die ("MISSING_PACKET_FILE: " + $fp) }
  $h = Sha256-File $fp
  [void]$lines.Add(($h + "  " + $rp))
}
Write-Utf8NoBomLf $shaPath ((($lines.ToArray()) -join "`n") + "`n")

$tPath = Join-Path $RunRoot "build_transcript.txt"
Write-Utf8NoBomLf $tPath ("PIE_BUILD_OK run_id=" + $RunId + "`npacket=" + $PktRoot + "`npacket_id=" + $packetId + "`n")
Write-Host ("PIE_BUILD_OK: " + $PktRoot) -ForegroundColor Green
Write-Output $PktRoot
