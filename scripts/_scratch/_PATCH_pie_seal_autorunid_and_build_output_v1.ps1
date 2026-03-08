param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
function Die([string]$m){ throw $m }
function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $t = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if (-not $t.EndsWith("`n")) { $t += "`n" }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}
function Read-Utf8NoBom([string]$Path){
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Die ("MISSING_FILE: " + $Path) }
  $enc = New-Object System.Text.UTF8Encoding($false)
  return [System.IO.File]::ReadAllText($Path,$enc)
}
function Parse-GateText([string]$Text){ [void][ScriptBlock]::Create($Text) }
function Sha256HexFile([string]$Path){
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Die ("MISSING_FILE: " + $Path) }
  $sha=[System.Security.Cryptography.SHA256]::Create()
  try { $fs=[System.IO.File]::OpenRead($Path); try{ $h=$sha.ComputeHash($fs) } finally { $fs.Dispose() } } finally { $sha.Dispose() }
  $sb=New-Object System.Text.StringBuilder; for($i=0;$i -lt $h.Length;$i++){ [void]$sb.Append($h[$i].ToString("x2")) }; return $sb.ToString()
}

function Get-LatestRunId([string]$RepoRoot){
  $rl = Join-Path $RepoRoot "runs\run_ledger.ndjson"
  if (Test-Path -LiteralPath $rl -PathType Leaf) {
    $lines = @(@(Get-Content -LiteralPath $rl -ErrorAction Stop))
    for($i=$lines.Count-1; $i -ge 0; $i--){
      $ln = $lines[$i].Trim()
      if ($ln.Length -lt 2) { continue }
      try { $o = $ln | ConvertFrom-Json } catch { continue }
      $rid = [string]$o.run_id
      if ($rid -match "^[0-9a-f]{32}$") { return $rid }
    }
  }
  # fallback: newest run_*_output.txt
  $runs = Join-Path $RepoRoot "runs"
  if (-not (Test-Path -LiteralPath $runs -PathType Container)) { Die ("missing_runs_dir: " + $runs) }
  $f = Get-ChildItem -LiteralPath $runs -File -Filter "run_*_output.txt" | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
  if (-not $f) { Die "no_run_outputs_found" }
  $m = [regex]::Match($f.Name, "^run_([0-9a-f]{32})_output\.txt$")
  if (-not $m.Success) { Die ("cannot_parse_run_id_from: " + $f.Name) }
  return $m.Groups[1].Value
}

$seal = @'
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
'@
$sealPath = Join-Path $RepoRoot "scripts\pie_run_seal_v1.ps1"
$sealBak  = $sealPath + ".bak_" + (Get-Date -Format "yyyyMMdd_HHmmss")
if (Test-Path -LiteralPath $sealPath -PathType Leaf) { Copy-Item -LiteralPath $sealPath -Destination $sealBak -Force | Out-Null }
Write-Utf8NoBomLf $sealPath $seal
Parse-GateText $seal
Write-Host ("PATCH_OK: pie_run_seal_v1.ps1 now auto-picks latest RunId (backup=" + $sealBak + ")") -ForegroundColor Green

$build = @'
param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [string]$RunId="",
  [switch]$Sign,
  [ValidateNotNullOrEmpty()][string]$Namespace="pie/run_packet.v1",
  [string]$SigningKeyPath="",
  [string]$Principal=""
)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
function Die([string]$m){ throw $m }
$RepoRoot = $RepoRoot.TrimEnd("\")
. (Join-Path $RepoRoot "scripts\_lib_neverlost_v1.ps1")

function Sha256HexBytes([byte[]]$b){ if ($null -eq $b) { $b=@() }; $sha=[System.Security.Cryptography.SHA256]::Create(); try{$h=$sha.ComputeHash([byte[]]$b)}finally{$sha.Dispose()}; $sb=New-Object System.Text.StringBuilder; for($i=0;$i -lt $h.Length;$i++){[void]$sb.Append($h[$i].ToString("x2"))}; return $sb.ToString() }
function Sha256HexFile([string]$Path){ $sha=[System.Security.Cryptography.SHA256]::Create(); try{$fs=[System.IO.File]::OpenRead($Path); try{$h=$sha.ComputeHash($fs)}finally{$fs.Dispose()}}finally{$sha.Dispose()}; $sb=New-Object System.Text.StringBuilder; for($i=0;$i -lt $h.Length;$i++){[void]$sb.Append($h[$i].ToString("x2"))}; return $sb.ToString() }
function Write-Utf8NoBomLf([string]$Path,[string]$Text){ $dir=Split-Path -Parent $Path; if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){ New-Item -ItemType Directory -Force -Path $dir | Out-Null }; $t=$Text.Replace("`r`n","`n").Replace("`r","`n"); if(-not $t.EndsWith("`n")){ $t += "`n" }; $enc=New-Object System.Text.UTF8Encoding($false); [System.IO.File]::WriteAllText($Path,$t,$enc) }
function Read-Utf8NoBom([string]$Path){ if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("MISSING_FILE: " + $Path) }; $enc=New-Object System.Text.UTF8Encoding($false); return [System.IO.File]::ReadAllText($Path,$enc) }

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

if ([string]::IsNullOrWhiteSpace($RunId)) { $RunId = Get-LatestRunId $RepoRoot }
if ($RunId -notmatch "^[0-9a-f]{32}$") { Die ("bad_run_id: " + $RunId) }

$runDir = Join-Path $RepoRoot ("runs\run_" + $RunId)
if (-not (Test-Path -LiteralPath $runDir -PathType Container)) { Die ("missing_sealed_run_dir: " + $runDir + " (run pie_run_seal_v1.ps1 first)") }
$runSums = Join-Path $runDir "sha256sums.txt"
if (-not (Test-Path -LiteralPath $runSums -PathType Leaf)) { Die ("missing_run_sha256sums: " + $runSums) }

$outbox = Join-Path $RepoRoot "packets\outbox"
if (-not (Test-Path -LiteralPath $outbox -PathType Container)) { New-Item -ItemType Directory -Force -Path $outbox | Out-Null }
$tmp = Join-Path $outbox ("_tmp_build_" + ([guid]::NewGuid().ToString("n")))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

# (1) payload/**
$payload = Join-Path $tmp "payload\run"
New-Item -ItemType Directory -Force -Path $payload | Out-Null
Copy-Item -LiteralPath $runDir -Destination (Join-Path $payload ("run_" + $RunId)) -Recurse -Force

# (2) manifest.json WITHOUT packet_id
$manifestPath = Join-Path $tmp "manifest.json"
$m = @{ schema="packet.manifest.v1"; kind="pie.run_packet"; run_id=$RunId; created_utc=(Get-Date).ToUniversalTime().ToString("o"); option="A"; payload_rel=("payload/run/run_" + $RunId + "/") }
$mCanon = NL_ToCanonJson $m
Write-Utf8NoBomLf $manifestPath $mCanon

# (3) optional signature BEFORE sha256sums
if ($Sign) {
  $signer = Join-Path $RepoRoot "scripts\pie_run_packet_sign_v1.ps1"
  if (-not (Test-Path -LiteralPath $signer -PathType Leaf)) { Die ("missing signer script: " + $signer) }
  & (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -ExecutionPolicy Bypass -File $signer -RepoRoot $RepoRoot -PacketRoot $tmp -Namespace $Namespace -SigningKeyPath $SigningKeyPath -Principal $Principal
}

# (4) PacketId = SHA256(UTF8(manifest-without-id bytes))
$mBytes = [System.Text.Encoding]::UTF8.GetBytes((Read-Utf8NoBom $manifestPath))
$packetId = Sha256HexBytes $mBytes

# (5) packet_id.txt (Option A)
$pidTxt = Join-Path $tmp "packet_id.txt"
Write-Utf8NoBomLf $pidTxt ($packetId)

# (6) sha256sums last
$sumsPath = Join-Path $tmp "sha256sums.txt"
$files = New-Object System.Collections.Generic.List[string]
[void]$files.Add("manifest.json")
[void]$files.Add("packet_id.txt")
if (Test-Path -LiteralPath (Join-Path $tmp "sig_envelope.v1.json") -PathType Leaf) { [void]$files.Add("sig_envelope.v1.json") }
if (Test-Path -LiteralPath (Join-Path $tmp "signatures\sig_envelope.sig") -PathType Leaf) { [void]$files.Add("signatures\sig_envelope.sig") }
$payloadRoot = Join-Path $tmp "payload"
$payloadFiles = @(@(Get-ChildItem -LiteralPath $payloadRoot -Recurse -File | ForEach-Object { $_.FullName.Substring($tmp.Length).TrimStart("\") }))
foreach($r in $payloadFiles){ [void]$files.Add($r) }
$uniq = @(@($files.ToArray() | Sort-Object -Unique))
$sumLines = New-Object System.Collections.Generic.List[string]
foreach($r in $uniq){ $fp = Join-Path $tmp $r; $h = Sha256HexFile $fp; [void]$sumLines.Add(($h + "  " + ($r -replace "\\","/"))) }
Write-Utf8NoBomLf $sumsPath (($sumLines.ToArray() -join "`n"))

# finalize
$final = Join-Path $outbox $packetId
if (Test-Path -LiteralPath $final -PathType Container) { Remove-Item -LiteralPath $final -Recurse -Force }
Move-Item -LiteralPath $tmp -Destination $final

$msg = "OK: run packet built: " + $packetId + " run_id=" + $RunId + " " + $final
Write-Host $msg -ForegroundColor Green
Write-Output $msg
'@
$bp = Join-Path $RepoRoot "scripts\pie_run_packet_build_v1.ps1"
$bb = $bp + ".bak_" + (Get-Date -Format "yyyyMMdd_HHmmss")
if (Test-Path -LiteralPath $bp -PathType Leaf) { Copy-Item -LiteralPath $bp -Destination $bb -Force | Out-Null }
Write-Utf8NoBomLf $bp $build
Parse-GateText $build
Write-Host ("PATCH_OK: pie_run_packet_build_v1.ps1 now emits Write-Output (backup=" + $bb + ")") -ForegroundColor Green
Write-Host "PATCH_ALL_DONE" -ForegroundColor Green
