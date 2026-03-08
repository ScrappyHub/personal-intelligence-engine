param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$PacketRoot
)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
. (Join-Path $RepoRoot "scripts\_lib_pie_tier0_v1.ps1")
$RepoRoot=(Resolve-Path -LiteralPath $RepoRoot).Path
$PacketRoot=(Resolve-Path -LiteralPath $PacketRoot).Path
if(-not (Test-Path -LiteralPath $PacketRoot -PathType Container)){ Die ("MISSING_PACKETROOT: " + $PacketRoot) }
$manPath = Join-Path $PacketRoot "manifest.json"
$pidPath = Join-Path $PacketRoot "packet_id.txt"
$shaPath = Join-Path $PacketRoot "sha256sums.txt"
foreach($p in @($manPath,$pidPath,$shaPath)){ if(-not (Test-Path -LiteralPath $p -PathType Leaf)){ Die ("MISSING_REQUIRED: " + $p) } }

# Parse manifest, enforce Option A: NO packet_id field
$mRaw = Read-Utf8NoBom $manPath
$mObj = $mRaw | ConvertFrom-Json -ErrorAction Stop
if($mObj.PSObject.Properties.Name -contains "packet_id"){ Die "INVALID_MANIFEST_CONTAINS_PACKET_ID" }
if(-not $mObj.files){ Die "INVALID_MANIFEST_MISSING_FILES" }

# Relpath safety checks + existence
foreach($f in @($mObj.files)){
  $rp = [string]$f.relpath
  if(-not (Safe-RelPath $rp)){ Die ("INVALID_RELPATH: " + $rp) }
  $fp = Join-Path $PacketRoot ($rp.Replace("/","\"))
  if(-not (Test-Path -LiteralPath $fp -PathType Leaf)){ Die ("MISSING_MANIFEST_FILE: " + $rp) }
}

# Recompute PacketId from on-disk manifest.json bytes (must already be canonical)
$pidExpected = Sha256-Bytes (Read-Bytes $manPath)
$pidActual = (Read-Utf8NoBom $pidPath).Trim()
if($pidActual -ne $pidExpected){ Die ("INVALID_PACKET_ID_MISMATCH expected=" + $pidExpected + " actual=" + $pidActual) }

# Verify sha256sums.txt matches actual on-disk bytes for each listed relpath
$lines = @()
$raw = Read-Utf8NoBom $shaPath
foreach($ln in @($raw -split "`n")){ $t=$ln.Trim(); if([string]::IsNullOrWhiteSpace($t)){ continue }; $lines += @($t) }
if($lines.Count -lt 3){ Die "INVALID_SHA256SUMS_TOO_SHORT" }
$seen = @{}
foreach($ln in $lines){
  $m = [regex]::Match($ln,'^(?<h>[0-9a-f]{64})\s{2}(?<p>.+)$')
  if(-not $m.Success){ Die ("INVALID_SHA256SUMS_LINE: " + $ln) }
  $h = $m.Groups["h"].Value
  $rp = $m.Groups["p"].Value
  if($seen.ContainsKey($rp)){ Die ("INVALID_SHA256SUMS_DUP_RELPATH: " + $rp) }
  $seen[$rp]=$true
  if(-not (Safe-RelPath $rp) -and $rp -ne "manifest.json" -and $rp -ne "packet_id.txt" -and $rp -ne "sha256sums.txt"){ Die ("INVALID_SHA256SUMS_RELPATH: " + $rp) }
  $fp = Join-Path $PacketRoot ($rp.Replace("/","\"))
  if(-not (Test-Path -LiteralPath $fp -PathType Leaf)){ Die ("INVALID_SHA256SUMS_MISSING_FILE: " + $rp) }
  $ha = Sha256-File $fp
  if($ha -ne $h){ Die ("INVALID_SHA256_MISMATCH relpath=" + $rp + " expected=" + $h + " actual=" + $ha) }
}

# Produce deterministic verification_result.json in packet root (verifier output).
$res = [ordered]@{ schema="pie.verify.result.v1"; status="VALID"; packet_root=$PacketRoot; packet_id=$pidExpected; verified_utc=[DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ") }
$outPath = Join-Path $PacketRoot "verification_result.json"
Write-CanonJsonFile $outPath $res
Write-Host ("PIE_VERIFY_VALID packet_id=" + $pidExpected) -ForegroundColor Green
Write-Output $outPath
