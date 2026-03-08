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

# If already patched, stop (idempotent).
if ($txt -match "(?im)^\s*Write-Output\s*\(\s*`"OK:\s*run\s*packet\s*built:\s*`"\s*\+\s*\$packetId") {
  Write-Host ("OK: builder already emits pipeline output (backup=" + $bak + ")") -ForegroundColor Yellow
  return
}

# Append a guaranteed pipeline emission at end; relies on $packetId, $RunId, $final already defined by builder.
$append = @(
  "",
  "# --- PATCH: pipeline emission for capture-safe smoke ---",
  'Write-Output ("OK: run packet built: " + $packetId + " run_id=" + $RunId + " " + $final)',
  "# --- END PATCH ---"
) -join "`n"
$txt2 = $txt.TrimEnd() + "`n" + $append + "`n"
Parse-GateText $txt2
Write-Utf8NoBomLf $bp $txt2
Write-Host ("PATCH_OK: builder now guarantees pipeline OK line (backup=" + $bak + ")") -ForegroundColor Green
