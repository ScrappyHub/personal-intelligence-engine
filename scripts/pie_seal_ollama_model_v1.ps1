param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  # The actual Ollama tag to seal, e.g. "qwen2.5-coder:1.5b" or "llama3.2".
  [Parameter(Mandatory=$true)][string]$Model,
  # Filesystem-safe sealed model_id. Defaults to $Model with ':' '/' '\' replaced by '_'.
  [Parameter(Mandatory=$false)][string]$ModelId = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

. (Join-Path $RepoRoot "scripts\_lib_neverlost_v1.ps1")
. (Join-Path $RepoRoot "scripts\_lib_pie_v1.ps1")
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

# Seal a locally-pulled Ollama model into registry\models\<ModelId>\model_manifest.v1.json using
# the model's local Ollama digest as its content address. This makes the model usable as a sealed
# -Backend ollama run WITHOUT copying GGUF blobs, and records the real tag as ollama_model so a
# filesystem-safe id can reference a tag that contains ':'.

if([string]::IsNullOrWhiteSpace($ModelId)){ $ModelId = ($Model -replace '[:/\\]', '_') }

$Url = $env:PIE_OLLAMA_TAGS_URL
if([string]::IsNullOrWhiteSpace($Url)){ $Url = "http://127.0.0.1:11434/api/tags" }

try {
  $tags = Invoke-RestMethod -Method Get -Uri $Url -ContentType "application/json"
}
catch {
  throw ("PIE_SEAL_OLLAMA_TAGS_FAILED: " + $_.Exception.Message + " (is the Ollama runtime started? try: .\pie.ps1 runtime start)")
}

if($null -eq $tags -or -not ($tags.PSObject.Properties.Name -contains "models")){
  throw "PIE_SEAL_OLLAMA_TAGS_MALFORMED"
}

$entry = $null
foreach($m in @($tags.models)){
  $name = [string]$m.name
  if($name -ieq $Model -or $name -ieq ($Model + ":latest")){ $entry = $m; break }
}
if($null -eq $entry){
  throw ("PIE_SEAL_OLLAMA_MODEL_NOT_FOUND: " + $Model + " (pull it first: ollama pull " + $Model + ")")
}

$digest = [string]$entry.digest
if([string]::IsNullOrWhiteSpace($digest)){ throw ("PIE_SEAL_OLLAMA_NO_DIGEST: " + $Model) }
$digest = $digest -replace '^sha256:', ''
$sizeBytes = 0
if($entry.PSObject.Properties.Name -contains "size"){ $sizeBytes = [int64]$entry.size }
$actualTag = [string]$entry.name

$manifestDir = Join-Path (PIE_RegistryRoot $RepoRoot) $ModelId
if(-not (Test-Path -LiteralPath $manifestDir -PathType Container)){ New-Item -ItemType Directory -Path $manifestDir -Force | Out-Null }

$manifest = @{
  schema         = "model_manifest.v1"
  model_id       = $ModelId
  backend        = "ollama"
  ollama_model   = $actualTag
  sums_sha256    = ("sha256:" + $digest)
  weights_sha256 = ("sha256:" + $digest)
  size_bytes     = $sizeBytes
  layout         = "ollama"
  notes          = "sealed from local Ollama digest; weights remain in the Ollama store"
  sealed_at_utc  = (Get-Date).ToUniversalTime().ToString("o")
}

$manifestPath = Join-Path $manifestDir "model_manifest.v1.json"
NL_WriteUtf8NoBomLf $manifestPath (NL_ToCanonJson $manifest)

NL_AppendReceipt $RepoRoot "pie_seal_ollama_model" ("sealed ollama model " + $ModelId) @{ model_id=$ModelId; ollama_model=$actualTag; sums_sha256=("sha256:" + $digest) }

Write-Host ("OK: sealed ollama model: " + $ModelId + " -> " + $actualTag + " sha256:" + $digest.Substring(0,[Math]::Min(16,$digest.Length)) + "...") -ForegroundColor Green
Write-Host ("Run positive check: .\scripts\_RUN_pie_engine_verify_all_v1.ps1 -RepoRoot . -OllamaModel " + $ModelId) -ForegroundColor Cyan
