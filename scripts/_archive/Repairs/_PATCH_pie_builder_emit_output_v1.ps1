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

# Idempotent: if builder already emits pipeline OK line, do nothing.
if ($txt -match "(?im)^\s*Write-Output\s+\`$msg\s*$") {
  Write-Host ("OK: builder already emits pipeline output (backup=" + $bak + ")") -ForegroundColor Yellow
  return
}

# Replace the final OK Write-Host line (host stream) with pipeline+host emission.
$re = '(?im)^\s*Write-Host\s*\(\s*"\s*OK:\s*run\s*packet\s*built:\s*"\s*\+\s*\$packetId\s*\+\s*"\s*run_id="\s*\+\s*\$RunId\s*\+\s*"\s*"\s*\+\s*\$final\s*\)\s*(?:-ForegroundColor\s+\w+)?\s*$'
if ($txt -notmatch $re) { Die "builder_patch_fail: could not find expected OK Write-Host line" }

$rep = @(
  '$msg = ("OK: run packet built: " + $packetId + " run_id=" + $RunId + " " + $final)',
  'Write-Output $msg',
  'Write-Host $msg -ForegroundColor Green'
) -join "`n"

$txt2 = [regex]::Replace($txt, $re, $rep)
if ($txt2 -eq $txt) { Die "builder_patch_fail: replace produced no change" }
Parse-GateText $txt2
Write-Utf8NoBomLf $bp $txt2
Write-Host ("PATCH_OK: builder now emits pipeline OK line (backup=" + $bak + ")") -ForegroundColor Green
