param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
function Die([string]$m){ throw $m }
function EnsureDir([string]$p){ if(-not (Test-Path -LiteralPath $p -PathType Container)){ New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function Read-Utf8NoBom([string]$Path){ if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("MISSING_FILE: " + $Path) }; $enc=New-Object System.Text.UTF8Encoding($false); return [System.IO.File]::ReadAllText($Path,$enc) }
function Write-Utf8NoBomLf([string]$Path,[string]$Text){ $dir=Split-Path -Parent $Path; if($dir){ EnsureDir $dir }; $t=$Text.Replace("`r`n","`n").Replace("`r","`n"); if(-not $t.EndsWith("`n")){ $t += "`n" }; $enc=New-Object System.Text.UTF8Encoding($false); [System.IO.File]::WriteAllText($Path,$t,$enc) }
function Copy-Dir([string]$Src,[string]$Dst){ EnsureDir $Dst; Copy-Item -LiteralPath (Join-Path $Src "*") -Destination $Dst -Recurse -Force }

$RepoRoot = $RepoRoot.TrimEnd("\")
$tv = Join-Path $RepoRoot "test_vectors"
EnsureDir $tv

# Source packet from the deterministic Tier-0 run fixture output
$srcPacket = Join-Path $RepoRoot "proofs\runs\pie0\packet"
if(-not (Test-Path -LiteralPath $srcPacket -PathType Container)){ Die ("MISSING_SOURCE_PACKET_DIR: " + $srcPacket + " (run FULL_GREEN once to materialize proofs/runs/pie0/packet)") }

# ---- POS vector ----
$pos = Join-Path $tv "pos_minimal_v1"
if(-not (Test-Path -LiteralPath $pos -PathType Container)){ Copy-Dir $srcPacket $pos }

# Helpers to read canonical core files
function MustFile([string]$d,[string]$n){ $p=Join-Path $d $n; if(-not (Test-Path -LiteralPath $p -PathType Leaf)){ Die ("MISSING_VECTOR_FILE: " + $p) }; return $p }
$posManifest = MustFile $pos "manifest.json"
$posPidTxt   = MustFile $pos "packet_id.txt"
$posSha      = MustFile $pos "sha256sums.txt"

# ---- NEG 1: manifest contains packet_id ----
$n1 = Join-Path $tv "neg_manifest_contains_packet_id_v1"
if(-not (Test-Path -LiteralPath $n1 -PathType Container)){ Copy-Dir $pos $n1 }
$m1 = Read-Utf8NoBom (MustFile $n1 "manifest.json")
if($m1 -notmatch "(?i)""packet_id"""){
  # deterministic insertion: add a packet_id field at the top-level by simple text strategy (Tier-0 fixture manifest format)
  $pid = (Read-Utf8NoBom (MustFile $n1 "packet_id.txt")).Trim()
  $m1b = $m1
  if($m1b -match "^\s*\{\s*$"){ Die "NEG1_UNSUPPORTED_MANIFEST_SHAPE (empty object)" }
  # insert after first "{"
  $i = $m1b.IndexOf("{",[System.StringComparison]::Ordinal)
  if($i -lt 0){ Die "NEG1_MANIFEST_NOT_JSON_OBJECT" }
  $m1b = $m1b.Insert($i+1, "`n  ""packet_id"": """ + $pid + """,")
  Write-Utf8NoBomLf (Join-Path $n1 "manifest.json") $m1b
}

# ---- NEG 2: packet_id.txt mismatch ----
$n2 = Join-Path $tv "neg_packet_id_mismatch_v1"
if(-not (Test-Path -LiteralPath $n2 -PathType Container)){ Copy-Dir $pos $n2 }
$pid2 = (Read-Utf8NoBom (MustFile $n2 "packet_id.txt")).Trim()
# deterministic wrong pid: flip last hex char
$last = $pid2.Substring($pid2.Length-1,1)
$flip = "0"
if($last -eq "0"){ $flip="1" }
$badPid2 = $pid2.Substring(0,$pid2.Length-1) + $flip
Write-Utf8NoBomLf (Join-Path $n2 "packet_id.txt") ($badPid2 + "`n")

# ---- NEG 3: sha256 mismatch ----
$n3 = Join-Path $tv "neg_sha256_mismatch_v1"
if(-not (Test-Path -LiteralPath $n3 -PathType Container)){ Copy-Dir $pos $n3 }
$sha3 = Read-Utf8NoBom (MustFile $n3 "sha256sums.txt")
$lines = $sha3 -split "`n"
$out = New-Object System.Collections.Generic.List[string]
for($i=0;$i -lt $lines.Length;$i++){
  $ln = $lines[$i].TrimEnd()
  if([string]::IsNullOrWhiteSpace($ln)){ continue }
  if($ln -match "^(?<h>[0-9a-fA-F]{64})\s+(?<p>.+)$"){
    $h=$matches["h"]; $p=$matches["p"]
    # mutate first hash deterministically: flip first hex
    $c=$h.Substring(0,1); $n="0"; if($c -eq "0"){ $n="1" }
    $h2 = $n + $h.Substring(1)
    [void]$out.Add(($h2 + "  " + $p))
    # copy rest unchanged
    for($j=$i+1;$j -lt $lines.Length;$j++){ $ln2=$lines[$j].TrimEnd(); if([string]::IsNullOrWhiteSpace($ln2)){ continue }; [void]$out.Add($ln2) }
    break
  } else { [void]$out.Add($ln) }
}
Write-Utf8NoBomLf (Join-Path $n3 "sha256sums.txt") ((($out.ToArray()) -join "`n") + "`n")

Write-Host ("PIE_VECTORS_OK: " + $tv) -ForegroundColor Green
Write-Host ("  POS: " + $pos) -ForegroundColor Green
Write-Host ("  NEG1: " + $n1) -ForegroundColor Green
Write-Host ("  NEG2: " + $n2) -ForegroundColor Green
Write-Host ("  NEG3: " + $n3) -ForegroundColor Green
