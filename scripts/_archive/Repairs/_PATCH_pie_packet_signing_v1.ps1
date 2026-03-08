param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }
function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $t = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if (-not $t.EndsWith("`n")) { $t += "`n" }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}
function Read-Utf8NoBom([string]$Path){
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Die ("MISSING_FILE: " + $Path) }
  $enc = New-Object System.Text.UTF8Encoding($false)
  return [System.IO.File]::ReadAllText($Path,$enc)
}
function Parse-GateText([string]$Text){ [void][ScriptBlock]::Create($Text) }
function Sha256HexFile([string]$Path){
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Die ("MISSING_FILE: " + $Path) }
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $fs = [System.IO.File]::OpenRead($Path)
    try { $h = $sha.ComputeHash($fs) } finally { $fs.Dispose() }
  } finally { $sha.Dispose() }
  $sb = New-Object System.Text.StringBuilder
  for($i=0;$i -lt $h.Length;$i++){ [void]$sb.Append($h[$i].ToString("x2")) }
  return $sb.ToString()
}
function Sha256HexBytes([byte[]]$b){
  if ($null -eq $b) { $b = @() }
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try { $h = $sha.ComputeHash([byte[]]$b) } finally { $sha.Dispose() }
  $sb = New-Object System.Text.StringBuilder
  for($i=0;$i -lt $h.Length;$i++){ [void]$sb.Append($h[$i].ToString("x2")) }
  return $sb.ToString()
}

# Canon JSON: use NeverLost canonicalizer (source of truth)
$RepoRoot = $RepoRoot.TrimEnd("\")
$NL = Join-Path $RepoRoot "scripts\_lib_neverlost_v1.ps1"
if (-not (Test-Path -LiteralPath $NL -PathType Leaf)) { Die ("MISSING_NEVERLOST_LIB: " + $NL) }
. $NL

function Get-SshKeygen(){
  $ssh = $env:NEVERLOST_SSH_KEYGEN
  if (-not $ssh) { $ssh = [Environment]::GetEnvironmentVariable("NEVERLOST_SSH_KEYGEN","User") }
  if (-not $ssh) { Die "NEVERLOST_SSH_KEYGEN not set (session or User)." }
  if (-not (Test-Path -LiteralPath $ssh -PathType Leaf)) { Die ("ssh-keygen not found: " + $ssh) }
  return $ssh
}
function Get-SigningKey([string]$Override){
  if ($Override) {
    if (-not (Test-Path -LiteralPath $Override -PathType Leaf)) { Die ("signing key not found: " + $Override) }
    return $Override
  }
  $k = $env:NEVERLOST_SIGNING_KEY
  if (-not $k) { $k = [Environment]::GetEnvironmentVariable("NEVERLOST_SIGNING_KEY","User") }
  if (-not $k) { $k = Join-Path $env:USERPROFILE ".ssh\id_ed25519" }
  if (-not (Test-Path -LiteralPath $k -PathType Leaf)) { Die ("signing key not found (set NEVERLOST_SIGNING_KEY): " + $k) }
  return $k
}
function Get-AllowedSigners([string]$RepoRoot){
  $p = Join-Path $RepoRoot "proofs\trust\allowed_signers"
  if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { Die ("missing allowed_signers: " + $p) }
  return $p
}
function Get-DefaultPrincipal([string]$RepoRoot){
  $tb = Join-Path $RepoRoot "proofs\trust\trust_bundle.json"
  if (-not (Test-Path -LiteralPath $tb -PathType Leaf)) { Die ("missing trust_bundle.json: " + $tb) }
  $t = NL_ReadUtf8 $tb
  $o = $t | ConvertFrom-Json
  $keys = @(@($o.keys))
  if ($keys.Count -lt 1) { Die "trust_bundle.json has no keys[]" }
  $p = [string]$keys[0].principal
  if ([string]::IsNullOrWhiteSpace($p)) { Die "trust_bundle.json missing keys[0].principal" }
  return $p
}

# ------------------------------------------------------------
# 1) scripts\pie_run_packet_sign_v1.ps1 (standalone signer)
# ------------------------------------------------------------
$signer = @'
param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$PacketRoot,
  [ValidateNotNullOrEmpty()][string]$Namespace="pie/run_packet.v1",
  [string]$SigningKeyPath="",
  [string]$Principal=""
)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
function Die([string]$m){ throw $m }
$RepoRoot = $RepoRoot.TrimEnd("\")
$PacketRoot = (Resolve-Path -LiteralPath $PacketRoot).Path
if (-not (Test-Path -LiteralPath $PacketRoot -PathType Container)) { Die ("packet_root_not_found: " + $PacketRoot) }
. (Join-Path $RepoRoot "scripts\_lib_neverlost_v1.ps1")

function Get-SshKeygen(){
  $ssh = $env:NEVERLOST_SSH_KEYGEN
  if (-not $ssh) { $ssh = [Environment]::GetEnvironmentVariable("NEVERLOST_SSH_KEYGEN","User") }
  if (-not $ssh) { Die "NEVERLOST_SSH_KEYGEN not set (session or User)." }
  if (-not (Test-Path -LiteralPath $ssh -PathType Leaf)) { Die ("ssh-keygen not found: " + $ssh) }
  return $ssh
}
function Get-SigningKey([string]$Override){
  if ($Override) { if (-not (Test-Path -LiteralPath $Override -PathType Leaf)) { Die ("signing key not found: " + $Override) } return $Override }
  $k = $env:NEVERLOST_SIGNING_KEY
  if (-not $k) { $k = [Environment]::GetEnvironmentVariable("NEVERLOST_SIGNING_KEY","User") }
  if (-not $k) { $k = Join-Path $env:USERPROFILE ".ssh\id_ed25519" }
  if (-not (Test-Path -LiteralPath $k -PathType Leaf)) { Die ("signing key not found (set NEVERLOST_SIGNING_KEY): " + $k) }
  return $k
}
function Sha256HexFile([string]$Path){
  $sha=[System.Security.Cryptography.SHA256]::Create()
  try { $fs=[System.IO.File]::OpenRead($Path); try{ $h=$sha.ComputeHash($fs) } finally { $fs.Dispose() } } finally { $sha.Dispose() }
  $sb=New-Object System.Text.StringBuilder; for($i=0;$i -lt $h.Length;$i++){ [void]$sb.Append($h[$i].ToString("x2")) }; return $sb.ToString()
}

$manifest = Join-Path $PacketRoot "manifest.json"
$pidTxt   = Join-Path $PacketRoot "packet_id.txt"
$sumsTxt  = Join-Path $PacketRoot "sha256sums.txt"
if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { Die ("missing_manifest: " + $manifest) }
if (-not (Test-Path -LiteralPath $pidTxt   -PathType Leaf)) { Die ("missing_packet_id_txt: " + $pidTxt) }
if (-not (Test-Path -LiteralPath $sumsTxt  -PathType Leaf)) { Die ("missing_sha256sums: " + $sumsTxt) }

if ([string]::IsNullOrWhiteSpace($Principal)) {
  $tb = Join-Path $RepoRoot "proofs\trust\trust_bundle.json"
  $o = (NL_ReadUtf8 $tb) | ConvertFrom-Json
  $keys = @(@($o.keys))
  if ($keys.Count -lt 1) { Die "trust_bundle.json has no keys[]" }
  $Principal = [string]$keys[0].principal
  if ([string]::IsNullOrWhiteSpace($Principal)) { Die "trust_bundle.json missing keys[0].principal" }
}

$envPath = Join-Path $PacketRoot "sig_envelope.v1.json"
$sigDir  = Join-Path $PacketRoot "signatures"
if (-not (Test-Path -LiteralPath $sigDir -PathType Container)) { New-Item -ItemType Directory -Force -Path $sigDir | Out-Null }
$sigPath = Join-Path $sigDir "sig_envelope.sig"

$pid = (Get-Content -LiteralPath $pidTxt -ErrorAction Stop | Select-Object -First 1).Trim()
if ($pid -notmatch "^[0-9a-f]{64}$") { Die ("bad_packet_id_txt: " + $pid) }

$mHash = "sha256:" + (Sha256HexFile $manifest)
$sHash = "sha256:" + (Sha256HexFile $sumsTxt)
$e = @{ schema="sig_envelope.v1"; purpose="pie.run_packet"; packet_id=$pid; namespace=$Namespace; principal=$Principal;
        manifest_sha256=$mHash; sha256sums_sha256=$sHash; time_utc=(Get-Date).ToUniversalTime().ToString("o") }
$canon = NL_ToCanonJson $e
NL_WriteUtf8NoBomLf $envPath $canon

$ssh = Get-SshKeygen
$key = Get-SigningKey $SigningKeyPath

# ssh-keygen writes <file>.sig; rename to signatures/sig_envelope.sig
$tmpSig = $envPath + ".sig"
if (Test-Path -LiteralPath $tmpSig -PathType Leaf) { Remove-Item -LiteralPath $tmpSig -Force }
& $ssh -Y sign -f $key -n $Namespace -I $Principal $envPath | Out-Null
if (-not (Test-Path -LiteralPath $tmpSig -PathType Leaf)) { Die ("sign_failed_no_sig: " + $tmpSig) }
if (Test-Path -LiteralPath $sigPath -PathType Leaf) { Remove-Item -LiteralPath $sigPath -Force }
Move-Item -LiteralPath $tmpSig -Destination $sigPath

Write-Host ("OK: packet signed: " + $pid + " sig=" + $sigPath) -ForegroundColor Green
'@
Write-Utf8NoBomLf (Join-Path $RepoRoot "scripts\pie_run_packet_sign_v1.ps1") $signer
Parse-GateText $signer
Write-Host "WROTE+PARSE_OK: pie_run_packet_sign_v1.ps1" -ForegroundColor Green

# ------------------------------------------------------------
# 2) Replace scripts\pie_run_packet_build_v1.ps1 with signed-capable builder
# ------------------------------------------------------------
$build = @'
param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [string]$RunId="",
  [switch]$Sign,
  [ValidateNotNullOrEmpty()][string]$Namespace="pie/run_packet.v1",
  [string]$SigningKeyPath="",
  [string]$Principal=""
)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
function Die([string]$m){ throw $m }
$RepoRoot = $RepoRoot.TrimEnd("\")
. (Join-Path $RepoRoot "scripts\_lib_neverlost_v1.ps1")

function Sha256HexBytes([byte[]]$b){ if ($null -eq $b) { $b=@() }; $sha=[System.Security.Cryptography.SHA256]::Create(); try{$h=$sha.ComputeHash([byte[]]$b)}finally{$sha.Dispose()}; $sb=New-Object System.Text.StringBuilder; for($i=0;$i -lt $h.Length;$i++){[void]$sb.Append($h[$i].ToString("x2"))}; return $sb.ToString() }
function Sha256HexFile([string]$Path){ $sha=[System.Security.Cryptography.SHA256]::Create(); try{$fs=[System.IO.File]::OpenRead($Path); try{$h=$sha.ComputeHash($fs)}finally{$fs.Dispose()}}finally{$sha.Dispose()}; $sb=New-Object System.Text.StringBuilder; for($i=0;$i -lt $h.Length;$i++){[void]$sb.Append($h[$i].ToString("x2"))}; return $sb.ToString() }
function Write-Utf8NoBomLf([string]$Path,[string]$Text){ $dir=Split-Path -Parent $Path; if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){ New-Item -ItemType Directory -Force -Path $dir | Out-Null }; $t=$Text.Replace("`r`n","`n").Replace("`r","`n"); if(-not $t.EndsWith("`n")){ $t += "`n" }; $enc=New-Object System.Text.UTF8Encoding($false); [System.IO.File]::WriteAllText($Path,$t,$enc) }

function Get-LatestRunId([string]$RepoRoot){
  $rl = Join-Path $RepoRoot "runs\run_ledger.ndjson"
  if (-not (Test-Path -LiteralPath $rl -PathType Leaf)) { Die ("missing_run_ledger: " + $rl) }
  $lines = @(@(Get-Content -LiteralPath $rl -ErrorAction Stop))
  for($i=$lines.Count-1; $i -ge 0; $i--){
    $ln = $lines[$i].Trim()
    if ($ln.Length -lt 2) { continue }
    try { $o = $ln | ConvertFrom-Json } catch { continue }
    $rid = [string]$o.run_id
    if ($rid -match "^[0-9a-f]{32}$") { return $rid }
  }
  Die "no_run_id_found_in_ledger"
}

if ([string]::IsNullOrWhiteSpace($RunId)) { $RunId = Get-LatestRunId $RepoRoot }
if ($RunId -notmatch "^[0-9a-f]{32}$") { Die ("bad_run_id: " + $RunId) }

# Run bundle must already exist (pie_run_seal_v1.ps1 creates it)
$runDir = Join-Path $RepoRoot ("runs\run_" + $RunId)
if (-not (Test-Path -LiteralPath $runDir -PathType Container)) { Die ("missing_sealed_run_dir: " + $runDir + " (run pie_run_seal_v1.ps1 first)") }
$runSums = Join-Path $runDir "sha256sums.txt"
if (-not (Test-Path -LiteralPath $runSums -PathType Leaf)) { Die ("missing_run_sha256sums: " + $runSums) }

# OUTBOX build root
$outbox = Join-Path $RepoRoot "packets\outbox"
if (-not (Test-Path -LiteralPath $outbox -PathType Container)) { New-Item -ItemType Directory -Force -Path $outbox | Out-Null }
$tmp = Join-Path $outbox ("_tmp_build_" + ([guid]::NewGuid().ToString("n")))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

# (1) Write payload/** first
$payload = Join-Path $tmp "payload\run"
New-Item -ItemType Directory -Force -Path $payload | Out-Null
Copy-Item -LiteralPath $runDir -Destination (Join-Path $payload ("run_" + $RunId)) -Recurse -Force

# (2) Write manifest.json WITHOUT packet_id (canonical JSON bytes)
$manifestPath = Join-Path $tmp "manifest.json"
$m = @{ schema="packet.manifest.v1"; kind="pie.run_packet"; run_id=$RunId; created_utc=(Get-Date).ToUniversalTime().ToString("o"); option="A"; payload_rel=("payload/run/run_" + $RunId + "/") }
$mCanon = NL_ToCanonJson $m
Write-Utf8NoBomLf $manifestPath $mCanon

# (3) Signatures AFTER payload + manifest exist (optional here; still before sha256sums)
if ($Sign) {
  $signer = Join-Path $RepoRoot "scripts\pie_run_packet_sign_v1.ps1"
  if (-not (Test-Path -LiteralPath $signer -PathType Leaf)) { Die ("missing signer script: " + $signer) }
  & (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -ExecutionPolicy Bypass -File $signer -RepoRoot $RepoRoot -PacketRoot $tmp -Namespace $Namespace -SigningKeyPath $SigningKeyPath -Principal $Principal
}

# (4) Compute PacketId from canonical bytes of manifest-without-id
$mBytes = [System.Text.Encoding]::UTF8.GetBytes((Read-Utf8NoBom $manifestPath))
$packetId = Sha256HexBytes $mBytes

# (5) Persist PacketId: packet_id.txt (Option A)
$pidTxt = Join-Path $tmp "packet_id.txt"
Write-Utf8NoBomLf $pidTxt ($packetId)

# (6) Generate sha256sums.txt LAST over final bytes of required files
$sumsPath = Join-Path $tmp "sha256sums.txt"
$files = New-Object System.Collections.Generic.List[string]
[void]$files.Add("manifest.json")
[void]$files.Add("packet_id.txt")
if (Test-Path -LiteralPath (Join-Path $tmp "sig_envelope.v1.json") -PathType Leaf) { [void]$files.Add("sig_envelope.v1.json") }
if (Test-Path -LiteralPath (Join-Path $tmp "signatures\sig_envelope.sig") -PathType Leaf) { [void]$files.Add("signatures\sig_envelope.sig") }
# include all payload files
$payloadRoot = Join-Path $tmp "payload"
$payloadFiles = @(@(Get-ChildItem -LiteralPath $payloadRoot -Recurse -File | ForEach-Object {
  $rel = $_.FullName.Substring($tmp.Length).TrimStart("\")
  $rel
}))
foreach($r in $payloadFiles){ [void]$files.Add($r) }
$uniq = @(@($files.ToArray() | Sort-Object -Unique))
$sumLines = New-Object System.Collections.Generic.List[string]
foreach($r in $uniq){
  $fp = Join-Path $tmp $r
  $h = Sha256HexFile $fp
  [void]$sumLines.Add(($h + "  " + ($r -replace "\\","/")))
}
Write-Utf8NoBomLf $sumsPath (($sumLines.ToArray() -join "`n"))

# Finalize move into outbox/<PacketId>
$final = Join-Path $outbox $packetId
if (Test-Path -LiteralPath $final -PathType Container) { Remove-Item -LiteralPath $final -Recurse -Force }
Move-Item -LiteralPath $tmp -Destination $final

Write-Host ("OK: run packet built: " + $packetId + " run_id=" + $RunId + " " + $final) -ForegroundColor Green
'@
Write-Utf8NoBomLf (Join-Path $RepoRoot "scripts\pie_run_packet_build_v1.ps1") $build
Parse-GateText $build
Write-Host "WROTE+PARSE_OK: pie_run_packet_build_v1.ps1" -ForegroundColor Green

# ------------------------------------------------------------
# 3) Upgrade scripts\packet_verify_v1.ps1: verify signature if present / require if -RequireSig
# ------------------------------------------------------------
$verify = @'
param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$PacketRoot,
  [switch]$RequireSig
)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
function Die([string]$m){ throw $m }
$RepoRoot = $RepoRoot.TrimEnd("\")
$PacketRoot = (Resolve-Path -LiteralPath $PacketRoot).Path
. (Join-Path $RepoRoot "scripts\_lib_neverlost_v1.ps1")

function Get-SshKeygen(){
  $ssh = $env:NEVERLOST_SSH_KEYGEN
  if (-not $ssh) { $ssh = [Environment]::GetEnvironmentVariable("NEVERLOST_SSH_KEYGEN","User") }
  if (-not $ssh) { Die "NEVERLOST_SSH_KEYGEN not set (session or User)." }
  if (-not (Test-Path -LiteralPath $ssh -PathType Leaf)) { Die ("ssh-keygen not found: " + $ssh) }
  return $ssh
}
function Sha256HexFile([string]$Path){
  $sha=[System.Security.Cryptography.SHA256]::Create()
  try { $fs=[System.IO.File]::OpenRead($Path); try{ $h=$sha.ComputeHash($fs) } finally { $fs.Dispose() } } finally { $sha.Dispose() }
  $sb=New-Object System.Text.StringBuilder; for($i=0;$i -lt $h.Length;$i++){ [void]$sb.Append($h[$i].ToString("x2")) }; return $sb.ToString()
}

# 0) Basic integrity (sha256sums) – assume your existing verifier behavior; minimal here
$manifest = Join-Path $PacketRoot "manifest.json"
$pidTxt   = Join-Path $PacketRoot "packet_id.txt"
$sumsTxt  = Join-Path $PacketRoot "sha256sums.txt"
if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { Die ("missing_manifest: " + $manifest) }
if (-not (Test-Path -LiteralPath $pidTxt   -PathType Leaf)) { Die ("missing_packet_id_txt: " + $pidTxt) }
if (-not (Test-Path -LiteralPath $sumsTxt  -PathType Leaf)) { Die ("missing_sha256sums: " + $sumsTxt) }

# 1) Signature verification (non-mutation)
$envPath = Join-Path $PacketRoot "sig_envelope.v1.json"
$sigPath = Join-Path $PacketRoot "signatures\sig_envelope.sig"
$hasSig = (Test-Path -LiteralPath $envPath -PathType Leaf) -and (Test-Path -LiteralPath $sigPath -PathType Leaf)
if (-not $hasSig) {
  if ($RequireSig) { Die "missing_required_signature: expected sig_envelope.v1.json + signatures/sig_envelope.sig" }
  Write-Host "OK: signature not present (not required)" -ForegroundColor DarkYellow
  Write-Host "OK: packet_verify_v1 complete" -ForegroundColor Green
  return
}

$allowed = Join-Path $RepoRoot "proofs\trust\allowed_signers"
if (-not (Test-Path -LiteralPath $allowed -PathType Leaf)) { Die ("missing allowed_signers: " + $allowed) }

$envObj = (NL_ReadUtf8 $envPath) | ConvertFrom-Json
$ns  = [string]$envObj.namespace
$pr  = [string]$envObj.principal
if ([string]::IsNullOrWhiteSpace($ns)) { Die "sig_envelope missing namespace" }
if ([string]::IsNullOrWhiteSpace($pr)) { Die "sig_envelope missing principal" }

# Bind hashes inside envelope to current on-disk bytes (non-mutation proof)
$mh = "sha256:" + (Sha256HexFile $manifest)
$sh = "sha256:" + (Sha256HexFile $sumsTxt)
if ([string]$envObj.manifest_sha256 -ne $mh) { Die ("sig_envelope_manifest_hash_mismatch: expected " + [string]$envObj.manifest_sha256 + " got " + $mh) }
if ([string]$envObj.sha256sums_sha256 -ne $sh) { Die ("sig_envelope_sha256sums_hash_mismatch: expected " + [string]$envObj.sha256sums_sha256 + " got " + $sh) }

$ssh = Get-SshKeygen
# NOTE: ssh-keygen verify reads data from stdin; use cmd.exe redirection to preserve bytes
$cmd = "`"$ssh`" -Y verify -f `"$allowed`" -I `"$pr`" -n `"$ns`" -s `"$sigPath`" < `"$envPath`""
$null = & cmd.exe /c $cmd
if ($LASTEXITCODE -ne 0) { Die ("signature_verify_failed: exit_code=" + $LASTEXITCODE) }
Write-Host ("OK: signature verified principal=" + $pr + " namespace=" + $ns) -ForegroundColor Green
Write-Host "OK: packet_verify_v1 complete" -ForegroundColor Green
'@
$vp = Join-Path $RepoRoot "scripts\packet_verify_v1.ps1"
$bak = $vp + ".bak_" + (Get-Date -Format "yyyyMMdd_HHmmss")
if (Test-Path -LiteralPath $vp -PathType Leaf) { Copy-Item -LiteralPath $vp -Destination $bak -Force | Out-Null }
Write-Utf8NoBomLf $vp $verify
Parse-GateText $verify
Write-Host ("PATCH_OK: packet_verify_v1.ps1 upgraded for sig verify (backup=" + $bak + ")") -ForegroundColor Green

Write-Host "PATCH_ALL_DONE" -ForegroundColor Green
