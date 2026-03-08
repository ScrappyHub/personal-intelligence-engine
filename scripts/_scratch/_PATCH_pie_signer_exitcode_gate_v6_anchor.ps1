param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
function Die([string]$m){ throw $m }
function Read-Utf8NoBom([string]$Path){ if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("MISSING_FILE: " + $Path) }; $enc=New-Object System.Text.UTF8Encoding($false); return [System.IO.File]::ReadAllText($Path,$enc) }
function Write-Utf8NoBomLf([string]$Path,[string]$Text){ $dir=Split-Path -Parent $Path; if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){ New-Item -ItemType Directory -Force -Path $dir | Out-Null }; $t=$Text.Replace("`r`n","`n").Replace("`r","`n"); if(-not $t.EndsWith("`n")){ $t += "`n" }; $enc=New-Object System.Text.UTF8Encoding($false); [System.IO.File]::WriteAllText($Path,$t,$enc) }
function Parse-GateText([string]$Text){ [void][ScriptBlock]::Create($Text) }

$RepoRoot = $RepoRoot.TrimEnd("\")
$sp = Join-Path $RepoRoot "scripts\pie_run_packet_sign_v1.ps1"
if (-not (Test-Path -LiteralPath $sp -PathType Leaf)) { Die ("missing signer: " + $sp) }
$bak = $sp + ".bak_" + (Get-Date -Format "yyyyMMdd_HHmmss")
Copy-Item -LiteralPath $sp -Destination $bak -Force | Out-Null
$txt = Read-Utf8NoBom $sp

$sent = "# --- PIE_PATCH_SIGNER_EXITCODE_GATE_V6 ---"
if ($txt -like ("*" + $sent + "*")) { Write-Host ("OK: signer already patched (backup=" + $bak + ")") -ForegroundColor Yellow; return }

# Anchor: the ssh-keygen sign invocation currently piped to Out-Null
$re = '(?im)^\s*&\s*\$ssh\s+-Y\s+sign\s+-f\s+\$key\s+-n\s+\$Namespace\s+-I\s+\$Principal\s+\$envPath\s*\|\s*Out-Null\s*$'
if ($txt -notmatch $re) {
  $sn = @()
  $sn += "patch_fail: could not find expected sign line to replace."
  $sn += "DIAG: matching candidates containing '-Y sign':"
  $ls = $txt -split "`n"
  for($i=0;$i -lt $ls.Length;$i++){ $ln=$ls[$i]; if($ln -match "(?i)\-Y\s+sign"){ $sn += ("L"+($i+1)+": "+$ln.TrimEnd()) } }
  Die ( ($sn -join "`n") + "`nbackup=" + $bak )
}

$rep = @(
  $sent,
  '$signOut = & $ssh -Y sign -f $key -n $Namespace -I $Principal $envPath 2>&1',
  'if ($LASTEXITCODE -ne 0) {',
  '  $o = @(@($signOut)) -join "`n"',
  '  Die ("ssh-keygen -Y sign failed (exit=" + $LASTEXITCODE + "): " + $o)',
  '}'
) -join "`n"

$txt2 = [regex]::Replace($txt, $re, $rep)
if ($txt2 -eq $txt) { Die ("patch_fail: replace produced no change (backup=" + $bak + ")") }
Parse-GateText $txt2
Write-Utf8NoBomLf $sp $txt2
Write-Host ("PATCH_OK: signer now gates on LASTEXITCODE (backup=" + $bak + ")") -ForegroundColor Green
