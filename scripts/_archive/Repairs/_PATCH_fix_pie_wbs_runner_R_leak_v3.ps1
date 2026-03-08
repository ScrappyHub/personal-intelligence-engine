param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
function Die([string]$m){ throw $m }
function Read-Utf8NoBom([string]$Path){ if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("MISSING_FILE: " + $Path) }; $enc=New-Object System.Text.UTF8Encoding($false); return [System.IO.File]::ReadAllText($Path,$enc) }
function Write-Utf8NoBomLf([string]$Path,[string]$Text){ $dir=Split-Path -Parent $Path; if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){ New-Item -ItemType Directory -Force -Path $dir | Out-Null }; $t=$Text.Replace("`r`n","`n").Replace("`r","`n"); if(-not $t.EndsWith("`n")){ $t += "`n" }; $enc=New-Object System.Text.UTF8Encoding($false); [System.IO.File]::WriteAllText($Path,$t,$enc) }
function Parse-GateText([string]$Text){ [void][ScriptBlock]::Create($Text) }

$RepoRoot = $RepoRoot.TrimEnd("\")
$scratch = Join-Path $RepoRoot "scripts\_scratch"
$target  = Join-Path $scratch "_RUN_pie_write_wbs_and_patch_signer_v1.ps1"
if(-not (Test-Path -LiteralPath $target -PathType Leaf)){ Die ("MISSING_TARGET_RUNNER: " + $target) }
$bak = $target + ".bak_" + (Get-Date -Format "yyyyMMdd_HHmmss")
Copy-Item -LiteralPath $target -Destination $bak -Force | Out-Null
$txt = Read-Utf8NoBom $target

# Replace the bad inner builder substring(s). Use backtick-escaped $ so these are LITERALS.
$n1 = "[void]`$R.Add('[void]`$R.Add("
$r1 = "[void]`$R.Add('[void]`$md.Add("
$n2 = "[void]`$R.Add('[void]`$R.Add('""
$r2 = "[void]`$R.Add('[void]`$md.Add('""

$txt2 = $txt
$txt2 = $txt2.Replace($n1,$r1)
$txt2 = $txt2.Replace($n2,$r2)

if($txt2 -eq $txt){
  $ls = $txt -split "`n"
  $sn = New-Object System.Collections.Generic.List[string]
  [void]$sn.Add("PATCH_FAIL: no known needle found. backup=" + $bak)
  [void]$sn.Add("Showing lines that mention `$R/`$md/R.Add/md.Add:")
  for($i=0;$i -lt $ls.Length;$i++){
    $l=$ls[$i]
    if($l -match "\`$\bR\b" -or $l -match "\`$\bmd\b" -or $l -match "(?i)\bR\.Add\b" -or $l -match "(?i)\bmd\.Add\b"){
      [void]$sn.Add(("L{0}: {1}" -f ($i+1), $l.TrimEnd()))
    }
  }
  Die (($sn.ToArray()) -join "`n")
}

Parse-GateText $txt2
Write-Utf8NoBomLf $target $txt2
Parse-GateText (Read-Utf8NoBom $target)
Write-Host ("PATCH_OK: fixed runner inner $R leak (backup=" + $bak + ")") -ForegroundColor Green
Write-Host ("RUNNER_PARSE_OK: " + $target) -ForegroundColor Green
