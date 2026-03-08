param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$OutDir,
  [Parameter(Mandatory=$true)][string]$Producer,
  [Parameter(Mandatory=$true)][string]$PacketKind,
  [Parameter(Mandatory=$true)][string]$PayloadDir
)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
. (Join-Path $RepoRoot "scripts\_lib_packet_constitution_v1.ps1")
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$PayloadDir = (Resolve-Path -LiteralPath $PayloadDir).Path
if (-not (Test-Path -LiteralPath $OutDir -PathType Container)) { New-Item -ItemType Directory -Force -Path $OutDir | Out-Null }
$OutDir = (Resolve-Path -LiteralPath $OutDir).Path

# 1) Write payload/** first (copy)
$staging = Join-Path $OutDir ("staging_" + (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss") + "_" + ([guid]::NewGuid().ToString("n")))
New-Item -ItemType Directory -Force -Path $staging | Out-Null
$payloadOut = Join-Path $staging "payload"
New-Item -ItemType Directory -Force -Path $payloadOut | Out-Null
Copy-Item -LiteralPath (Join-Path $PayloadDir "*") -Destination $payloadOut -Recurse -Force

# 2) Write manifest.json WITHOUT packet_id using canonical JSON bytes
$manifest = @{ schema="packet.manifest.v1"; producer=$Producer; kind=$PacketKind; created_utc=(Get-Date).ToUniversalTime().ToString("o"); option="A"; payload_root="payload" }
$manifestJson = PC_ToCanonJson $manifest
$manifestPath = Join-Path $staging "manifest.json"
PC_WriteUtf8NoBomLf $manifestPath $manifestJson

# 3) signatures/** step is reserved; not required for minimal build tool v1
$sigDir = Join-Path $staging "signatures"
if (-not (Test-Path -LiteralPath $sigDir -PathType Container)) { New-Item -ItemType Directory -Force -Path $sigDir | Out-Null }

# 4) Compute PacketId from canonical bytes of manifest-without-id (manifest.json on disk)
$packetId = PC_Sha256HexFile $manifestPath

# 5) Persist PacketId -> packet_id.txt
$pidPath = Join-Path $staging "packet_id.txt"
PC_WriteUtf8NoBomLf $pidPath $packetId

# 6) Generate sha256sums.txt LAST (excluding itself)
$sumsPath = PC_WriteSha256Sums $staging

# 7) Receipts last (in v1 we just print deterministic summary)
$final = Join-Path $OutDir $packetId
if (Test-Path -LiteralPath $final) { PC_Die ("packet_exists: " + $final) }
Move-Item -LiteralPath $staging -Destination $final
Write-Host ("PACKET_BUILD_OK: " + $final) -ForegroundColor Green
Write-Host ("PacketId: " + $packetId) -ForegroundColor Cyan
Write-Host ("manifest_sha256: " + (PC_Sha256HexFile (Join-Path $final "manifest.json"))) -ForegroundColor Cyan
Write-Host ("sha256sums_sha256: " + (PC_Sha256HexFile (Join-Path $final "sha256sums.txt"))) -ForegroundColor Cyan
