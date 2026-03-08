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

$sent = "# --- PIE_PATCH_SIGNER_EXITCODE_GATE_V5 ---"
if ($txt -like ("*" + $sent + "*")) { Write-Host ("OK: signer already patched (backup=" + $bak + ")") -ForegroundColor Yellow; return }

# Find a block that captures ssh-keygen output to $X then does: if($X){ throw/Die ... }
$re = '(?is)(\$\w+)\s*=\s*&[^\r\n]*\b-Y\b[^\r\n]*\bsign\b[^\r\n]*[\r\n]+(?:[^\r\n]*[\r\n]+){0,25}?if\s*\(\s*\1\s*\)\s*\{[\s\S]{0,2500}?\}'
$m = [regex]::Match($txt, $re)
if (-not $m.Success) {
  $snip = @()
  $snip += "DIAG: could not locate capture+if(<var>) throw block."
  $snip += "DIAG: lines containing Signing file / ssh-keygen / -Y / sign:"
  $ls = $txt -split "`n"
  for($i=0;$i -lt $ls.Length;$i++){
    $ln = $ls[$i]
    if($ln -match "(?i)Signing file|ssh-keygen|\b-Y\b|\bsign\b"){ $snip += ("L" + ($i+1) + ": " + $ln.TrimEnd()) }
  }
  Die ( ($snip -join "`n") + "`nbackup=" + $bak )
}

$block = $m.Value
$capVar = $m.Groups[1].Value
$ifRe = '(?is)if\s*\(\s*' + [regex]::Escape($capVar) + '\s*\)\s*\{[\s\S]{0,2500}?\}'
$newIf = @(
  $sent,
  'if ($LASTEXITCODE -ne 0) {',
  '  $o = @(@(' + $capVar + ')) -join "`n"',
  '  Die ("ssh-keygen -Y sign failed (exit=" + $LASTEXITCODE + "): " + $o)',
  '}'
) -join "`n"
$block2 = [regex]::Replace($block, $ifRe, $newIf, 1)
if ($block2 -eq $block) { Die ("patch_fail: internal replace produced no change (backup=" + $bak + ")") }
$txt2 = $txt.Replace($block, $block2)
Parse-GateText $txt2
Write-Utf8NoBomLf $sp $txt2
Write-Host ("PATCH_OK: signer now gates on LASTEXITCODE (backup=" + $bak + ")") -ForegroundColor Green
