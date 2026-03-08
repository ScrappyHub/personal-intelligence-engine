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

$newBlock = @(
  'if ($LASTEXITCODE -ne 0) {',
  '  $o = @(@($out)) -join "`n"',
  '  Die ("sign_failed (exit=" + $LASTEXITCODE + "): " + $o)',
  '}'
) -join "`n"

# Prefer: patch an if($out){Die/throw} near ssh-keygen region if present; else fallback to first such block.
$patched = $false
if ($txt -match "(?is)ssh-keygen") {
  $m = [regex]::Match($txt, '(?is)ssh-keygen[\s\S]{0,2500}?if\s*\(\s*\$out\s*\)\s*\{[\s\S]{0,2000}?\}' )
  if ($m.Success) {
    $old = $m.Value
    $repl = [regex]::Replace($old, '(?is)if\s*\(\s*\$out\s*\)\s*\{[\s\S]{0,2000}?\}', $newBlock, 1)
    if ($repl -eq $old) { Die ("patch_fail: ssh-keygen-region replace produced no change (backup=" + $bak + ")") }
    $txt2 = $txt.Replace($old, $repl)
    $patched = $true
  }
}
if (-not $patched) {
  $m2 = [regex]::Match($txt, '(?is)if\s*\(\s*\$out\s*\)\s*\{[\s\S]{0,2000}?(Die|throw)\b[\s\S]{0,2000}?\}' )
  if (-not $m2.Success) { Die ("patch_fail: could not find any `if ($out) { Die/throw ... }` block in signer (backup=" + $bak + ")") }
  $old2 = $m2.Value
  $txt2 = [regex]::Replace($txt, [regex]::Escape($old2), $newBlock, 1)
  $patched = $true
}

if (-not $patched) { Die ("patch_fail: internal patched=false (backup=" + $bak + ")") }
Parse-GateText $txt2
Write-Utf8NoBomLf $sp $txt2
Write-Host ("PATCH_OK: signer now gates on LASTEXITCODE (backup=" + $bak + ")") -ForegroundColor Green
