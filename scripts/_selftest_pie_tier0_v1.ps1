param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [string]$RunId = "pie0",
  [switch]$SkipSign
)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
function Resolve-VecPacketRoot([string]$VecDir){
  $p = Join-Path $VecDir "packet"
  if(Test-Path -LiteralPath $p -PathType Container){ return $p }
  return $VecDir
}

$RepoRoot=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $RepoRoot "scripts\_lib_pie_tier0_v1.ps1")
function Expect-Fail([string]$Path,[string]$Label){
  $failed = $false
  try {
    & (Join-Path $RepoRoot "scripts\pie_verify_packet_optionA_v1.ps1") -RepoRoot $RepoRoot -PacketRoot $Path | Out-Host
  } catch {
    $failed = $true
    Write-Host ("EXPECTED_FAIL_OK: " + $Label + " :: " + $_.Exception.Message) -ForegroundColor Yellow
  }
  if(-not $failed){
    Die ("EXPECTED_FAILURE_MISSING: " + $Label + " path=" + $Path)
  }
}
Write-Host "SELFTEST_PIE_TIER0_V1_START" -ForegroundColor Yellow
Write-Host "VECTORS_MATERIALIZE_START" -ForegroundColor Yellow
& (Join-Path $RepoRoot "scripts\pie_materialize_vectors_v1.ps1") -RepoRoot $RepoRoot | Out-Host
Write-Host "VECTORS_MATERIALIZE_OK" -ForegroundColor Green
# Canonical vector bootstrap FROM the just-built valid packet
$tv = Join-Path $RepoRoot "test_vectors"
if (Test-Path -LiteralPath $tv -PathType Container) { Remove-Item -LiteralPath $tv -Recurse -Force }
New-Item -ItemType Directory -Force -Path $tv | Out-Null

$srcPacket = Join-Path (Join-Path $RepoRoot "proofs\runs\pie0") "packet"
if (-not (Test-Path -LiteralPath $srcPacket -PathType Container)) { Die ("MISSING_SOURCE_PACKET: " + $srcPacket) }

$posRoot = Join-Path $tv "pos_minimal_v1"
$n1Root  = Join-Path $tv "neg_manifest_contains_packet_id_v1"
$n2Root  = Join-Path $tv "neg_packet_id_mismatch_v1"
$n3Root  = Join-Path $tv "neg_sha256_mismatch_v1"

$pos = Join-Path $posRoot "packet"
$n1  = Join-Path $n1Root  "packet"
$n2  = Join-Path $n2Root  "packet"
$n3  = Join-Path $n3Root  "packet"

foreach($d in @($posRoot,$n1Root,$n2Root,$n3Root)){
  New-Item -ItemType Directory -Force -Path $d | Out-Null
}

Copy-Item -LiteralPath $srcPacket -Destination $pos -Recurse -Force
Copy-Item -LiteralPath $srcPacket -Destination $n1  -Recurse -Force
Copy-Item -LiteralPath $srcPacket -Destination $n2  -Recurse -Force
Copy-Item -LiteralPath $srcPacket -Destination $n3  -Recurse -Force

# NEG1: manifest contains forbidden packet_id field (PS5.1-safe; no -AsHashtable)
$mf1    = Join-Path $n1 "manifest.json"
$mf1Raw = [System.IO.File]::ReadAllText($mf1, (New-Object System.Text.UTF8Encoding($false)))
if ($mf1Raw -match '"packet_id"\s*:') {
  # already negative; keep as-is
} else {
  $mf1Trim = $mf1Raw.TrimEnd()
  if (-not $mf1Trim.EndsWith("}")) { Die ("NEG1_BAD_MANIFEST_SHAPE: " + $mf1) }
  $mf1New = $mf1Trim.Substring(0, $mf1Trim.Length - 1) + ',"packet_id":"BAD_NEGATIVE_VECTOR"}'
  [System.IO.File]::WriteAllText($mf1, ($mf1New + "`n"), (New-Object System.Text.UTF8Encoding($false)))
}

# NEG2: packet_id mismatch
$pid2 = Join-Path $n2 "packet_id.txt"
[System.IO.File]::WriteAllText($pid2, (("0" * 64) + "`n"), (New-Object System.Text.UTF8Encoding($false)))

# NEG3: sha256sums mismatch
$sum3 = Join-Path $n3 "sha256sums.txt"
$sumLines = @([System.IO.File]::ReadAllLines($sum3, (New-Object System.Text.UTF8Encoding($false))))
if ($sumLines.Count -lt 1) { Die ("NEG3_EMPTY_SHA256SUMS: " + $sum3) }
$parts = $sumLines[0] -split '\s+', 2
if ($parts.Count -lt 2) { Die ("NEG3_BAD_SHA256SUMS_LINE: " + $sumLines[0]) }
$sumLines[0] = (("0" * 64) + "  " + $parts[1])
[System.IO.File]::WriteAllText($sum3, (($sumLines -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))

Write-Host "SELFTEST_VECTORS_FROM_VALID_PACKET_OK" -ForegroundColor Green
Write-Host ("  POS_PKT: " + $pos) -ForegroundColor Green
Write-Host ("  NEG1_PKT: " + $n1) -ForegroundColor Green
Write-Host ("  NEG2_PKT: " + $n2) -ForegroundColor Green
Write-Host ("  NEG3_PKT: " + $n3) -ForegroundColor Green
# Canonical aliases for downstream negative checks
$neg1 = $n1
$neg2 = $n2
$neg3 = $n3


# Canonical vector bootstrap (StrictMode-safe)
$tv = Join-Path $RepoRoot "test_vectors"
$pos = Resolve-VecPacketRoot (Join-Path (Join-Path $tv "pos_minimal_v1") "packet")
$n1  = Resolve-VecPacketRoot (Join-Path (Join-Path $tv "neg_manifest_contains_packet_id_v1") "packet")
$n2  = Resolve-VecPacketRoot (Join-Path (Join-Path $tv "neg_packet_id_mismatch_v1") "packet")
$n3  = Resolve-VecPacketRoot (Join-Path (Join-Path $tv "neg_sha256_mismatch_v1") "packet")
Write-Host ("VEC_PACKET_ROOTS_OK") -ForegroundColor Green
Write-Host ("  POS_PKT: " + $pos) -ForegroundColor Green
Write-Host ("  NEG1_PKT: " + $n1) -ForegroundColor Green
Write-Host ("  NEG2_PKT: " + $n2) -ForegroundColor Green
Write-Host ("  NEG3_PKT: " + $n3) -ForegroundColor Green






# 1) seal
& (Join-Path $RepoRoot "scripts\pie_seal_run_v1.ps1") -RepoRoot $RepoRoot -RunId $RunId | Out-Host

# 2) build
$pkt = & (Join-Path $RepoRoot "scripts\pie_build_packet_optionA_v1.ps1") -RepoRoot $RepoRoot -RunId $RunId
if([string]::IsNullOrWhiteSpace($pkt)){ Die "BUILD_DID_NOT_RETURN_PACKETROOT" }
$pkt = (Resolve-Path -LiteralPath $pkt).Path

# 3) sign (uses existing signer if present)
if(-not $SkipSign){
  $signer = Join-Path $RepoRoot "scripts\pie_run_packet_sign_v1.ps1"
  if(-not (Test-Path -LiteralPath $signer -PathType Leaf)){ Die ("MISSING_SIGNER: " + $signer) }
  & $signer -RepoRoot $RepoRoot -PacketRoot $pkt -Namespace "pie" -Principal "pie.tier0" | Out-Host
} else { Write-Host "SKIP_SIGN=1" -ForegroundColor Yellow }

# 4) verify (independent)
& (Join-Path $RepoRoot "scripts\pie_verify_packet_optionA_v1.ps1") -RepoRoot $RepoRoot -PacketRoot $pkt | Out-Host

# 5) build vectors (pos + 3 neg) deterministically from this packet
Ensure-Dir $tv
& (Join-Path $RepoRoot "scripts\pie_verify_packet_optionA_v1.ps1") -RepoRoot $RepoRoot -PacketRoot (Resolve-VecPacketRoot $pos) | Out-Host
# negatives (deterministic needles)
Expect-Fail $neg1 "INVALID_MANIFEST_CONTAINS_PACKET_ID"
Expect-Fail $neg2 "INVALID_SHA256_MISMATCH"
Expect-Fail $neg3 "INVALID_PACKET_ID_MISMATCH"

Write-Host "SELFTEST_PIE_TIER0_V1_GREEN" -ForegroundColor Green
