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

# Replace the signer invocation line with an arg-array splat block (more robust than inline params).
# Anchor: the builder must contain a call to pie_run_packet_sign_v1.ps1; we replace the whole line that starts with "& (Get-Command powershell.exe".
$re = '(?im)^\s*&\s*\(Get-Command\s+powershell\.exe\s+-ErrorAction\s+Stop\)\.Source\s+-NoProfile\s+-ExecutionPolicy\s+Bypass\s+-File\s+\$signer\s+.+$'
if ($txt -notmatch $re) { Die "patch_fail: could not find inline signer invocation line" }

$block = @(
  '  # --- PIE_PATCH_SIGN_CALL_V1 ---',
  '  if (-not (Test-Path -LiteralPath $tmp -PathType Container)) { Die ("sign_tmp_missing: " + $tmp) }',
  '  $ps = (Get-Command powershell.exe -ErrorAction Stop).Source',
  '  $argv = New-Object System.Collections.Generic.List[string]',
  '  [void]$argv.Add("-NoProfile")',
  '  [void]$argv.Add("-ExecutionPolicy")',
  '  [void]$argv.Add("Bypass")',
  '  [void]$argv.Add("-File")',
  '  [void]$argv.Add($signer)',
  '  [void]$argv.Add("-RepoRoot") ; [void]$argv.Add($RepoRoot)',
  '  [void]$argv.Add("-PacketRoot"); [void]$argv.Add($tmp)',
  '  [void]$argv.Add("-Namespace"); [void]$argv.Add($Namespace)',
  '  if ($SigningKeyPath) { [void]$argv.Add("-SigningKeyPath"); [void]$argv.Add($SigningKeyPath) }',
  '  if ($Principal)      { [void]$argv.Add("-Principal");      [void]$argv.Add($Principal) }',
  '  & $ps @($argv.ToArray())',
  '  # --- END PIE_PATCH_SIGN_CALL_V1 ---'
) -join "`n"

$txt2 = [regex]::Replace($txt, $re, $block, 1)
if ($txt2 -eq $txt) { Die "patch_fail: replace produced no change" }
Parse-GateText $txt2
Write-Utf8NoBomLf $bp $txt2
Write-Host ("PATCH_OK: builder signer invocation now uses arg-array splat (backup=" + $bak + ")") -ForegroundColor Green
