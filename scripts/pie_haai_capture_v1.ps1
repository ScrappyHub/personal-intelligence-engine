param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$SessionId,
  [Parameter(Mandatory=$false)][ValidateRange(0,1000000)][int]$TurnIndex = 0,
  [Parameter(Mandatory=$false)][string]$HaaiRepo = "C:\dev\haai"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $RepoRoot "scripts\_lib_pie_agent_session_v1.ps1")
$HaaiRepo = $(if(Test-Path -LiteralPath $HaaiRepo -PathType Container){ (Resolve-Path -LiteralPath $HaaiRepo).Path } else { throw ("PIE_HAAI_REPO_NOT_FOUND: " + $HaaiRepo) })
$HaaiPython = Join-Path $HaaiRepo "core\python"
$HaaiCli = Join-Path $HaaiPython "haai_core\cli.py"
if(-not (Test-Path -LiteralPath $HaaiCli -PathType Leaf)){ throw ("PIE_HAAI_CLI_NOT_FOUND: " + $HaaiCli) }
if($null -eq (Get-Command python -ErrorAction SilentlyContinue)){ throw "PIE_HAAI_PYTHON_NOT_FOUND" }

function Get-Sha256File([string]$Path){ return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Verify-HaaiPacket([string]$PacketRoot){
  foreach($Name in @("manifest.json","packet_id.txt","sha256sums.txt")){ if(-not (Test-Path -LiteralPath (Join-Path $PacketRoot $Name) -PathType Leaf)){ throw ("PIE_HAAI_PACKET_FILE_MISSING: " + $Name) } }
  $PacketId = (PIE_ReadUtf8Text -Path (Join-Path $PacketRoot "packet_id.txt")).Trim().ToLowerInvariant()
  if($PacketId -notmatch '^[0-9a-f]{64}$'){ throw "PIE_HAAI_PACKET_ID_INVALID" }
  if((Get-Sha256File -Path (Join-Path $PacketRoot "manifest.json")) -ne $PacketId){ throw "PIE_HAAI_PACKET_ID_MISMATCH" }
  $Seen = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::Ordinal)
  foreach($Line in @((PIE_ReadUtf8Text -Path (Join-Path $PacketRoot "sha256sums.txt")) -split "`r?`n")){
    if([string]::IsNullOrWhiteSpace($Line)){ continue }
    if($Line -notmatch '^([0-9a-fA-F]{64})  ([^\\]+)$'){ throw "PIE_HAAI_SHA256SUMS_LINE_INVALID" }
    $Expected = $Matches[1].ToLowerInvariant()
    $Relative = $Matches[2].Replace('/','\')
    if($Relative -match '(^|\\)\.\.(\\|$)' -or [IO.Path]::IsPathRooted($Relative)){ throw "PIE_HAAI_PACKET_PATH_INVALID" }
    if(-not $Seen.Add($Relative)){ throw "PIE_HAAI_PACKET_PATH_DUPLICATE" }
    $Path = [IO.Path]::GetFullPath((Join-Path $PacketRoot $Relative))
    if(-not $Path.StartsWith(([IO.Path]::GetFullPath($PacketRoot) + [IO.Path]::DirectorySeparatorChar),[StringComparison]::OrdinalIgnoreCase)){ throw "PIE_HAAI_PACKET_PATH_ESCAPE" }
    if(-not (Test-Path -LiteralPath $Path -PathType Leaf) -or (Get-Sha256File -Path $Path) -ne $Expected){ throw ("PIE_HAAI_PACKET_FILE_HASH_MISMATCH: " + $Relative) }
  }
  if($Seen.Count -lt 3){ throw "PIE_HAAI_PACKET_FILE_COUNT_INVALID" }
  return $PacketId
}

$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)
$Lock = PIE_AcquireSessionLock -RunRoot $RunRoot
try {
  $Session = PIE_GetAgentSession -RepoRoot $RepoRoot -SessionId $SessionId -RequireIntegrity -OperationLockHeld
  $Turns = @($Session.conversation_turns)
  if($Turns.Count -eq 0){ throw ("PIE_HAAI_SESSION_HAS_NO_TURNS: " + $SessionId) }
  if($TurnIndex -eq 0){ $TurnIndex = $Turns.Count }
  if($TurnIndex -gt $Turns.Count){ throw ("PIE_HAAI_TURN_NOT_FOUND: " + $TurnIndex) }
  $Turn = $Turns[$TurnIndex - 1]
  $TurnHash = [string]$Turn.turn_sha256
  if($TurnHash -notmatch '^[0-9a-f]{64}$'){ throw "PIE_HAAI_TURN_HASH_INVALID" }
  $ExportRoot = Join-Path $RunRoot ("haai\turn_" + $TurnIndex.ToString("000000") + "_" + $TurnHash.Substring(0,12))
  $CaptureRoot = Join-Path $ExportRoot "capture"
  $PacketRoot = Join-Path $ExportRoot "packet"
  $InputPath = Join-Path $ExportRoot "capture_input.json"
  $ReceiptPath = Join-Path $ExportRoot "receipt.json"

  if(Test-Path -LiteralPath $ReceiptPath -PathType Leaf){
    $Receipt = PIE_ReadUtf8Text -Path $ReceiptPath | ConvertFrom-Json
    $PacketId = Verify-HaaiPacket -PacketRoot $PacketRoot
    if([string]$Receipt.schema -ne "pie.haai.capture.receipt.v1" -or [string]$Receipt.turn_sha256 -ne $TurnHash -or [string]$Receipt.packet_id -ne $PacketId){ throw "PIE_HAAI_RECEIPT_MISMATCH" }
    Write-Host ("PIE_HAAI_CAPTURE_ALREADY_VERIFIED: " + $PacketId) -ForegroundColor Green
    Write-Host ("packet: " + $PacketRoot)
    return
  }
  if(Test-Path -LiteralPath $ExportRoot){ throw ("PIE_HAAI_PARTIAL_EXPORT_PRESENT: " + $ExportRoot) }
  New-Item -ItemType Directory -Force -Path $ExportRoot | Out-Null
  $Provenance = [ordered]@{schema="pie.haai.turn.provenance.v1";session_id=$SessionId;binding_sha256=$Session.binding_sha256;project_identity_sha256=$Session.project_identity_sha256;model_identity_sha256=$Session.model_identity_sha256;turn_index=$TurnIndex;turn_sha256=$TurnHash}
  $Capture = [ordered]@{
    producer=[ordered]@{name="PIE";version="1";instance_id=$Session.binding_sha256}
    messages=@([ordered]@{role="system";content=($Provenance | ConvertTo-Json -Compress)},[ordered]@{role="user";content=[string]$Turn.message})
    assistant_text=[string]$Turn.response
    model=[ordered]@{provider=[string]$Session.backend;model_id=[string]$Session.model}
    strength="evidence"
  }
  PIE_WriteAtomicText -Path $InputPath -Text (($Capture | ConvertTo-Json -Depth 12) + "`n")
  $PreviousPythonPath = $env:PYTHONPATH
  $PreviousNoBytecode = $env:PYTHONDONTWRITEBYTECODE
  try {
    $env:PYTHONPATH = $HaaiPython
    $env:PYTHONDONTWRITEBYTECODE = "1"
    & python -m haai_core.cli capture --input $InputPath --out $CaptureRoot | Out-Host
    if($LASTEXITCODE -ne 0){ throw "PIE_HAAI_CAPTURE_FAILED" }
    & python -m haai_core.cli build --capture $CaptureRoot --out $PacketRoot | Out-Host
    if($LASTEXITCODE -ne 0){ throw "PIE_HAAI_BUILD_FAILED" }
    & python -m haai_core.cli verify --packet $PacketRoot | Out-Host
    if($LASTEXITCODE -ne 0){ throw "PIE_HAAI_VERIFY_FAILED" }
  }
  finally { $env:PYTHONPATH = $PreviousPythonPath; $env:PYTHONDONTWRITEBYTECODE = $PreviousNoBytecode }
  $PacketId = Verify-HaaiPacket -PacketRoot $PacketRoot
  $Receipt = [ordered]@{schema="pie.haai.capture.receipt.v1";session_id=$SessionId;binding_sha256=$Session.binding_sha256;turn_index=$TurnIndex;turn_sha256=$TurnHash;packet_id=$PacketId;packet_path=$PacketRoot;haai_repo=$HaaiRepo;status="verified";created_utc=[DateTime]::UtcNow.ToString("o")}
  PIE_WriteAtomicText -Path $ReceiptPath -Text (($Receipt | ConvertTo-Json -Depth 10) + "`n")
  [IO.File]::AppendAllText((Join-Path $RunRoot "haai_receipts.ndjson"),(($Receipt | ConvertTo-Json -Compress) + "`n"),(New-Object Text.UTF8Encoding($false)))
  Write-Host ("PIE_HAAI_CAPTURE_OK: " + $PacketId) -ForegroundColor Green
  Write-Host ("packet: " + $PacketRoot)
}
finally { $Lock.Dispose() }
