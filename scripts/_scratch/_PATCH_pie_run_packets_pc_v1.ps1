param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }

function Read-Utf8NoBom([string]$Path){
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Die ("MISSING_FILE: " + $Path) }
  $enc = New-Object System.Text.UTF8Encoding($false)
  return [System.IO.File]::ReadAllText($Path,$enc)
}
function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $t = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if (-not $t.EndsWith("`n")) { $t += "`n" }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}
function Parse-GateText([string]$Text){ [void][ScriptBlock]::Create($Text) }
function Parse-GateFile([string]$Path){ Parse-GateText (Read-Utf8NoBom $Path) }

function Sha256HexBytes([byte[]]$b){
  if ($null -eq $b) { $b = @() }
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try { $h = $sha.ComputeHash([byte[]]$b) } finally { $sha.Dispose() }
  $sb = New-Object System.Text.StringBuilder
  for($i=0;$i -lt $h.Length;$i++){ [void]$sb.Append($h[$i].ToString("x2")) }
  return $sb.ToString()
}
function Sha256HexFile([string]$Path){
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Die ("MISSING_FILE: " + $Path) }
  $fs = [System.IO.File]::Open($Path,[System.IO.FileMode]::Open,[System.IO.FileAccess]::Read,[System.IO.FileShare]::Read)
  try {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $h = $sha.ComputeHash($fs) } finally { $sha.Dispose() }
  } finally { $fs.Dispose() }
  $sb = New-Object System.Text.StringBuilder
  for($i=0;$i -lt $h.Length;$i++){ [void]$sb.Append($h[$i].ToString("x2")) }
  return $sb.ToString()
}

$RepoRoot = $RepoRoot.TrimEnd("\")
if (-not (Test-Path -LiteralPath $RepoRoot -PathType Container)) { Die ("RepoRoot not found: " + $RepoRoot) }

$LibNeverlost = Join-Path $RepoRoot "scripts\_lib_neverlost_v1.ps1"
$LibPie       = Join-Path $RepoRoot "scripts\_lib_pie_v1.ps1"
if (-not (Test-Path -LiteralPath $LibNeverlost -PathType Leaf)) { Die ("MISSING_LIB: " + $LibNeverlost) }
if (-not (Test-Path -LiteralPath $LibPie -PathType Leaf)) { Die ("MISSING_LIB: " + $LibPie) }

. $LibNeverlost
. $LibPie

# ---------------------------
# 1) scripts\pie_run_seal_v1.ps1
# ---------------------------
$SealPath = Join-Path $RepoRoot "scripts\pie_run_seal_v1.ps1"

$seal = New-Object System.Collections.Generic.List[string]
[void]$seal.Add('param(')
[void]$seal.Add('  [Parameter(Mandatory=$true)][string]$RepoRoot,')
[void]$seal.Add('  [Parameter(Mandatory=$true)][string]$RunId')
[void]$seal.Add(')')
[void]$seal.Add('$ErrorActionPreference="Stop"')
[void]$seal.Add('Set-StrictMode -Version Latest')
[void]$seal.Add('. (Join-Path $RepoRoot "scripts\_lib_neverlost_v1.ps1")')
[void]$seal.Add('. (Join-Path $RepoRoot "scripts\_lib_pie_v1.ps1")')
[void]$seal.Add('$RepoRoot = $RepoRoot.TrimEnd("\")')
[void]$seal.Add('')
[void]$seal.Add('# Run artifacts (v1): we normalize into runs\run_<id>\')
[void]$seal.Add('$runsDir = Join-Path $RepoRoot "runs"')
[void]$seal.Add('if (-not (Test-Path -LiteralPath $runsDir -PathType Container)) { PIE_Die ("missing_runs_dir: " + $runsDir) }')
[void]$seal.Add('$runDir = Join-Path $runsDir ("run_" + $RunId)')
[void]$seal.Add('if (-not (Test-Path -LiteralPath $runDir -PathType Container)) { New-Item -ItemType Directory -Force -Path $runDir | Out-Null }')
[void]$seal.Add('')
[void]$seal.Add('$inOld  = Join-Path $runsDir ("run_" + $RunId + "_input.txt")')
[void]$seal.Add('$outOld = Join-Path $runsDir ("run_" + $RunId + "_output.txt")')
[void]$seal.Add('$inNew  = Join-Path $runDir "input.txt"')
[void]$seal.Add('$outNew = Join-Path $runDir "output.txt"')
[void]$seal.Add('')
[void]$seal.Add('if (Test-Path -LiteralPath $inOld -PathType Leaf) {')
[void]$seal.Add('  if (Test-Path -LiteralPath $inNew -PathType Leaf) { Remove-Item -LiteralPath $inNew -Force }')
[void]$seal.Add('  Move-Item -LiteralPath $inOld -Destination $inNew')
[void]$seal.Add('}')
[void]$seal.Add('if (Test-Path -LiteralPath $outOld -PathType Leaf) {')
[void]$seal.Add('  if (Test-Path -LiteralPath $outNew -PathType Leaf) { Remove-Item -LiteralPath $outNew -Force }')
[void]$seal.Add('  Move-Item -LiteralPath $outOld -Destination $outNew')
[void]$seal.Add('}')
[void]$seal.Add('')
[void]$seal.Add('if (-not (Test-Path -LiteralPath $inNew -PathType Leaf))  { PIE_Die ("missing_run_input: " + $inNew) }')
[void]$seal.Add('if (-not (Test-Path -LiteralPath $outNew -PathType Leaf)) { PIE_Die ("missing_run_output: " + $outNew) }')
[void]$seal.Add('')
[void]$seal.Add('# Pull run_record.v1 from run_ledger.ndjson and write canonical run_record.v1.json')
[void]$seal.Add('$ledger = Join-Path $runsDir "run_ledger.ndjson"')
[void]$seal.Add('if (-not (Test-Path -LiteralPath $ledger -PathType Leaf)) { PIE_Die ("missing_run_ledger: " + $ledger) }')
[void]$seal.Add('$lines = @(@([System.IO.File]::ReadAllLines($ledger,(New-Object System.Text.UTF8Encoding($false)))))')
[void]$seal.Add('$hit = $null')
[void]$seal.Add('for($i=$lines.Count-1; $i -ge 0; $i--){')
[void]$seal.Add('  $ln = $lines[$i]')
[void]$seal.Add('  if ([string]::IsNullOrWhiteSpace($ln)) { continue }')
[void]$seal.Add('  try { $o = $ln | ConvertFrom-Json } catch { continue }')
[void]$seal.Add('  if ([string]$o.schema -ne "run_record.v1") { continue }')
[void]$seal.Add('  if ([string]$o.run_id -ne $RunId) { continue }')
[void]$seal.Add('  $hit = $o; break')
[void]$seal.Add('}')
[void]$seal.Add('if ($null -eq $hit) { PIE_Die ("run_record_not_found_in_ledger: " + $RunId) }')
[void]$seal.Add('$rrPath = Join-Path $runDir "run_record.v1.json"')
[void]$seal.Add('$rrCanon = NL_ToCanonJson $hit')
[void]$seal.Add('NL_WriteUtf8NoBomLf $rrPath $rrCanon')
[void]$seal.Add('')
[void]$seal.Add('# Write sha256sums.txt (relative paths within runDir)')
[void]$seal.Add('$sumsPath = Join-Path $runDir "sha256sums.txt"')
[void]$seal.Add('$entries = New-Object System.Collections.Generic.List[string]')
[void]$seal.Add('$files = @("input.txt","output.txt","run_record.v1.json")')
[void]$seal.Add('foreach($rel in $files){')
[void]$seal.Add('  $fp = Join-Path $runDir $rel')
[void]$seal.Add('  if (-not (Test-Path -LiteralPath $fp -PathType Leaf)) { PIE_Die ("missing_run_file: " + $fp) }')
[void]$seal.Add('  $hx = PIE_Sha256HexFile $fp')
[void]$seal.Add('  [void]$entries.Add(($hx + "  " + $rel))')
[void]$seal.Add('}')
[void]$seal.Add('$sumsText = (($entries.ToArray() | Sort-Object) -join "`n") + "`n"')
[void]$seal.Add('NL_WriteUtf8NoBomLf $sumsPath $sumsText')
[void]$seal.Add('$sumsSha = PIE_Sha256HexBytes ([System.Text.Encoding]::UTF8.GetBytes($sumsText))')
[void]$seal.Add('')
[void]$seal.Add('NL_AppendReceipt $RepoRoot "pie_run_seal" ("sealed run " + $RunId) @{ run_id=$RunId; file_count=$files.Count; sums_sha256=("sha256:" + $sumsSha) }')
[void]$seal.Add('Write-Host ("OK: run sealed: " + $RunId + " sums_sha256=sha256:" + $sumsSha) -ForegroundColor Green')
[void]$seal.Add('Write-Output ("sha256:" + $sumsSha)')
[void]$seal.Add('')

$sealText = ($seal.ToArray() -join "`n") + "`n"
NL_WriteUtf8NoBomLf $SealPath $sealText
Parse-GateFile $SealPath
Write-Host "WROTE+PARSE_OK: pie_run_seal_v1.ps1" -ForegroundColor Green

# ---------------------------
# 2) scripts\pie_run_packet_build_v1.ps1 (Packet Constitution v1, Option A)
# ---------------------------
$PktPath = Join-Path $RepoRoot "scripts\pie_run_packet_build_v1.ps1"

$pkt = New-Object System.Collections.Generic.List[string]
[void]$pkt.Add('param(')
[void]$pkt.Add('  [Parameter(Mandatory=$true)][string]$RepoRoot,')
[void]$pkt.Add('  [Parameter(Mandatory=$true)][string]$RunId')
[void]$pkt.Add(')')
[void]$pkt.Add('$ErrorActionPreference="Stop"')
[void]$pkt.Add('Set-StrictMode -Version Latest')
[void]$pkt.Add('. (Join-Path $RepoRoot "scripts\_lib_neverlost_v1.ps1")')
[void]$pkt.Add('. (Join-Path $RepoRoot "scripts\_lib_pie_v1.ps1")')
[void]$pkt.Add('$RepoRoot = $RepoRoot.TrimEnd("\")')
[void]$pkt.Add('')
[void]$pkt.Add('# Require sealed run dir exists')
[void]$pkt.Add('$runDir = Join-Path (Join-Path $RepoRoot "runs") ("run_" + $RunId)')
[void]$pkt.Add('if (-not (Test-Path -LiteralPath $runDir -PathType Container)) { PIE_Die ("missing_sealed_run_dir: " + $runDir) }')
[void]$pkt.Add('$sumsPath = Join-Path $runDir "sha256sums.txt"')
[void]$pkt.Add('if (-not (Test-Path -LiteralPath $sumsPath -PathType Leaf)) { PIE_Die ("missing_run_sha256sums: " + $sumsPath) }')
[void]$pkt.Add('$sumsText = NL_ReadUtf8 $sumsPath')
[void]$pkt.Add('if ([string]::IsNullOrWhiteSpace($sumsText)) { PIE_Die ("empty_run_sha256sums: " + $sumsPath) }')
[void]$pkt.Add('$sumsSha = PIE_Sha256HexBytes ([System.Text.Encoding]::UTF8.GetBytes($sumsText.Replace("`r`n","`n").Replace("`r","`n")))')
[void]$pkt.Add('')
[void]$pkt.Add('# Packet outbox root')
[void]$pkt.Add('$outbox = Join-Path $RepoRoot "packets\outbox"')
[void]$pkt.Add('if (-not (Test-Path -LiteralPath $outbox -PathType Container)) { New-Item -ItemType Directory -Force -Path $outbox | Out-Null }')
[void]$pkt.Add('$stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")')
[void]$pkt.Add('$work = Join-Path $outbox ("_work_run_" + $RunId + "_" + $stamp)')
[void]$pkt.Add('if (Test-Path -LiteralPath $work -PathType Container) { Remove-Item -LiteralPath $work -Recurse -Force }')
[void]$pkt.Add('New-Item -ItemType Directory -Force -Path $work | Out-Null')
[void]$pkt.Add('')
[void]$pkt.Add('# 1) Write payload/** first (copy sealed run dir) ')
[void]$pkt.Add('$payload = Join-Path $work "payload\run"')
[void]$pkt.Add('New-Item -ItemType Directory -Force -Path $payload | Out-Null')
[void]$pkt.Add('Copy-Item -LiteralPath (Join-Path $runDir "*") -Destination $payload -Recurse -Force')
[void]$pkt.Add('')
[void]$pkt.Add('# 2) Write manifest.json WITHOUT packet_id (canonical JSON) ')
[void]$pkt.Add('$man = @{ schema="packet.manifest.v1"; kind="pie.run.v1"; producer="pie"; run_id=$RunId; run_sums_sha256=("sha256:" + $sumsSha); created_utc=(Get-Date).ToUniversalTime().ToString("o"); option="A"; payload=@( @{ rel="payload/run/"; note="sealed run bundle" } ) }')
[void]$pkt.Add('$manPath = Join-Path $work "manifest.json"')
[void]$pkt.Add('NL_WriteUtf8NoBomLf $manPath (NL_ToCanonJson $man)')
[void]$pkt.Add('')
[void]$pkt.Add('# 3) Detached signatures (optional in PIE v1; keep directory reserved)')
[void]$pkt.Add('$sigDir = Join-Path $work "signatures"')
[void]$pkt.Add('if (-not (Test-Path -LiteralPath $sigDir -PathType Container)) { New-Item -ItemType Directory -Force -Path $sigDir | Out-Null }')
[void]$pkt.Add('')
[void]$pkt.Add('# 4) Compute PacketId from canonical bytes of manifest-without-id (manifest.json as written)')
[void]$pkt.Add('$manBytes = [System.Text.Encoding]::UTF8.GetBytes((NL_ReadUtf8 $manPath).Replace("`r`n","`n").Replace("`r","`n"))')
[void]$pkt.Add('$packetId = PIE_Sha256HexBytes $manBytes')
[void]$pkt.Add('')
[void]$pkt.Add('# 5) Persist PacketId (Option A: packet_id.txt) ')
[void]$pkt.Add('$pidPath = Join-Path $work "packet_id.txt"')
[void]$pkt.Add('NL_WriteUtf8NoBomLf $pidPath ($packetId + "`n")')
[void]$pkt.Add('')
[void]$pkt.Add('# 6) Generate sha256sums.txt LAST over final on-disk bytes')
[void]$pkt.Add('$sumOut = Join-Path $work "sha256sums.txt"')
[void]$pkt.Add('$all = New-Object System.Collections.Generic.List[string]')
[void]$pkt.Add('$root = (Resolve-Path -LiteralPath $work).Path')
[void]$pkt.Add('$files = Get-ChildItem -LiteralPath $root -Recurse -File')
[void]$pkt.Add('foreach($f in $files){')
[void]$pkt.Add('  $rel = $f.FullName.Substring($root.Length).TrimStart("\") -replace "\\","/"')
[void]$pkt.Add('  $hx = PIE_Sha256HexFile $f.FullName')
[void]$pkt.Add('  [void]$all.Add(($hx + "  " + $rel))')
[void]$pkt.Add('}')
[void]$pkt.Add('$sumText = (($all.ToArray() | Sort-Object) -join "`n") + "`n"')
[void]$pkt.Add('NL_WriteUtf8NoBomLf $sumOut $sumText')
[void]$pkt.Add('')
[void]$pkt.Add('# 7) Emit receipts LAST')
[void]$pkt.Add('NL_AppendReceipt $RepoRoot "pie_run_packet_build" ("built run packet " + $RunId) @{ run_id=$RunId; packet_id=("sha256:" + $packetId); manifest_sha256=("sha256:" + (PIE_Sha256HexFile $manPath)); sha256sums_sha256=("sha256:" + (PIE_Sha256HexFile $sumOut)) }')
[void]$pkt.Add('')
[void]$pkt.Add('# Final: rename folder to PacketId for stability')
[void]$pkt.Add('$final = Join-Path $outbox $packetId')
[void]$pkt.Add('if (Test-Path -LiteralPath $final -PathType Container) { Remove-Item -LiteralPath $final -Recurse -Force }')
[void]$pkt.Add('Move-Item -LiteralPath $work -Destination $final')
[void]$pkt.Add('Write-Host ("OK: run packet built: " + $packetId + " run_id=" + $RunId) -ForegroundColor Green')
[void]$pkt.Add('Write-Output $final')
[void]$pkt.Add('')

$pktText = ($pkt.ToArray() -join "`n") + "`n"
NL_WriteUtf8NoBomLf $PktPath $pktText
Parse-GateFile $PktPath
Write-Host "WROTE+PARSE_OK: pie_run_packet_build_v1.ps1" -ForegroundColor Green

# ---------------------------
# 3) test_vectors/ minimal packet (golden) + selftest script
# ---------------------------
$TvRoot = Join-Path $RepoRoot "test_vectors\packet_constitution_v1\minimal_packet_v1"
if (-not (Test-Path -LiteralPath $TvRoot -PathType Container)) { New-Item -ItemType Directory -Force -Path $TvRoot | Out-Null }

# Deterministic content (fixed timestamp to keep packet id stable)
$tvPayloadDir = Join-Path $TvRoot "payload"
if (-not (Test-Path -LiteralPath $tvPayloadDir -PathType Container)) { New-Item -ItemType Directory -Force -Path $tvPayloadDir | Out-Null }
$tvHello = Join-Path $tvPayloadDir "hello.txt"
if (-not (Test-Path -LiteralPath $tvHello -PathType Leaf)) {
  NL_WriteUtf8NoBomLf $tvHello ("hello`n")
}

$tvManifest = Join-Path $TvRoot "manifest.json"
$tvManObj = @{
  schema="packet.manifest.v1";
  kind="test.minimal.v1";
  producer="test";
  created_utc="2000-01-01T00:00:00.0000000Z";
  option="A";
  payload=@(@{ rel="payload/hello.txt"; note="hello" })
}
$tvManCanon = (NL_ToCanonJson $tvManObj) + "`n"
NL_WriteUtf8NoBomLf $tvManifest $tvManCanon

# PacketId = sha256(canonical bytes of manifest-without-id) == manifest.json bytes (Option A)
$tvPid = Sha256HexBytes ([System.Text.Encoding]::UTF8.GetBytes($tvManCanon.Replace("`r`n","`n").Replace("`r","`n")))
$tvPidPath = Join-Path $TvRoot "packet_id.txt"
NL_WriteUtf8NoBomLf $tvPidPath ($tvPid + "`n")

# sha256sums.txt last (manifest, packet_id, payload)
$tvSums = Join-Path $TvRoot "sha256sums.txt"
$tvList = New-Object System.Collections.Generic.List[string]
$tvRootAbs = (Resolve-Path -LiteralPath $TvRoot).Path
$tvFiles = Get-ChildItem -LiteralPath $tvRootAbs -Recurse -File
foreach($f in $tvFiles){
  $rel = $f.FullName.Substring($tvRootAbs.Length).TrimStart("\") -replace "\\","/"
  $hx = Sha256HexFile $f.FullName
  [void]$tvList.Add(($hx + "  " + $rel))
}
$tvSumText = (($tvList.ToArray() | Sort-Object) -join "`n") + "`n"
NL_WriteUtf8NoBomLf $tvSums $tvSumText

# Golden expectations
$expPid = Join-Path $TvRoot "expected_packet_id.txt"
$expSums = Join-Path $TvRoot "expected_sha256sums.txt"
NL_WriteUtf8NoBomLf $expPid ($tvPid + "`n")
NL_WriteUtf8NoBomLf $expSums $tvSumText

# Selftest script (verifies vectors using packet_verify_v1.ps1, and checks golden expectations)
$SelftestPath = Join-Path $RepoRoot "scripts\_selftest_packet_constitution_v1.ps1"
$VerifyPath   = Join-Path $RepoRoot "scripts\packet_verify_v1.ps1"
if (-not (Test-Path -LiteralPath $VerifyPath -PathType Leaf)) { Die ("MISSING: " + $VerifyPath) }

$st = New-Object System.Collections.Generic.List[string]
[void]$st.Add('param([Parameter(Mandatory=$true)][string]$RepoRoot)')
[void]$st.Add('$ErrorActionPreference="Stop"')
[void]$st.Add('Set-StrictMode -Version Latest')
[void]$st.Add('. (Join-Path $RepoRoot "scripts\_lib_neverlost_v1.ps1")')
[void]$st.Add('. (Join-Path $RepoRoot "scripts\_lib_pie_v1.ps1")')
[void]$st.Add('$RepoRoot = $RepoRoot.TrimEnd("\")')
[void]$st.Add('function Die([string]$m){ throw ("PCV1_SELFTEST_FAIL: " + $m) }')
[void]$st.Add('')
[void]$st.Add('$tv = Join-Path $RepoRoot "test_vectors\packet_constitution_v1\minimal_packet_v1"')
[void]$st.Add('if (-not (Test-Path -LiteralPath $tv -PathType Container)) { Die ("missing_test_vector_dir: " + $tv) }')
[void]$st.Add('$verify = Join-Path $RepoRoot "scripts\packet_verify_v1.ps1"')
[void]$st.Add('if (-not (Test-Path -LiteralPath $verify -PathType Leaf)) { Die ("missing_verify_script: " + $verify) }')
[void]$st.Add('')
[void]$st.Add('# Verify packet (MUST NOT MUTATE)')
[void]$st.Add('& (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -ExecutionPolicy Bypass -File $verify -RepoRoot $RepoRoot -PacketRoot $tv | Out-Null')
[void]$st.Add('')
[void]$st.Add('# Check expected packet id matches packet_id.txt')
[void]$st.Add('$pid = (NL_ReadUtf8 (Join-Path $tv "packet_id.txt")).Trim()')
[void]$st.Add('$exp = (NL_ReadUtf8 (Join-Path $tv "expected_packet_id.txt")).Trim()')
[void]$st.Add('if ($pid -ne $exp) { Die ("packet_id_mismatch expected=" + $exp + " got=" + $pid) }')
[void]$st.Add('')
[void]$st.Add('# Check expected sha256sums matches')
[void]$st.Add('$s = NL_ReadUtf8 (Join-Path $tv "sha256sums.txt")')
[void]$st.Add('$es = NL_ReadUtf8 (Join-Path $tv "expected_sha256sums.txt")')
[void]$st.Add('if ($s.Replace("`r`n","`n").Replace("`r","`n") -ne $es.Replace("`r`n","`n").Replace("`r","`n")) { Die "sha256sums_mismatch" }')
[void]$st.Add('')
[void]$st.Add('Write-Host ("PCV1_SELFTEST_OK packet_id=" + $pid) -ForegroundColor Green')
$stText = ($st.ToArray() -join "`n") + "`n"
NL_WriteUtf8NoBomLf $SelftestPath $stText
Parse-GateFile $SelftestPath
Write-Host "WROTE+PARSE_OK: _selftest_packet_constitution_v1.ps1" -ForegroundColor Green

Write-Host "PATCH_OK: run seal + run packet build + test_vectors + selftest installed" -ForegroundColor Green

# ---------------------------
# 4) Smoke: run selftest + seal latest run + build packet
# ---------------------------
Write-Host "[SMOKE] Running Packet Constitution v1 selftest..." -ForegroundColor Cyan
& (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -ExecutionPolicy Bypass -File $SelftestPath -RepoRoot $RepoRoot | Out-Null

# Determine latest run_id from run_ledger.ndjson (last non-empty line)
$rledger = Join-Path (Join-Path $RepoRoot "runs") "run_ledger.ndjson"
if (-not (Test-Path -LiteralPath $rledger -PathType Leaf)) { Die ("missing_run_ledger: " + $rledger) }
$raw = [System.IO.File]::ReadAllText($rledger,(New-Object System.Text.UTF8Encoding($false)))
$lines2 = @(@($raw -split "`r?`n", -1))
$last = $null
for($i=$lines2.Count-1; $i -ge 0; $i--){
  $ln = $lines2[$i]
  if ([string]::IsNullOrWhiteSpace($ln)) { continue }
  $last = $ln
  break
}
if ($null -eq $last) { Die "run_ledger_empty" }
try { $o2 = $last | ConvertFrom-Json } catch { Die ("run_ledger_last_line_parse_failed: " + $_.Exception.Message) }
$latestRunId = [string]$o2.run_id
if ([string]::IsNullOrWhiteSpace($latestRunId)) { Die "run_ledger_last_line_missing_run_id" }

Write-Host ("[SMOKE] Sealing latest run_id=" + $latestRunId) -ForegroundColor Cyan
$sealScript = Join-Path $RepoRoot "scripts\pie_run_seal_v1.ps1"
& (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -ExecutionPolicy Bypass -File $sealScript -RepoRoot $RepoRoot -RunId $latestRunId | Out-Null

Write-Host ("[SMOKE] Building packet for run_id=" + $latestRunId) -ForegroundColor Cyan
$pktScript = Join-Path $RepoRoot "scripts\pie_run_packet_build_v1.ps1"
$pktOut = & (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -ExecutionPolicy Bypass -File $pktScript -RepoRoot $RepoRoot -RunId $latestRunId
Write-Host ("SMOKE_OK: run packet dir = " + $pktOut) -ForegroundColor Green
