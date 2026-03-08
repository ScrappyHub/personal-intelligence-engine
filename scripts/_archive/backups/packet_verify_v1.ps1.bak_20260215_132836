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

function Get-SshKeygen(){ $ssh=$env:NEVERLOST_SSH_KEYGEN; if(-not $ssh){$ssh=[Environment]::GetEnvironmentVariable("NEVERLOST_SSH_KEYGEN","User")} ; if(-not $ssh){Die "NEVERLOST_SSH_KEYGEN not set (session or User)."} ; if(-not (Test-Path -LiteralPath $ssh -PathType Leaf)){Die ("ssh-keygen not found: " + $ssh)} ; return $ssh }
function Sha256HexFile([string]$Path){ $sha=[System.Security.Cryptography.SHA256]::Create(); try{ $fs=[System.IO.File]::OpenRead($Path); try{ $h=$sha.ComputeHash($fs) } finally { $fs.Dispose() } } finally { $sha.Dispose() }; $sb=New-Object System.Text.StringBuilder; for($i=0;$i -lt $h.Length;$i++){ [void]$sb.Append($h[$i].ToString("x2")) }; return $sb.ToString() }

$manifest = Join-Path $PacketRoot "manifest.json"
$pidTxt   = Join-Path $PacketRoot "packet_id.txt"
$sumsTxt  = Join-Path $PacketRoot "sha256sums.txt"
if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { Die ("missing_manifest: " + $manifest) }
if (-not (Test-Path -LiteralPath $pidTxt   -PathType Leaf)) { Die ("missing_packet_id_txt: " + $pidTxt) }
if (-not (Test-Path -LiteralPath $sumsTxt  -PathType Leaf)) { Die ("missing_sha256sums: " + $sumsTxt) }

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

$mh  = "sha256:" + (Sha256HexFile $manifest)
$pidh = "sha256:" + (Sha256HexFile $pidTxt)
if ([string]$envObj.manifest_sha256 -ne $mh) { Die ("sig_envelope_manifest_hash_mismatch: expected " + [string]$envObj.manifest_sha256 + " got " + $mh) }
if ([string]$envObj.packet_id_txt_sha256 -ne $pidh) { Die ("sig_envelope_packet_id_txt_hash_mismatch: expected " + [string]$envObj.packet_id_txt_sha256 + " got " + $pidh) }

$ssh = Get-SshKeygen
# verify via stdin redirection (cmd.exe)
$cmd = "`"$ssh`" -Y verify -f `"$allowed`" -I `"$pr`" -n `"$ns`" -s `"$sigPath`" < `"$envPath`""
$null = & cmd.exe /c $cmd
if ($LASTEXITCODE -ne 0) { Die ("signature_verify_failed: exit_code=" + $LASTEXITCODE) }
Write-Host ("OK: signature verified principal=" + $pr + " namespace=" + $ns) -ForegroundColor Green
Write-Host "OK: packet_verify_v1 complete" -ForegroundColor Green
