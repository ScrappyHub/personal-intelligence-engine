param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
function Die([string]$m){ throw $m }
function Read-Utf8NoBom([string]$Path){ if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("MISSING_FILE: " + $Path) }; $enc=New-Object System.Text.UTF8Encoding($false); return [System.IO.File]::ReadAllText($Path,$enc) }
function Write-Utf8NoBomLf([string]$Path,[string]$Text){ $dir=Split-Path -Parent $Path; if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){ New-Item -ItemType Directory -Force -Path $dir | Out-Null }; $t=$Text.Replace("`r`n","`n").Replace("`r","`n"); if(-not $t.EndsWith("`n")){ $t += "`n" }; $enc=New-Object System.Text.UTF8Encoding($false); [System.IO.File]::WriteAllText($Path,$t,$enc) }
function Parse-GateText([string]$Text){ [void][ScriptBlock]::Create($Text) }

$RepoRoot = $RepoRoot.TrimEnd("\")
$runner = Join-Path $RepoRoot "scripts\_scratch\_RUN_pie_wbs_and_signer_fix_v2.ps1"
if(-not (Test-Path -LiteralPath $runner -PathType Leaf)){ Die ("MISSING_RUNNER: " + $runner) }
$bak = $runner + ".bak_" + (Get-Date -Format "yyyyMMdd_HHmmss")
Copy-Item -LiteralPath $runner -Destination $bak -Force | Out-Null
$txt = Read-Utf8NoBom $runner

# Fix invalid C-style escaping: replace literal \" with PowerShell escaped quote `"
$before = $txt
$txt2 = $txt.Replace('\"','`"' )
if($txt2 -eq $before){ Write-Host ("OK: no \" sequences found; runner unchanged (backup=" + $bak + ")") -ForegroundColor Yellow; Parse-GateText $before; return }
Parse-GateText $txt2
Write-Utf8NoBomLf $runner $txt2
Write-Host ("PATCH_OK: fixed \" sequences in runner (backup=" + $bak + ")") -ForegroundColor Green
Parse-GateText (Read-Utf8NoBom $runner)
Write-Host ("RUNNER_PARSE_OK: " + $runner) -ForegroundColor Green
