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

$sent = "# --- PIE_PATCH_SIGNER_LASTEXITCODE_GATE_V1 ---"
if ($txt -like ("*" + $sent + "*")) { Write-Host ("OK: signer already patched (backup=" + $bak + ")") -ForegroundColor Yellow; return }

# Match: $X = & $ssh -Y sign ... 2>&1  then an if($X){...Die/throw...} shortly after
$re = '(?is)(?<assign>^\s*(?<var>\$\w+)\s*=\s*&\s*\$ssh\b[^\r\n]*\b-Y\b[^\r\n]*\bsign\b[^\r\n]*2>&1\s*$)\s*(?:\r?\n)(?:[^\r\n]*\r?\n){0,20}?(?<if>^\s*if\s*\(\s*\k<var>\s*\)\s*\{[\s\S]{0,2500}?\}\s*)'
$m = [regex]::Match($txt, $re)
if (-not $m.Success) {
  $sn = @()
  $sn += "patch_fail: could not locate '$var = & $ssh -Y sign ... 2>&1' + following if($var){...} block. backup=" + $bak
  $sn += "DIAG: candidate lines (signOut/ssh/-Y/sign/LASTEXITCODE):"
  $ls = $txt -split "`n"
  for($i=0;$i -lt $ls.Length;$i++){ $ln=$ls[$i]; if($ln -match "(?i)\bsignOut\b|\bssh\b|\b-Y\b|\bsign\b|LASTEXITCODE"){ $sn += ("L" + ($i+1) + ": " + $ln.TrimEnd()) } }
  Die (($sn -join "`n"))
}

$varName = $m.Groups["var"].Value
$oldIf   = $m.Groups["if"].Value

$indent = ""
$im = [regex]::Match($oldIf, '(?m)^(?<i>\s*)if\b')
if ($im.Success) { $indent = $im.Groups["i"].Value }

$newLines = @()
$newLines += ($indent + $sent)
$newLines += ($indent + 'if ($LASTEXITCODE -ne 0) {')
$newLines += ($indent + '  $o = @(@(' + $varName + ')) -join "`n"')
$newLines += ($indent + '  Die ("ssh-keygen -Y sign failed (exit=" + $LASTEXITCODE + "): " + $o)')
$newLines += ($indent + '}')
$newIf = ($newLines -join "`n")

$txt2 = $txt.Replace($oldIf, $newIf)
if ($txt2 -eq $txt) { Die ("patch_fail: replace produced no change (backup=" + $bak + ")") }
Parse-GateText $txt2
Write-Utf8NoBomLf $sp $txt2
Write-Host ("PATCH_OK: signer gate is now LASTEXITCODE (backup=" + $bak + ")") -ForegroundColor Green
