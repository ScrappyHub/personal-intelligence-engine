param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
function Die([string]$m){ throw $m }
function Read-Utf8NoBom([string]$Path){ if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("MISSING_FILE: " + $Path) }; $enc=New-Object System.Text.UTF8Encoding($false); return [System.IO.File]::ReadAllText($Path,$enc) }
function Write-Utf8NoBomLf([string]$Path,[string]$Text){ $dir=Split-Path -Parent $Path; if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){ New-Item -ItemType Directory -Force -Path $dir | Out-Null }; $t=$Text.Replace("`r`n","`n").Replace("`r","`n"); if(-not $t.EndsWith("`n")){ $t += "`n" }; $enc=New-Object System.Text.UTF8Encoding($false); [System.IO.File]::WriteAllText($Path,$t,$enc) }
function Parse-GateText([string]$Text){ [void][ScriptBlock]::Create($Text) }

$RepoRoot = $RepoRoot.TrimEnd("\")
$sp = Join-Path $RepoRoot "scripts\pie_build_packet_optionA_v1.ps1"
if(-not (Test-Path -LiteralPath $sp -PathType Leaf)){ Die ("MISSING_BUILDER: " + $sp) }
$bak = $sp + ".bak_" + (Get-Date -Format "yyyyMMdd_HHmmss")
Copy-Item -LiteralPath $sp -Destination $bak -Force | Out-Null
$txt = Read-Utf8NoBom $sp

# $PID is a read-only automatic variable. If the builder uses $pid as "packet id", it will collide (case-insensitive).
# Rename all $pid/$PID tokens to $packetId (intended "packet id").
$re = New-Object System.Text.RegularExpressions.Regex('(?i)\$pid\b')
$txt2 = $re.Replace($txt, '$packetId')
if($txt2 -eq $txt){ Die ("PATCH_FAIL: no $pid token found to replace. backup=" + $bak) }

Parse-GateText $txt2
Write-Utf8NoBomLf $sp $txt2
Parse-GateText (Read-Utf8NoBom $sp)
Write-Host ("PATCH_OK: renamed $pid/$PID -> $packetId in builder (backup=" + $bak + ")") -ForegroundColor Green
Write-Host ("BUILDER_PARSE_OK: " + $sp) -ForegroundColor Green
