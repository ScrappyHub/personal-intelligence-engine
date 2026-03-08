param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
function Die([string]$m){ throw $m }
function Ensure-Dir([string]$p){ if($p -and -not (Test-Path -LiteralPath $p -PathType Container)){ New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function Write-Utf8NoBomLf([string]$Path,[string]$Text){ $dir=Split-Path -Parent $Path; if($dir){ Ensure-Dir $dir }; $t=$Text.Replace("`r`n","`n").Replace("`r","`n"); if(-not $t.EndsWith("`n")){ $t += "`n" }; $enc=New-Object System.Text.UTF8Encoding($false); [System.IO.File]::WriteAllText($Path,$t,$enc) }
function Read-Utf8NoBom([string]$Path){ if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("MISSING_FILE: " + $Path) }; $enc=New-Object System.Text.UTF8Encoding($false); return [System.IO.File]::ReadAllText($Path,$enc) }
function Parse-GateText([string]$Text){ [void][ScriptBlock]::Create($Text) }
function Parse-GateFile([string]$Path){ Parse-GateText (Read-Utf8NoBom $Path) }

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Scripts = Join-Path $RepoRoot "scripts"
$Scratch  = Join-Path $Scripts "_scratch"
Ensure-Dir $Scripts
Ensure-Dir $Scratch
Ensure-Dir (Join-Path $RepoRoot "docs")
Ensure-Dir (Join-Path $RepoRoot "docs\wbs")
Ensure-Dir (Join-Path $RepoRoot "schemas")
Ensure-Dir (Join-Path $RepoRoot "proofs\audit")
Ensure-Dir (Join-Path $RepoRoot "proofs\runs")
Ensure-Dir (Join-Path $RepoRoot "test_vectors")

$libPath = Join-Path $Scripts "_lib_pie_tier0_v1.ps1"
$libText = @'
# PIE Tier-0 Lib v1
# PS5.1, StrictMode, UTF-8 no BOM + LF, NO exit
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
function Die([string]$m){ throw $m }
function Ensure-Dir([string]$p){ if($p -and -not (Test-Path -LiteralPath $p -PathType Container)){ New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function Write-Utf8NoBomLf([string]$Path,[string]$Text){ $dir=Split-Path -Parent $Path; if($dir){ Ensure-Dir $dir }; $t=$Text.Replace("`r`n","`n").Replace("`r","`n"); if(-not $t.EndsWith("`n")){ $t += "`n" }; $enc=New-Object System.Text.UTF8Encoding($false); [System.IO.File]::WriteAllText($Path,$t,$enc) }
function Read-Utf8NoBom([string]$Path){ if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("MISSING_FILE: " + $Path) }; $enc=New-Object System.Text.UTF8Encoding($false); return [System.IO.File]::ReadAllText($Path,$enc) }
function Read-Bytes([string]$Path){ if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("MISSING_FILE: " + $Path) }; return [System.IO.File]::ReadAllBytes($Path) }
function Sha256-Bytes([byte[]]$b){ $sha=[System.Security.Cryptography.SHA256]::Create(); try{ $h=$sha.ComputeHash($b) } finally { $sha.Dispose() }; return ([BitConverter]::ToString($h).Replace("-","").ToLowerInvariant()) }
function Sha256-File([string]$Path){ return (Sha256-Bytes (Read-Bytes $Path)) }
function CanonJson([object]$obj){
  # Deterministic canonical JSON: sort keys recursively, no whitespace
  function _Sort([object]$x){
    if($null -eq $x){ return $null }
    if($x -is [System.Collections.IDictionary]){
      $keys=@($x.Keys | ForEach-Object { [string]$_ } | Sort-Object)
      $o=[ordered]@{}
      foreach($k in $keys){ $o[$k]=_Sort $x[$k] }
      return $o
    }
    if(($x -is [System.Collections.IEnumerable]) -and -not ($x -is [string])){
      $arr=@()
      foreach($it in $x){ $arr += @(_Sort $it) }
      return ,$arr
    }
    return $x
  }
  $s = (_Sort $obj) | ConvertTo-Json -Depth 99 -Compress
  # Force LF and trailing LF for canonical bytes discipline when writing
  return $s.Replace("`r`n","`n").Replace("`r","`n")
}
function Write-CanonJsonFile([string]$Path,[object]$obj){ Write-Utf8NoBomLf $Path ((CanonJson $obj) + "`n") }
function Safe-RelPath([string]$p){
  # Disallow absolute paths, traversal, or backslashes in manifest relpaths
  if([string]::IsNullOrWhiteSpace($p)){ return $false }
  if($p -match '^[A-Za-z]:\\' ){ return $false }
  if($p.StartsWith("/") -or $p.StartsWith("\")){ return $false }
  if($p -match '\\'){ return $false }
  if($p -match '(^|/)\.\.(\/|$)' ){ return $false }
  return $true
}
'@
Write-Utf8NoBomLf $libPath $libText
Parse-GateFile $libPath
Write-Host ("WROTE_LIB_OK: " + $libPath) -ForegroundColor Green

$sealPath = Join-Path $Scripts "pie_seal_run_v1.ps1"
$sealText = @'
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
'@
Write-Utf8NoBomLf $sealPath $sealText
Parse-GateFile $sealPath
Write-Host ("WROTE_SEAL_OK: " + $sealPath) -ForegroundColor Green

$buildPath = Join-Path $Scripts "pie_build_packet_optionA_v1.ps1"
$buildText = @'
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

# PacketId = SHA-256(canonical bytes of manifest-without-id) — we use on-disk manifest.json bytes (already canonical)
$pid = Sha256-Bytes (Read-Bytes $manPath)
$pidPath = Join-Path $PktRoot "packet_id.txt"
Write-Utf8NoBomLf $pidPath ($pid + "`n")

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
Write-Utf8NoBomLf $tPath ("PIE_BUILD_OK run_id=" + $RunId + "`npacket=" + $PktRoot + "`npacket_id=" + $pid + "`n")
Write-Host ("PIE_BUILD_OK: " + $PktRoot) -ForegroundColor Green
Write-Output $PktRoot
'@
Write-Utf8NoBomLf $buildPath $buildText
Parse-GateFile $buildPath
Write-Host ("WROTE_BUILD_OK: " + $buildPath) -ForegroundColor Green

$verPath = Join-Path $Scripts "pie_verify_packet_optionA_v1.ps1"
$verText = @'
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
'@
Write-Utf8NoBomLf $verPath $verText
Parse-GateFile $verPath
Write-Host ("WROTE_VERIFY_OK: " + $verPath) -ForegroundColor Green

$selfPath = Join-Path $Scripts "_selftest_pie_tier0_v1.ps1"
$selfText = @'
param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [string]$RunId = "pie0",
  [switch]$SkipSign
)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
$RepoRoot=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $RepoRoot "scripts\_lib_pie_tier0_v1.ps1")
Write-Host "SELFTEST_PIE_TIER0_V1_START" -ForegroundColor Yellow

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
$tv = Join-Path $RepoRoot "test_vectors"
Ensure-Dir $tv
$pos = Join-Path $tv "pos_minimal_v1"
if(Test-Path -LiteralPath $pos -PathType Container){ Remove-Item -LiteralPath $pos -Recurse -Force }
New-Item -ItemType Directory -Force -Path $pos | Out-Null
Copy-Item -LiteralPath (Join-Path $pkt "*") -Destination $pos -Recurse -Force

# neg1: manifest contains packet_id
$neg1 = Join-Path $tv "neg_manifest_contains_packet_id_v1"
if(Test-Path -LiteralPath $neg1 -PathType Container){ Remove-Item -LiteralPath $neg1 -Recurse -Force }
New-Item -ItemType Directory -Force -Path $neg1 | Out-Null
Copy-Item -LiteralPath (Join-Path $pos "*") -Destination $neg1 -Recurse -Force
$m1p = Join-Path $neg1 "manifest.json"
$m1 = (Read-Utf8NoBom $m1p) | ConvertFrom-Json -ErrorAction Stop
# inject forbidden field
$m1 | Add-Member -NotePropertyName "packet_id" -NotePropertyValue "FORBIDDEN" -Force
Write-CanonJsonFile $m1p $m1
# sha256sums now wrong on purpose; keep as-is to ensure deterministic failure ordering

# neg2: sha256 mismatch (modify payload without updating sha256sums)
$neg2 = Join-Path $tv "neg_sha256_mismatch_v1"
if(Test-Path -LiteralPath $neg2 -PathType Container){ Remove-Item -LiteralPath $neg2 -Recurse -Force }
New-Item -ItemType Directory -Force -Path $neg2 | Out-Null
Copy-Item -LiteralPath (Join-Path $pos "*") -Destination $neg2 -Recurse -Force
Write-Utf8NoBomLf (Join-Path $neg2 "payload\hello.txt") ("tamper`n")

# neg3: packet_id mismatch (edit packet_id.txt)
$neg3 = Join-Path $tv "neg_packet_id_mismatch_v1"
if(Test-Path -LiteralPath $neg3 -PathType Container){ Remove-Item -LiteralPath $neg3 -Recurse -Force }
New-Item -ItemType Directory -Force -Path $neg3 | Out-Null
Copy-Item -LiteralPath (Join-Path $pos "*") -Destination $neg3 -Recurse -Force
Write-Utf8NoBomLf (Join-Path $neg3 "packet_id.txt") ("0" * 64 + "`n")

# 6) run vector verification and assert deterministic reason tokens
function Expect-Fail([string]$Path,[string]$Needle){
  try {
    & (Join-Path $RepoRoot "scripts\pie_verify_packet_optionA_v1.ps1") -RepoRoot $RepoRoot -PacketRoot $Path | Out-Host
    Die ("EXPECTED_FAIL_BUT_VALID: " + $Path)
  } catch {
    $msg = [string]$_.Exception.Message
    if($msg -notmatch [regex]::Escape($Needle)){ Die ("FAIL_WRONG_REASON expected=" + $Needle + " got=" + $msg) }
    Write-Host ("EXPECTED_FAIL_OK: " + $Needle) -ForegroundColor Green
  }
}

# positive
& (Join-Path $RepoRoot "scripts\pie_verify_packet_optionA_v1.ps1") -RepoRoot $RepoRoot -PacketRoot $pos | Out-Host
# negatives (deterministic needles)
Expect-Fail $neg1 "INVALID_MANIFEST_CONTAINS_PACKET_ID"
Expect-Fail $neg2 "INVALID_SHA256_MISMATCH"
Expect-Fail $neg3 "INVALID_PACKET_ID_MISMATCH"

Write-Host "SELFTEST_PIE_TIER0_V1_GREEN" -ForegroundColor Green
'@
Write-Utf8NoBomLf $selfPath $selfText
Parse-GateFile $selfPath
Write-Host ("WROTE_SELFTEST_OK: " + $selfPath) -ForegroundColor Green

$fullPath = Join-Path $Scripts "_RUN_pie_tier0_full_green_v1.ps1"
$fullText = @'
param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
$RepoRoot=(Resolve-Path -LiteralPath $RepoRoot).Path
$PSExe=(Get-Command powershell.exe -ErrorAction Stop).Source
$Scripts=Join-Path $RepoRoot "scripts"
$Scratch=Join-Path $Scripts "_scratch"
function Die([string]$m){ throw $m }
function Ensure-Dir([string]$p){ if($p -and -not(Test-Path -LiteralPath $p -PathType Container)){ New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function Read-Utf8NoBom([string]$Path){ if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("MISSING_FILE: " + $Path) }; $enc=New-Object System.Text.UTF8Encoding($false); return [System.IO.File]::ReadAllText($Path,$enc) }
function Parse-GateFile([string]$Path){ [void][ScriptBlock]::Create((Read-Utf8NoBom $Path)) }
function Run-Child([string]$Script,[hashtable]$Args){
  $alist=@()
  foreach($k in @($Args.Keys)){ $alist += @("-" + $k); $alist += @([string]$Args[$k]) }
  & $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Script @alist
  if($LASTEXITCODE -ne 0){ Die ("CHILD_FAIL exit=" + $LASTEXITCODE + " script=" + $Script) }
}

Write-Host "PIE_TIER0_FULL_GREEN_V1_START" -ForegroundColor Yellow
foreach($p in @(
  (Join-Path $Scripts "_lib_pie_tier0_v1.ps1"),
  (Join-Path $Scripts "pie_seal_run_v1.ps1"),
  (Join-Path $Scripts "pie_build_packet_optionA_v1.ps1"),
  (Join-Path $Scripts "pie_verify_packet_optionA_v1.ps1"),
  (Join-Path $Scripts "_selftest_pie_tier0_v1.ps1")
)){ Parse-GateFile $p }
Write-Host "PARSE_GATE_OK" -ForegroundColor Green

# Run selftest in child proc for clean determinism
Run-Child (Join-Path $Scripts "_selftest_pie_tier0_v1.ps1") @{ RepoRoot=$RepoRoot } | Out-Host
Write-Host "PIE_TIER0_FULL_GREEN_V1_OK" -ForegroundColor Green
'@
Write-Utf8NoBomLf $fullPath $fullText
Parse-GateFile $fullPath
Write-Host ("WROTE_FULL_GREEN_OK: " + $fullPath) -ForegroundColor Green

Write-Utf8NoBomLf (Join-Path $RepoRoot "docs\SPEC_RUN_MODEL.md") ("# PIE Run Model v1`n`n- RunId is explicit; Tier-0 selftest uses pie0.`n- Seal writes proofs/runs/<run_id>/run_seal.json + seal_transcript.txt`n- Build writes proofs/runs/<run_id>/packet/**`n")
Write-Utf8NoBomLf (Join-Path $RepoRoot "docs\PACKET_SPEC_PIE.md") ("# PIE Packet Spec (PCv1 Option A) v1`n`n- manifest.json excludes packet_id`n- packet_id.txt = SHA-256(on-disk canonical manifest.json bytes)`n- sha256sums.txt generated last over final bytes`n- verifier is non-mutating`n")
Write-Host "WROTE_DOCS_OK" -ForegroundColor Green

Write-Host "PIE_PIPELINE_WRITE_OK" -ForegroundColor Green
Write-Host ("NEXT: run FULL_GREEN -> " + (Join-Path $Scripts "_RUN_pie_tier0_full_green_v1.ps1")) -ForegroundColor Yellow
