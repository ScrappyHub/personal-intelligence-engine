param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
function Die([string]$m){ throw $m }
function Read-Utf8NoBom([string]$Path){ if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("MISSING_FILE: " + $Path) }; $enc=New-Object System.Text.UTF8Encoding($false); return [System.IO.File]::ReadAllText($Path,$enc) }
function Write-Utf8NoBomLf([string]$Path,[string]$Text){ $dir=Split-Path -Parent $Path; if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){ New-Item -ItemType Directory -Force -Path $dir | Out-Null }; $t=$Text.Replace("`r`n","`n").Replace("`r","`n"); if(-not $t.EndsWith("`n")){ $t += "`n" }; $enc=New-Object System.Text.UTF8Encoding($false); [System.IO.File]::WriteAllText($Path,$t,$enc) }
function Parse-GateText([string]$Text){ [void][ScriptBlock]::Create($Text) }
$RepoRoot = $RepoRoot.TrimEnd("\")
$bp = Join-Path $RepoRoot "scripts\pie_run_packet_build_v1.ps1"
if (-not (Test-Path -LiteralPath $bp -PathType Leaf)) { Die ("missing builder: " + $bp) }
$bak = $bp + ".bak_" + (Get-Date -Format "yyyyMMdd_HHmmss")
Copy-Item -LiteralPath $bp -Destination $bak -Force | Out-Null
$txt = Read-Utf8NoBom $bp

# Anchor: the exact invocation line that runs the signer script (must exist).
$needle = '& (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -ExecutionPolicy Bypass -File $signer -RepoRoot $RepoRoot -PacketRoot $tmp -Namespace $Namespace -SigningKeyPath $SigningKeyPath -Principal $Principal'
if ($txt -notmatch [regex]::Escape($needle)) { Die "builder_patch_fail: signer invocation line not found (drift)" }

# If we already patched, detect and no-op (idempotent).
if ($txt -match "sign_requested_but_missing_sig_envelope") {
  Write-Host ("OK: builder already has signing hard-gate (backup=" + $bak + ")") -ForegroundColor Yellow
  return
}

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
Write-Host ("PATCH_OK: builder now hard-requires signature artifacts when -Sign (backup=" + $bak + ")") -ForegroundColor Green
