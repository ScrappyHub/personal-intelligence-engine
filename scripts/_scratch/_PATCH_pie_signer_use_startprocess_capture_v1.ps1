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

$sent = "# --- PIE_PATCH_SIGNER_SSHKEYGEN_STARTPROCESS_V1 ---"
if ($txt -like ("*" + $sent + "*")) { Write-Host ("OK: signer already Start-Process patched (backup=" + $bak + ")") -ForegroundColor Yellow; return }

$ls = $txt -split "`n"

# Locate the ssh-keygen sign assignment line (current shape includes 2>&1)
$idx = -1
for($i=0;$i -lt $ls.Length;$i++){
  $ln = $ls[$i]
  if($ln -match '(?i)^\s*\$signOut\s*=\s*&\s*\$ssh\b.*\b-Y\b.*\bsign\b.*\s2>&1\s*$'){ $idx=$i; break }
}
if ($idx -lt 0) {
  $sn=@()
  $sn += "patch_fail: could not find `$signOut = & `$ssh -Y sign ... 2>&1 line."
  $sn += ("backup=" + $bak)
  $sn += "DIAG: candidate lines:"
  for($j=0;$j -lt $ls.Length;$j++){ $l2=$ls[$j]; if($l2 -match "(?i)\bsignOut\b|\bssh\b|\b-Y\b|\bsign\b|2>&1|LASTEXITCODE"){ $sn += ("L" + ($j+1) + ": " + $l2.TrimEnd()) } }
  Die (($sn -join "`n"))
}

# Also remove the next immediate LASTEXITCODE gate blocks after that line (up to 12 lines)
$rmStart = $idx
$rmEnd = $idx
$max = [Math]::Min($ls.Length-1, $idx + 12)
for($k=$idx+1; $k -le $max; $k++){
  $t = $ls[$k].Trim()
  if ($t -match '(?i)^\s*if\s*\(\s*\$LASTEXITCODE\s*-ne\s*0\s*\)' -or $t -match '(?i)^\s*\$o\s*=\s*@\(@\(\$signOut\)\)' -or $t -match '(?i)ssh-keygen\s*-Y\s*sign\s*failed' -or $t -match '(?i)ssh_keygen_sign_failed' -or $t -match '(?i)^\s*\}' ) { $rmEnd = $k; continue }
  if ($rmEnd -gt $idx) { break }
}

# Indent from original signOut line
$indent = ""
$im = [regex]::Match($ls[$idx], '(?m)^(?<i>\s*)\$signOut\b')
if ($im.Success) { $indent = $im.Groups["i"].Value }

# Replacement: Start-Process with redirected stdout/stderr and ExitCode gate
$new = New-Object System.Collections.Generic.List[string]
[void]$new.Add($indent + $sent)
[void]$new.Add($indent + '$tmpOut = $envPath + ".sshkeygen.out.txt"')
[void]$new.Add($indent + '$tmpErr = $envPath + ".sshkeygen.err.txt"')
[void]$new.Add($indent + 'if (Test-Path -LiteralPath $tmpOut -PathType Leaf) { Remove-Item -LiteralPath $tmpOut -Force -ErrorAction SilentlyContinue }')
[void]$new.Add($indent + '$args = @("-Y","sign","-f",$key,"-n",$Namespace,"-I",$Principal,$envPath)' )
[void]$new.Add($indent + '$proc = Start-Process -FilePath $ssh -ArgumentList $args -NoNewWindow -Wait -PassThru -RedirectStandardOutput $tmpOut -RedirectStandardError $tmpErr' )
[void]$new.Add($indent + '$signOut = @()' )
[void]$new.Add($indent + 'if (Test-Path -LiteralPath $tmpOut -PathType Leaf) { $signOut += @(@((Get-Content -LiteralPath $tmpOut -Encoding UTF8) )) }' )
[void]$new.Add($indent + 'if (Test-Path -LiteralPath $tmpErr -PathType Leaf) { $signOut += @(@((Get-Content -LiteralPath $tmpErr -Encoding UTF8) )) }' )
[void]$new.Add($indent + 'if ($proc.ExitCode -ne 0) {' )
[void]$new.Add($indent + '  $o = @(@($signOut)) -join "`n"' )
[void]$new.Add($indent + '  Die ("ssh-keygen -Y sign failed (exit=" + $proc.ExitCode + "): " + $o)' )
[void]$new.Add($indent + '}' )

# Splice
$out = New-Object System.Collections.Generic.List[string]
for($i=0;$i -lt $ls.Length;$i++){
  if ($i -eq $rmStart) { foreach($nl in $new){ [void]$out.Add($nl) }; $i = $rmEnd; continue }
  [void]$out.Add($ls[$i])
}
$txt2 = (($out.ToArray()) -join "`n") + "`n"
Parse-GateText $txt2
Write-Utf8NoBomLf $sp $txt2
Write-Host ("PATCH_OK: signer now uses Start-Process capture + ExitCode gate (backup=" + $bak + ")") -ForegroundColor Green
