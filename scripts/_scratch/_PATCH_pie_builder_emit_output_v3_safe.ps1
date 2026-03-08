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

$sentinel = "# --- PIE_PATCH_PIPELINE_OKLINE_V1 ---"
if ($txt -like ("*" + $sentinel + "*")) {
  Write-Host ("OK: builder already patched for pipeline OK line (backup=" + $bak + ")") -ForegroundColor Yellow
  return
}

# Append a capture-safe pipeline emission at end (do NOT expand $ vars in patcher).
$appendLines = @(
  "",
  $sentinel,
  '$msg = ("OK: run packet built: " + $packetId + " run_id=" + $RunId + " " + $final)',
  'Write-Output $msg',
  '# --- END PIE_PATCH_PIPELINE_OKLINE_V1 ---'
) -join "`n"
$txt2 = $txt.TrimEnd() + "`n" + $appendLines + "`n"
Parse-GateText $txt2
Write-Utf8NoBomLf $bp $txt2
Write-Host ("PATCH_OK: builder now guarantees pipeline OK line (backup=" + $bak + ")") -ForegroundColor Green
