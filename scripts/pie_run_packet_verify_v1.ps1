param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$PacketRoot,
  [switch]$RequireSig,
  [switch]$RequireCertifiedInference
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$PacketRoot = (Resolve-Path -LiteralPath $PacketRoot).Path
. (Join-Path $RepoRoot 'scripts\_lib_pie_v1.ps1')

function Die([string]$Message){ throw ('PIE_RUN_PACKET_VERIFY_INVALID: ' + $Message) }
function Read-Text([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ('missing ' + $Path) }
  return [System.IO.File]::ReadAllText($Path,(New-Object System.Text.UTF8Encoding($false)))
}
function Normalize-Relative([string]$Path){ return $Path.Replace('\','/') }
function Is-SafeRelative([string]$Path){
  if([string]::IsNullOrWhiteSpace($Path) -or [System.IO.Path]::IsPathRooted($Path)){ return $false }
  $normalized = Normalize-Relative $Path
  return -not ($normalized -match '(^|/)\.\.(/|$)')
}

$manifestPath = Join-Path $PacketRoot 'manifest.json'
$packetIdPath = Join-Path $PacketRoot 'packet_id.txt'
$sumsPath = Join-Path $PacketRoot 'sha256sums.txt'
try { $manifest = (Read-Text $manifestPath) | ConvertFrom-Json } catch { Die ('manifest JSON invalid: ' + $_.Exception.Message) }
if([string]$manifest.schema -ne 'packet.manifest.v1' -or [string]$manifest.kind -ne 'pie.run_packet' -or [string]$manifest.option -ne 'A'){ Die 'manifest contract mismatch' }
if($manifest.PSObject.Properties.Name -contains 'packet_id'){ Die 'Option A manifest contains packet_id' }

$packetId = (Read-Text $packetIdPath).Trim()
$expectedPacketId = PIE_Sha256HexFile $manifestPath
if($packetId -ne $expectedPacketId){ Die 'packet id mismatch' }
$listed = @{}
foreach($line in @((Read-Text $sumsPath) -split "`n")){
  if([string]::IsNullOrWhiteSpace($line)){ continue }
  $match = [regex]::Match($line.TrimEnd("`r"),'^(?<hash>[0-9a-f]{64})\s{2}(?<path>.+)$')
  if(-not $match.Success){ Die ('invalid sha256sums line ' + $line) }
  $relative = Normalize-Relative $match.Groups['path'].Value
  if(-not (Is-SafeRelative $relative) -or $relative -eq 'sha256sums.txt'){ Die ('unsafe checksum path ' + $relative) }
  if($listed.ContainsKey($relative)){ Die ('duplicate checksum path ' + $relative) }
  $fullPath = Join-Path $PacketRoot $relative.Replace('/','\')
  if(-not (Test-Path -LiteralPath $fullPath -PathType Leaf)){ Die ('checksum target missing ' + $relative) }
  if((PIE_Sha256HexFile $fullPath) -ne $match.Groups['hash'].Value){ Die ('checksum mismatch ' + $relative) }
  $listed[$relative] = $true
}
$actualFiles = @(Get-ChildItem -LiteralPath $PacketRoot -Recurse -File | Where-Object { $_.FullName -ne $sumsPath -and $_.Name -ne 'verification_result.json' } | ForEach-Object { Normalize-Relative $_.FullName.Substring($PacketRoot.Length).TrimStart('\') })
foreach($actualFile in $actualFiles){ if(-not $listed.ContainsKey($actualFile)){ Die ('unlisted packet file ' + $actualFile) } }
foreach($listedFile in @($listed.Keys)){ if($actualFiles -notcontains $listedFile){ Die ('checksum lists unexpected file ' + $listedFile) } }

$payloadRelative = Normalize-Relative ([string]$manifest.payload_rel).TrimEnd('/')
if(-not (Is-SafeRelative $payloadRelative)){ Die 'payload path invalid' }
$runRoot = Join-Path $PacketRoot $payloadRelative.Replace('/','\')
$runVerifier = Join-Path $RepoRoot 'scripts\pie_run_verify_v1.ps1'
$verifyArgs = @('-RepoRoot',$RepoRoot,'-RunRoot',$runRoot)
if($RequireCertifiedInference){ $verifyArgs += '-RequireCertifiedInference' }
$runOutput = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $runVerifier @verifyArgs 2>&1 | Out-String
if($LASTEXITCODE -ne 0 -or $runOutput -notmatch 'PIE_RUN_VERIFY_VALID'){ Die ('sealed run invalid: ' + $runOutput.Trim()) }

$signatureVerifier = Join-Path $RepoRoot 'scripts\packet_verify_v1.ps1'
$signatureArgs = @('-RepoRoot',$RepoRoot,'-PacketRoot',$PacketRoot)
if($RequireSig){ $signatureArgs += '-RequireSig' }
$signatureOutput = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $signatureVerifier @signatureArgs 2>&1 | Out-String
if($LASTEXITCODE -ne 0){ Die ('signature verification failed: ' + $signatureOutput.Trim()) }

$provenance = (Read-Text (Join-Path $runRoot 'provenance.json')) | ConvertFrom-Json
$receiptRoot = Join-Path $RepoRoot 'runs\run_packet_verify'
if(-not (Test-Path -LiteralPath $receiptRoot -PathType Container)){ New-Item -ItemType Directory -Path $receiptRoot -Force | Out-Null }
$receipt = [ordered]@{ schema='pie.run.packet.verify.receipt.v1'; packet_id=$packetId; run_id=[string]$manifest.run_id; inference_certified=[bool]$provenance.inference_certified; signature_required=[bool]$RequireSig; verified_utc=(Get-Date).ToUniversalTime().ToString('o') }
[System.IO.File]::WriteAllText((Join-Path $receiptRoot ($packetId + '.json')),($receipt | ConvertTo-Json -Depth 5),(New-Object System.Text.UTF8Encoding($false)))
Write-Host ('PIE_RUN_PACKET_VERIFY_VALID: ' + $packetId + ' inference_certified=' + ([bool]$provenance.inference_certified).ToString().ToLowerInvariant()) -ForegroundColor Green
