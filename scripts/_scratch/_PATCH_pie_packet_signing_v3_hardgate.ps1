param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
function Die([string]$m){ throw $m }
function Write-Utf8NoBomLf([string]$Path,[string]$Text){ $dir=Split-Path -Parent $Path; if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){ New-Item -ItemType Directory -Force -Path $dir | Out-Null }; $t=$Text.Replace("`r`n","`n").Replace("`r","`n"); if(-not $t.EndsWith("`n")){ $t += "`n" }; $enc=New-Object System.Text.UTF8Encoding($false); [System.IO.File]::WriteAllText($Path,$t,$enc) }
function Read-Utf8NoBom([string]$Path){ if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("MISSING_FILE: " + $Path) }; $enc=New-Object System.Text.UTF8Encoding($false); return [System.IO.File]::ReadAllText($Path,$enc) }
function Parse-GateText([string]$Text){ [void][ScriptBlock]::Create($Text) }
$RepoRoot = $RepoRoot.TrimEnd("\")
$NL = Join-Path $RepoRoot "scripts\_lib_neverlost_v1.ps1"
if (-not (Test-Path -LiteralPath $NL -PathType Leaf)) { Die ("MISSING_NEVERLOST_LIB: " + $NL) }
. $NL

function Sha256HexFile([string]$Path){
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Die ("MISSING_FILE: " + $Path) }
  $sha=[System.Security.Cryptography.SHA256]::Create()
  try { $fs=[System.IO.File]::OpenRead($Path); try{ $h=$sha.ComputeHash($fs) } finally { $fs.Dispose() } } finally { $sha.Dispose() }
  $sb=New-Object System.Text.StringBuilder; for($i=0;$i -lt $h.Length;$i++){ [void]$sb.Append($h[$i].ToString("x2")) }; return $sb.ToString()
}

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

function Get-SshKeygen(){ $ssh=$env:NEVERLOST_SSH_KEYGEN; if(-not $ssh){$ssh=[Environment]::GetEnvironmentVariable("NEVERLOST_SSH_KEYGEN","User")} ; if(-not $ssh){Die "NEVERLOST_SSH_KEYGEN not set (session or User)."} ; if(-not (Test-Path -LiteralPath $ssh -PathType Leaf)){Die ("ssh-keygen not found: " + $ssh)} ; return $ssh }
function Get-SigningKey([string]$Override){ if($Override){ if(-not (Test-Path -LiteralPath $Override -PathType Leaf)){Die ("signing key not found: " + $Override)}; return $Override } $k=$env:NEVERLOST_SIGNING_KEY; if(-not $k){$k=[Environment]::GetEnvironmentVariable("NEVERLOST_SIGNING_KEY","User")} ; if(-not $k){$k=Join-Path $env:USERPROFILE ".ssh\id_ed25519"} ; if(-not (Test-Path -LiteralPath $k -PathType Leaf)){Die ("signing key not found (set NEVERLOST_SIGNING_KEY): " + $k)} ; return $k }
function Sha256HexFile([string]$Path){ $sha=[System.Security.Cryptography.SHA256]::Create(); try{ $fs=[System.IO.File]::OpenRead($Path); try{ $h=$sha.ComputeHash($fs) } finally { $fs.Dispose() } } finally { $sha.Dispose() }; $sb=New-Object System.Text.StringBuilder; for($i=0;$i -lt $h.Length;$i++){ [void]$sb.Append($h[$i].ToString("x2")) }; return $sb.ToString() }

$manifest = Join-Path $PacketRoot "manifest.json"
$pidTxt   = Join-Path $PacketRoot "packet_id.txt"
if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { Die ("missing_manifest: " + $manifest) }
if (-not (Test-Path -LiteralPath $pidTxt   -PathType Leaf)) { Die ("missing_packet_id_txt: " + $pidTxt) }
$pid = (Get-Content -LiteralPath $pidTxt -ErrorAction Stop | Select-Object -First 1).Trim()
if ($pid -notmatch "^[0-9a-f]{64}$") { Die ("bad_packet_id_txt: " + $pid) }

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

$mHash  = "sha256:" + (Sha256HexFile $manifest)
$pidHash = "sha256:" + (Sha256HexFile $pidTxt)
$e = @{ schema="sig_envelope.v1"; purpose="pie.run_packet"; packet_id=$pid; namespace=$Namespace; principal=$Principal; manifest_sha256=$mHash; packet_id_txt_sha256=$pidHash; time_utc=(Get-Date).ToUniversalTime().ToString("o") }
$canon = NL_ToCanonJson $e
NL_WriteUtf8NoBomLf $envPath $canon

$ssh = Get-SshKeygen
$key = Get-SigningKey $SigningKeyPath
$tmpSig = $envPath + ".sig"
if (Test-Path -LiteralPath $tmpSig -PathType Leaf) { Remove-Item -LiteralPath $tmpSig -Force }
& $ssh -Y sign -f $key -n $Namespace -I $Principal $envPath | Out-Null
if ($LASTEXITCODE -ne 0) { Die ("ssh_keygen_sign_failed: exit_code=" + $LASTEXITCODE) }
if (-not (Test-Path -LiteralPath $tmpSig -PathType Leaf)) { Die ("sign_failed_no_sig: " + $tmpSig) }
if (Test-Path -LiteralPath $sigPath -PathType Leaf) { Remove-Item -LiteralPath $sigPath -Force }
Move-Item -LiteralPath $tmpSig -Destination $sigPath -Force
if (-not (Test-Path -LiteralPath $envPath -PathType Leaf)) { Die ("signer_missing_env_after_write: " + $envPath) }
if (-not (Test-Path -LiteralPath $sigPath -PathType Leaf)) { Die ("signer_missing_sig_after_move: " + $sigPath) }
$msg = "OK: packet signed: " + $pid + " env=" + $envPath + " sig=" + $sigPath
Write-Host $msg -ForegroundColor Green
Write-Output $msg
'@
$sp = Join-Path $RepoRoot "scripts\pie_run_packet_sign_v1.ps1"
$sb = $sp + ".bak_" + (Get-Date -Format "yyyyMMdd_HHmmss")
if (Test-Path -LiteralPath $sp -PathType Leaf) { Copy-Item -LiteralPath $sp -Destination $sb -Force | Out-Null }
Write-Utf8NoBomLf $sp $signer
Parse-GateText $signer
Write-Host ("PATCH_OK: signer v3 hard-gate (backup=" + $sb + ")") -ForegroundColor Green

$bp = Join-Path $RepoRoot "scripts\pie_run_packet_build_v1.ps1"
if (-not (Test-Path -LiteralPath $bp -PathType Leaf)) { Die ("missing builder: " + $bp) }
$bb = $bp + ".bak_" + (Get-Date -Format "yyyyMMdd_HHmmss")
Copy-Item -LiteralPath $bp -Destination $bb -Force | Out-Null
$txt = Read-Utf8NoBom $bp
if ($txt -notmatch "(?is)if\s*\(\s*\$Sign\s*\)\s*\{") { Die "builder_patch_fail: cannot find if($Sign){ block" }

# Insert signature existence checks immediately after signer invocation line
$needle = '& (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -ExecutionPolicy Bypass -File $signer -RepoRoot $RepoRoot -PacketRoot $tmp -Namespace $Namespace -SigningKeyPath $SigningKeyPath -Principal $Principal'
if ($txt -notmatch [regex]::Escape($needle)) { Die "builder_patch_fail: signer invocation line not found (unexpected drift)" }
$ins = $needle + "`n" +
'  $envPath = Join-Path $tmp "sig_envelope.v1.json"' + "`n" +
'  $sigPath = Join-Path $tmp "signatures\sig_envelope.sig"' + "`n" +
'  if (-not (Test-Path -LiteralPath $envPath -PathType Leaf)) {' + "`n" +
'    $ls = @(@(Get-ChildItem -LiteralPath $tmp -Recurse -Force | Select-Object -ExpandProperty FullName))' + "`n" +
'    Die ("sign_requested_but_missing_sig_envelope: " + $envPath + " files=" + ($ls -join ";"))' + "`n" +
'  }' + "`n" +
'  if (-not (Test-Path -LiteralPath $sigPath -PathType Leaf)) {' + "`n" +
'    $ls = @(@(Get-ChildItem -LiteralPath $tmp -Recurse -Force | Select-Object -ExpandProperty FullName))' + "`n" +
'    Die ("sign_requested_but_missing_signature_file: " + $sigPath + " files=" + ($ls -join ";"))' + "`n" +
'  }'
$txt2 = $txt.Replace($needle, $ins)
if ($txt2 -eq $txt) { Die "builder_patch_fail: replace produced no change" }
Parse-GateText $txt2
Write-Utf8NoBomLf $bp $txt2
Write-Host ("PATCH_OK: builder v3 now hard-requires signature artifacts when -Sign (backup=" + $bb + ")") -ForegroundColor Green
Write-Host "PATCH_ALL_DONE" -ForegroundColor Green
