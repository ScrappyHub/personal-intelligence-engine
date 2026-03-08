param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
function Die([string]$m){ throw $m }
function Read-Utf8NoBom([string]$Path){ if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("MISSING_FILE: " + $Path) }; $enc=New-Object System.Text.UTF8Encoding($false); return [System.IO.File]::ReadAllText($Path,$enc) }
function Write-Utf8NoBomLf([string]$Path,[string]$Text){ $dir=Split-Path -Parent $Path; if($dir -and -not(Test-Path -LiteralPath $dir -PathType Container)){ New-Item -ItemType Directory -Force -Path $dir | Out-Null }; $t=$Text.Replace("`r`n","`n").Replace("`r","`n"); if(-not $t.EndsWith("`n")){ $t += "`n" }; $enc=New-Object System.Text.UTF8Encoding($false); [System.IO.File]::WriteAllText($Path,$t,$enc) }
function Parse-GateText([string]$Text){ [void][ScriptBlock]::Create($Text) }

$RepoRoot = $RepoRoot.TrimEnd("\")
$scratch = Join-Path $RepoRoot "scripts\_scratch"
$target  = Join-Path $scratch "_RUN_pie_write_wbs_and_patch_signer_v1.ps1"
if(-not (Test-Path -LiteralPath $target -PathType Leaf)){ Die ("MISSING_TARGET_RUNNER: " + $target) }
$bak = $target + ".bak_" + (Get-Date -Format "yyyyMMdd_HHmmss")
Copy-Item -LiteralPath $target -Destination $bak -Force | Out-Null
$txt = Read-Utf8NoBom $target

# Fix: only rewrite the inner emitted line builder (do NOT touch other content)
$needle = "[void]`$R.Add('[void]`$R.Add("
$repl   = "[void]`$R.Add('[void]`$md.Add("
$txt2 = $txt.Replace($needle,$repl)
if($txt2 -eq $txt){ Die ("PATCH_FAIL: needle not found. backup=" + $bak) }
Parse-GateText $txt2
Write-Utf8NoBomLf $target $txt2
Parse-GateText (Read-Utf8NoBom $target)
Write-Host ("PATCH_OK: runner inner $R->md typo fixed (backup=" + $bak + ")") -ForegroundColor Green
Write-Host ("RUNNER_PARSE_OK: " + $target) -ForegroundColor Green
