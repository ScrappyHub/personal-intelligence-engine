param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
function Die([string]$m){ throw $m }
function Ensure-Dir([string]$p){ if(-not(Test-Path -LiteralPath $p -PathType Container)){ New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function Write-Utf8NoBomLf([string]$Path,[string]$Text){ $dir=Split-Path -Parent $Path; if($dir){ Ensure-Dir $dir }; $t=$Text.Replace("`r`n","`n").Replace("`r","`n"); if(-not $t.EndsWith("`n")){ $t+="`n" }; $enc=New-Object System.Text.UTF8Encoding($false); [System.IO.File]::WriteAllText($Path,$t,$enc) }
function Write-Bytes([string]$Path,[byte[]]$Bytes){ $dir=Split-Path -Parent $Path; if($dir){ Ensure-Dir $dir }; [System.IO.File]::WriteAllBytes($Path,$Bytes) }
function Read-Bytes([string]$Path){ if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("MISSING_FILE: " + $Path) }; return [System.IO.File]::ReadAllBytes($Path) }
function Sha256HexBytes([byte[]]$b){ if($null -eq $b){ $b=@() }; $sha=[System.Security.Cryptography.SHA256]::Create(); $h=$sha.ComputeHash($b); ($h | ForEach-Object { $_.ToString("x2") }) -join "" }
function Sha256HexFile([string]$p){ Sha256HexBytes (Read-Bytes $p) }

$RepoRoot = $RepoRoot.TrimEnd("\")
$tv = Join-Path $RepoRoot "test_vectors"
Ensure-Dir $tv
$pos = Join-Path $tv "pos_minimal_v1"
$n1  = Join-Path $tv "neg_manifest_contains_packet_id_v1"
$n2  = Join-Path $tv "neg_packet_id_mismatch_v1"
$n3  = Join-Path $tv "neg_sha256_mismatch_v1"
Ensure-Dir $pos; Ensure-Dir $n1; Ensure-Dir $n2; Ensure-Dir $n3

# Helper: write a minimal manifest (canonical bytes) for vectors
function Write-MinManifest([string]$dir,[bool]$IncludePacketId,[string]$PacketIdValue){
  $mPath = Join-Path $dir "manifest.json"
  if($IncludePacketId){
    $txt = '{' + "`n" + '  "schema": "pie.packet_manifest.v1",' + "`n" + '  "kind": "pie_run_packet",' + "`n" + '  "created_utc": "2026-02-23T00:00:00Z",' + "`n" + '  "packet_id": "' + $PacketIdValue + '"' + "`n" + '}' + "`n"
  } else {
    $txt = '{' + "`n" + '  "schema": "pie.packet_manifest.v1",' + "`n" + '  "kind": "pie_run_packet",' + "`n" + '  "created_utc": "2026-02-23T00:00:00Z"' + "`n" + '}' + "`n"
  }
  Write-Utf8NoBomLf $mPath $txt
  return $mPath
}

# Helper: generate packet_id.txt from manifest bytes (Option A nucleus)
function Write-PacketIdFromManifest([string]$dir){
  $mPath = Join-Path $dir "manifest.json"
  $pidPath = Join-Path $dir "packet_id.txt"
  $packetId = Sha256HexFile $mPath
  Write-Utf8NoBomLf $pidPath ($packetId + "`n")
  return $packetId
}

# Helper: write sha256sums.txt LAST with correct hashes (unless caller mutates)
function Write-ShaSums([string]$dir){
  $sha = Join-Path $dir "sha256sums.txt"
  $mPath = Join-Path $dir "manifest.json"
  $pidPath = Join-Path $dir "packet_id.txt"
  $lines = New-Object System.Collections.Generic.List[string]
  [void]$lines.Add((Sha256HexFile $mPath) + "  manifest.json")
  if(Test-Path -LiteralPath $pidPath -PathType Leaf){ [void]$lines.Add((Sha256HexFile $pidPath) + "  packet_id.txt") }
  Write-Utf8NoBomLf $sha ((($lines.ToArray()) -join "`n") + "`n")
}

# POS: valid minimal vector
Write-MinManifest $pos $false "" | Out-Null
$posPid = Write-PacketIdFromManifest $pos
Write-ShaSums $pos

# NEG1: manifest contains packet_id (verifier must fail for this reason)
Write-MinManifest $n1 $true ("deadbeef" + ("0" * 56)) | Out-Null
# packet_id.txt exists but should not matter (still keep consistent hashes for determinism)
Write-Utf8NoBomLf (Join-Path $n1 "packet_id.txt") (Sha256HexFile (Join-Path $n1 "manifest.json") + "`n")
Write-ShaSums $n1

# NEG2: packet_id mismatch (sha256sums correct, packet_id.txt wrong)
Write-MinManifest $n2 $false "" | Out-Null
$truePid = Sha256HexFile (Join-Path $n2 "manifest.json")
$wrongPid = ("0" * 64)
Write-Utf8NoBomLf (Join-Path $n2 "packet_id.txt") ($wrongPid + "`n")
Write-ShaSums $n2

# NEG3: sha256 mismatch (tamper sha256sums.txt AFTER generating correct files)
Write-MinManifest $n3 $false "" | Out-Null
$n3Pid = Write-PacketIdFromManifest $n3
Write-ShaSums $n3
# Now mutate sha256sums.txt to force mismatch deterministically by changing manifest hash
$shaPath = Join-Path $n3 "sha256sums.txt"
$lines = (Get-Content -LiteralPath $shaPath -Encoding UTF8)
$out = New-Object System.Collections.Generic.List[string]
for($i=0;$i -lt $lines.Length;$i++){
  $ln = $lines[$i].TrimEnd()
  if($ln -match "\s+manifest\.json$"){
    $parts = $ln -split "\s+"
    $bad = ("f" * 64)
    [void]$out.Add($bad + "  manifest.json")
  } else { [void]$out.Add($ln) }
}
Write-Utf8NoBomLf $shaPath ((($out.ToArray()) -join "`n") + "`n")

Write-Host ("PIE_VECTORS_OK: " + $tv) -ForegroundColor Green
Write-Host ("  POS: " + $pos) -ForegroundColor Green
Write-Host ("  NEG1: " + $n1) -ForegroundColor Green
Write-Host ("  NEG2: " + $n2) -ForegroundColor Green
Write-Host ("  NEG3: " + $n3) -ForegroundColor Green
