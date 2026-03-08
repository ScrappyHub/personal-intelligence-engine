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
$sent = "# --- PIE_PATCH_SIGNER_LASTEXITCODE_GATE_V4 ---"
if ($txt -like ("*" + $sent + "*")) { Write-Host ("OK: signer already patched (backup=" + $bak + ")") -ForegroundColor Yellow; return }

$ls = $txt -split "`n"

# Find capture line: $X = & $ssh -Y sign ... 2>&1
$capIdx = -1
$capVar = $null
for($i=0;$i -lt $ls.Length;$i++){
  $ln = $ls[$i]
  $m = [regex]::Match($ln, '(?i)^\s*(\$\w+)\s*=\s*&\s*\$ssh\b.*\b-Y\b.*\bsign\b.*2>&1\s*$')
  if($m.Success){ $capIdx=$i; $capVar=$m.Groups[1].Value; break }
}
if ($capIdx -lt 0 -or [string]::IsNullOrWhiteSpace($capVar)) {
  $sn=@()
  $sn += 'patch_fail: could not find capture sign line (expected: $X = & $ssh -Y sign ... 2>&1).'
  $sn += ("backup=" + $bak)
  $sn += 'DIAG: candidate lines:'
  for($j=0;$j -lt $ls.Length;$j++){ $l2=$ls[$j]; if($l2 -match "(?i)\b-Y\b|\bsign\b|2>&1|signOut|LASTEXITCODE"){ $sn += ("L" + ($j+1) + ": " + $l2.TrimEnd()) } }
  Die (($sn -join "`n"))
}

# Find following if ($capVar) { ... } block (within next 60 lines)
$ifStart = -1
$ifRe = '(?i)^\s*if\s*\(\s*' + [regex]::Escape($capVar) + '\s*\)\s*\{'
$maxLook = [Math]::Min($ls.Length-1, $capIdx + 60)
for($i=$capIdx+1; $i -le $maxLook; $i++){ if([regex]::IsMatch($ls[$i], $ifRe)){ $ifStart=$i; break } }
if ($ifStart -lt 0) {
  $sn=@()
  $sn += ("patch_fail: could not find if(" + $capVar + "){...} block after capture line.")
  $sn += ("backup=" + $bak)
  $sn += 'DIAG: window after capture:'
  for($j=$capIdx; $j -le $maxLook; $j++){ $sn += ("L" + ($j+1) + ": " + $ls[$j].TrimEnd()) }
  Die (($sn -join "`n"))
}

# Determine end of that if-block by brace depth scanning
$depth = 0
$ifEnd = -1
for($i=$ifStart; $i -lt $ls.Length; $i++){
  $line = $ls[$i]
  $opens = [regex]::Matches($line, '\{').Count
  $closes = [regex]::Matches($line, '\}').Count
  $depth += ($opens - $closes)
  if ($i -eq $ifStart -and $depth -le 0) { $depth = 1 }
  if ($depth -eq 0) { $ifEnd = $i; break }
}
if ($ifEnd -lt $ifStart) { Die ("patch_fail: could not determine end of if-block. backup=" + $bak) }

# Preserve indent from the if line
$indent = ""
$im = [regex]::Match($ls[$ifStart], '(?m)^(?<i>\s*)if\b')
if ($im.Success) { $indent = $im.Groups["i"].Value }

# Replacement block
$new = New-Object System.Collections.Generic.List[string]
[void]$new.Add($indent + $sent)
[void]$new.Add($indent + 'if ($LASTEXITCODE -ne 0) {')
[void]$new.Add($indent + '  $o = @(@(' + $capVar + ')) -join "`n"')
[void]$new.Add($indent + '  Die ("ssh-keygen -Y sign failed (exit=" + $LASTEXITCODE + "): " + $o)')
[void]$new.Add($indent + '}')

# Splice lines
$out = New-Object System.Collections.Generic.List[string]
for($i=0;$i -lt $ls.Length;$i++){
  if ($i -eq $ifStart) { foreach($nl in $new){ [void]$out.Add($nl) }; $i = $ifEnd; continue }
  [void]$out.Add($ls[$i])
}
$txt2 = (($out.ToArray()) -join "`n") + "`n"
Parse-GateText $txt2
Write-Utf8NoBomLf $sp $txt2
Write-Host ("PATCH_OK: signer now gates on LASTEXITCODE (backup=" + $bak + ")") -ForegroundColor Green
