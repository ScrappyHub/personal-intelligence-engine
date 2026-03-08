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

# Locate ssh-keygen -Y sign
$idx = $txt.IndexOf("ssh-keygen -Y sign",[System.StringComparison]::OrdinalIgnoreCase)
if ($idx -lt 0) { Die ("patch_fail: could not find `ssh-keygen -Y sign` in signer (backup=" + $bak + ")") }
$sub = $txt.Substring($idx)

# After ssh-keygen call, signer currently treats any output as fatal. Replace that with exit-code gating.
$m = [regex]::Match($sub, '(?is)if\s*\(\s*\$out\s*\)\s*\{\s*(Die|throw)\b.*?\}' )
if (-not $m.Success) { Die ("patch_fail: could not find `if ($out) { Die/throw ... }` after ssh-keygen call (backup=" + $bak + ")") }

$old = $m.Value
$new = @(
  'if ($LASTEXITCODE -ne 0) {',
  '  $o = @(@($out)) -join "`n"',
  '  Die ("ssh-keygen -Y sign failed (exit=" + $LASTEXITCODE + "): " + $o)',
  '}'
) -join "`n"

$sub2 = $sub.Replace($old, $new)
if ($sub2 -eq $sub) { Die ("patch_fail: replace produced no change (backup=" + $bak + ")") }
$txt2 = $txt.Substring(0,$idx) + $sub2
Parse-GateText $txt2
Write-Utf8NoBomLf $sp $txt2
Write-Host ("PATCH_OK: signer now gates on LASTEXITCODE (ignores normal ssh-keygen chatter) (backup=" + $bak + ")") -ForegroundColor Green
