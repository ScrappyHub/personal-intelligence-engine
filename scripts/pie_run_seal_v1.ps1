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
function Write-Utf8NoBomExact([string]$Path,[string]$Text){
  $dir=Split-Path -Parent $Path
  if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){ New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $enc=New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path,$Text,$enc)
}
function Read-Utf8NoBom([string]$Path){ if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("MISSING_FILE: " + $Path) }; $enc=New-Object System.Text.UTF8Encoding($false); return [System.IO.File]::ReadAllText($Path,$enc) }
function Sha256HexBytes([byte[]]$Bytes){ $sha=[System.Security.Cryptography.SHA256]::Create(); try{ $h=$sha.ComputeHash($Bytes) } finally { $sha.Dispose() }; $sb=New-Object System.Text.StringBuilder; foreach($b in $h){ [void]$sb.Append($b.ToString('x2')) }; return $sb.ToString() }
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
$recordJson = Join-Path $runsDir ("run_" + $RunId + "_record.json")
$provenanceJson = Join-Path $runsDir ("run_" + $RunId + "_provenance.json")
if (-not (Test-Path -LiteralPath $inTxt -PathType Leaf)) { Die ("missing_input_txt: " + $inTxt) }
if (-not (Test-Path -LiteralPath $outTxt -PathType Leaf)) { Die ("missing_output_txt: " + $outTxt) }
if (-not (Test-Path -LiteralPath $recordJson -PathType Leaf)) { Die ("legacy_run_missing_record: " + $recordJson + " (only provenance-bound runs can be sealed)") }
if (-not (Test-Path -LiteralPath $provenanceJson -PathType Leaf)) { Die ("legacy_run_missing_provenance: " + $provenanceJson + " (only provenance-bound runs can be sealed)") }

try { $record = Read-Utf8NoBom $recordJson | ConvertFrom-Json } catch { Die ("invalid_run_record: " + $_.Exception.Message) }
try { $provenance = Read-Utf8NoBom $provenanceJson | ConvertFrom-Json } catch { Die ("invalid_run_provenance: " + $_.Exception.Message) }
if([string]$record.run_id -ne $RunId -or [string]$provenance.run_id -ne $RunId){ Die "run_id_binding_mismatch" }
if([string]$provenance.schema -ne 'pie.run.provenance.v1'){ Die ("unsupported_run_provenance_schema: " + [string]$provenance.schema) }

$actualInputHash = 'sha256:' + (Sha256HexFile $inTxt)
$actualOutputHash = 'sha256:' + (Sha256HexFile $outTxt)
if([string]$record.input_hash -ne $actualInputHash -or [string]$provenance.input_sha256 -ne $actualInputHash){ Die "input_hash_binding_mismatch" }
if([string]$record.output_hash -ne $actualOutputHash -or [string]$provenance.output_sha256 -ne $actualOutputHash){ Die "output_hash_binding_mismatch" }
if([string]$record.params_hash -ne [string]$provenance.params_sha256){ Die "params_hash_binding_mismatch" }

$recordLine = (Read-Utf8NoBom $recordJson).TrimEnd("`r","`n")
$actualRecordHash = 'sha256:' + (Sha256HexBytes ([System.Text.Encoding]::UTF8.GetBytes($recordLine)))
if([string]$provenance.record_line_sha256 -ne $actualRecordHash){ Die "record_line_hash_mismatch" }

$manifestPath = Join-Path $RepoRoot ('registry\models\' + ([string]$record.model_id).Replace(':','_') + '\model_manifest.v1.json')
if(-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)){ Die ("model_manifest_missing_at_seal: " + $manifestPath) }
if(('sha256:' + (Sha256HexFile $manifestPath)) -ne [string]$provenance.model_manifest_sha256){ Die "model_manifest_changed_since_run" }

$backend = [string]$provenance.backend
$adapterPath = $(switch($backend){
  'ollama'{Join-Path $RepoRoot 'scripts\pie_backend_ollama_cmd_v1.ps1'}
  'llamacpp'{Join-Path $RepoRoot 'scripts\pie_backend_llamacpp_cmd_v1.ps1'}
  'onnx'{Join-Path $RepoRoot 'scripts\pie_backend_onnx_cmd_v1.ps1'}
  'stub'{Join-Path $RepoRoot 'scripts\pie_run_v1.ps1'}
  default{Die ("unsupported_backend: " + $backend)}
})
if(('sha256:' + (Sha256HexFile $adapterPath)) -ne [string]$provenance.adapter_script_sha256){ Die "adapter_changed_since_run" }

$contractPath = Join-Path $RepoRoot ('engine\adapters\' + $backend + '\PIE_ENGINE_ADAPTER.v1.json')
$hasContract = -not [string]::IsNullOrWhiteSpace([string]$provenance.adapter_contract_sha256)
if($hasContract){
  if(-not (Test-Path -LiteralPath $contractPath -PathType Leaf)){ Die ("adapter_contract_missing_at_seal: " + $contractPath) }
  if(('sha256:' + (Sha256HexFile $contractPath)) -ne [string]$provenance.adapter_contract_sha256){ Die "adapter_contract_changed_since_run" }
}

. (Join-Path $RepoRoot 'scripts\_lib_pie_persona_v1.ps1')
$persona = $(switch($backend){ 'ollama'{PIE_PersonaSystem 'Ollama'} 'llamacpp'{PIE_PersonaSystem 'llama.cpp'} 'onnx'{PIE_PersonaSystem 'ONNX'} default{''} })
$personaHash = 'sha256:' + (Sha256HexBytes ([System.Text.Encoding]::UTF8.GetBytes($persona)))
if($personaHash -ne [string]$provenance.persona_sha256){ Die "persona_changed_since_run" }

$dir = Join-Path $runsDir ("run_" + $RunId)
$sums = Join-Path $dir "sha256sums.txt"
if (Test-Path -LiteralPath $sums -PathType Leaf) {
  Die ("run_already_sealed: " + $RunId + " (verify the existing immutable seal instead of overwriting it)")
}

New-Item -ItemType Directory -Force -Path $dir | Out-Null
Copy-Item -LiteralPath $inTxt  -Destination (Join-Path $dir "input.txt")  -Force
Copy-Item -LiteralPath $outTxt -Destination (Join-Path $dir "output.txt") -Force
Copy-Item -LiteralPath $recordJson -Destination (Join-Path $dir "record.json") -Force
Copy-Item -LiteralPath $provenanceJson -Destination (Join-Path $dir "provenance.json") -Force
Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $dir "model_manifest.json") -Force
Copy-Item -LiteralPath $adapterPath -Destination (Join-Path $dir "adapter.ps1") -Force
if($hasContract){ Copy-Item -LiteralPath $contractPath -Destination (Join-Path $dir "adapter_contract.json") -Force }
Write-Utf8NoBomExact (Join-Path $dir "persona.txt") $persona

$sumLines = New-Object System.Collections.Generic.List[string]
$sealedFiles = @('adapter.ps1','input.txt','model_manifest.json','output.txt','persona.txt','provenance.json','record.json')
if($hasContract){ $sealedFiles += 'adapter_contract.json' }
foreach($sealedFile in @($sealedFiles | Sort-Object)){
  $sealedHash = Sha256HexFile (Join-Path $dir $sealedFile)
  [void]$sumLines.Add(($sealedHash + "  " + $sealedFile))
}
Write-Utf8NoBomLf $sums (($sumLines.ToArray() -join "`n"))
Write-Host ("OK: run sealed: " + $RunId + " sums=" + $sums) -ForegroundColor Green
Write-Output ("OK: sealed run_id=" + $RunId + " " + $dir)
