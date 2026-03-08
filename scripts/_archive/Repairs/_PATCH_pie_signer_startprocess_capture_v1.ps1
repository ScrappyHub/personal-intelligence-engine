param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
function Die([string]$m){ throw $m }
function Read-Utf8NoBom([string]$Path){ if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("MISSING_FILE: " + $Path) }; $enc=New-Object System.Text.UTF8Encoding($false); return [System.IO.File]::ReadAllText($Path,$enc) }
function Write-Utf8NoBomLf([string]$Path,[string]$Text){ $dir=Split-Path -Parent $Path; if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){ New-Item -ItemType Directory -Force -Path $dir | Out-Null }; $t=$Text.Replace("`r`n","`n").Replace("`r","`n"); if(-not $t.EndsWith("`n")){ $t += "`n" }; $enc=New-Object System.Text.UTF8Encoding($false); [System.IO.File]::WriteAllText($Path,$t,$enc) }
function Parse-GateText([string]$Text){ [void][ScriptBlock]::Create($Text) }

$RepoRoot = $RepoRoot.TrimEnd("\")
$sp = Join-Path $RepoRoot "scripts\pie_run_packet_sign_v1.ps1"
if(-not (Test-Path -LiteralPath $sp -PathType Leaf)){ Die ("MISSING_SIGNER: " + $sp) }
$bak = $sp + ".bak_" + (Get-Date -Format "yyyyMMdd_HHmmss")
Copy-Item -LiteralPath $sp -Destination $bak -Force | Out-Null
$txt = Read-Utf8NoBom $sp
$sent = "# --- PIE_PATCH_SIGNER_SSHKEYGEN_STARTPROCESS_V1 ---"
if($txt -like ("*" + $sent + "*")){ Write-Host ("OK: signer already patched (backup=" + $bak + ")") -ForegroundColor Yellow; return }

# Find the exact signOut assignment line (current shape in repo)
$needle = '$signOut = & $ssh -Y sign -f $key -n $Namespace -I $Principal $envPath 2>&1'
$idx = $txt.IndexOf($needle,[System.StringComparison]::Ordinal)
if($idx -lt 0){
  $ls = $txt -split "`n"
  $sn = New-Object System.Collections.Generic.List[string]
  [void]$sn.Add("patch_fail: could not find exact signOut line")
  [void]$sn.Add("backup=" + $bak)
  for($i=0;$i -lt $ls.Length;$i++){
    $l=$ls[$i]
    if($l -match "(?i)\bsignOut\b|\bssh\b|ssh-keygen|\b-Y\b|\bsign\b|2>&1|\bLASTEXITCODE\b"){ [void]$sn.Add(("L{0}: {1}" -f ($i+1), $l.TrimEnd())) }
  }
  Die (($sn.ToArray()) -join "`n")
}

# Replacement block: capture stdout/stderr; set $LASTEXITCODE for existing gates
$repl = New-Object System.Collections.Generic.List[string]
[void]$repl.Add($sent)
[void]$repl.Add('$tmpOut = $envPath + ".sshkeygen.out.txt"' )
[void]$repl.Add('$tmpErr = $envPath + ".sshkeygen.err.txt"' )
[void]$repl.Add('if (Test-Path -LiteralPath $tmpOut -PathType Leaf) { Remove-Item -LiteralPath $tmpOut -Force -ErrorAction SilentlyContinue }' )
[void]$repl.Add('if (Test-Path -LiteralPath $tmpErr -PathType Leaf) { Remove-Item -LiteralPath $tmpErr -Force -ErrorAction SilentlyContinue }' )
[void]$repl.Add('$args = @("-Y","sign","-f",$key,"-n",$Namespace,"-I",$Principal,$envPath)' )
[void]$repl.Add('$proc = Start-Process -FilePath $ssh -ArgumentList $args -NoNewWindow -Wait -PassThru -RedirectStandardOutput $tmpOut -RedirectStandardError $tmpErr' )
[void]$repl.Add('$signOut = @()' )
[void]$repl.Add('if (Test-Path -LiteralPath $tmpOut -PathType Leaf) { $signOut += @(@(Get-Content -LiteralPath $tmpOut -Encoding UTF8)) }' )
[void]$repl.Add('if (Test-Path -LiteralPath $tmpErr -PathType Leaf) { $signOut += @(@(Get-Content -LiteralPath $tmpErr -Encoding UTF8)) }' )
[void]$repl.Add('$LASTEXITCODE = [int]$proc.ExitCode' )

$block = (($repl.ToArray()) -join "`n")
$txt2 = $txt.Replace($needle,$block)
Parse-GateText $txt2
Write-Utf8NoBomLf $sp $txt2
Parse-GateText (Read-Utf8NoBom $sp)
Write-Host ("PATCH_OK: signer now Start-Process captured (backup=" + $bak + ")") -ForegroundColor Green
