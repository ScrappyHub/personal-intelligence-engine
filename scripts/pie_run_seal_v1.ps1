param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [string]$RunId=""
)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
function Die([string]$m){ throw $m }
function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir=Split-Path -Parent $Path
  if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){ New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $t=$Text.Replace("`r`n","`n").Replace("`r","`n"); if(-not $t.EndsWith("`n")){ $t += "`n" }
  $enc=New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}
function Read-Utf8NoBom([string]$Path){ if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("MISSING_FILE: " + $Path) }; $enc=New-Object System.Text.UTF8Encoding($false); return [System.IO.File]::ReadAllText($Path,$enc) }
function Sha256HexFile([string]$Path){ $sha=[System.Security.Cryptography.SHA256]::Create(); try{ $fs=[System.IO.File]::OpenRead($Path); try{ $h=$sha.ComputeHash($fs) } finally { $fs.Dispose() } } finally { $sha.Dispose() }; $sb=New-Object System.Text.StringBuilder; for($i=0;$i -lt $h.Length;$i++){ [void]$sb.Append($h[$i].ToString("x2")) }; return $sb.ToString() }
function Get-LatestRunId([string]$RepoRoot){
  $rl = Join-Path $RepoRoot "runs\run_ledger.ndjson"
  if (Test-Path -LiteralPath $rl -PathType Leaf) {
    $lines = @(@(Get-Content -LiteralPath $rl -ErrorAction Stop))
    for($i=$lines.Count-1; $i -ge 0; $i--){
      $ln = $lines[$i].Trim(); if($ln.Length -lt 2){ continue }
      try { $o = $ln | ConvertFrom-Json } catch { continue }
      $rid = [string]$o.run_id
      if ($rid -match "^[0-9a-f]{32}$") { return $rid }
    }
  }
  $runs = Join-Path $RepoRoot "runs"
  $f = Get-ChildItem -LiteralPath $runs -File -Filter "run_*_output.txt" | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
  if (-not $f) { Die "no_run_outputs_found" }
  $m = [regex]::Match($f.Name, "^run_([0-9a-f]{32})_output\.txt$")
  if (-not $m.Success) { Die ("cannot_parse_run_id_from: " + $f.Name) }
  return $m.Groups[1].Value
}

$RepoRoot = $RepoRoot.TrimEnd("\")
if ([string]::IsNullOrWhiteSpace($RunId)) { $RunId = Get-LatestRunId $RepoRoot }
if ($RunId -notmatch "^[0-9a-f]{32}$") { Die ("bad_run_id: " + $RunId) }

$runsDir = Join-Path $RepoRoot "runs"
$inTxt  = Join-Path $runsDir ("run_" + $RunId + "_input.txt")
$outTxt = Join-Path $runsDir ("run_" + $RunId + "_output.txt")
if (-not (Test-Path -LiteralPath $inTxt -PathType Leaf)) { Die ("missing_input_txt: " + $inTxt) }
if (-not (Test-Path -LiteralPath $outTxt -PathType Leaf)) { Die ("missing_output_txt: " + $outTxt) }

$dir = Join-Path $runsDir ("run_" + $RunId)
$sums = Join-Path $dir "sha256sums.txt"
if (Test-Path -LiteralPath $sums -PathType Leaf) {
  Write-Host ("OK: run already sealed: " + $RunId) -ForegroundColor Green
  Write-Output ("OK: sealed run_id=" + $RunId + " " + $dir)
  return
}

New-Item -ItemType Directory -Force -Path $dir | Out-Null
Copy-Item -LiteralPath $inTxt  -Destination (Join-Path $dir "input.txt")  -Force
Copy-Item -LiteralPath $outTxt -Destination (Join-Path $dir "output.txt") -Force

$sumLines = New-Object System.Collections.Generic.List[string]
$h1 = Sha256HexFile (Join-Path $dir "input.txt")
$h2 = Sha256HexFile (Join-Path $dir "output.txt")
[void]$sumLines.Add(($h1 + "  input.txt"))
[void]$sumLines.Add(($h2 + "  output.txt"))
Write-Utf8NoBomLf $sums (($sumLines.ToArray() -join "`n"))
Write-Host ("OK: run sealed: " + $RunId + " sums=" + $sums) -ForegroundColor Green
Write-Output ("OK: sealed run_id=" + $RunId + " " + $dir)
