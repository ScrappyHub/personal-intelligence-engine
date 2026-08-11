param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$false)][string]$HaaiRepo = "C:\dev\haai"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$HaaiRepo = (Resolve-Path -LiteralPath $HaaiRepo).Path
$SessionId = "pie_haai_adapter_selftest"
$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)
if(Test-Path -LiteralPath $RunRoot -PathType Container){ Remove-Item -LiteralPath $RunRoot -Recurse -Force }
function Get-HaaiSourceSnapshot {
  $Root = Join-Path $HaaiRepo "core\python\haai_core"
  $Rows = @(Get-ChildItem -LiteralPath $Root -Recurse -File | Sort-Object FullName | ForEach-Object {
    [ordered]@{path=$_.FullName.Substring($Root.Length).TrimStart('\').Replace('\','/');bytes=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
  })
  return ($Rows | ConvertTo-Json -Depth 5 -Compress)
}
$BeforeStatus = Get-HaaiSourceSnapshot

& (Join-Path $RepoRoot "scripts\pie_agent_start_v1.ps1") -RepoRoot $RepoRoot -SessionId $SessionId -Backend mock -Model "haai-adapter-mock" -ProjectRepo $RepoRoot -Goal "verify explicit HAAI evidence export" | Out-Null
& (Join-Path $RepoRoot "scripts\pie_agent_send_v1.ps1") -RepoRoot $RepoRoot -SessionId $SessionId -Message "preserve this exact turn" -ConversationMessage "preserve this exact turn" -TimeoutSeconds 30 -MaxAttempts 1 | Out-Null
& (Join-Path $RepoRoot "scripts\pie_haai_capture_v1.ps1") -RepoRoot $RepoRoot -SessionId $SessionId -HaaiRepo $HaaiRepo | Out-Null

$Receipt = Get-ChildItem -LiteralPath (Join-Path $RunRoot "haai") -Recurse -File -Filter "receipt.json" | Select-Object -First 1 | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json }
if($null -eq $Receipt -or [string]$Receipt.schema -ne "pie.haai.capture.receipt.v1" -or [string]$Receipt.status -ne "verified"){ throw "PIE_HAAI_SELFTEST_RECEIPT_BAD" }
if([string]$Receipt.turn_sha256 -notmatch '^[0-9a-f]{64}$' -or [string]$Receipt.packet_id -notmatch '^[0-9a-f]{64}$'){ throw "PIE_HAAI_SELFTEST_HASH_BAD" }
$Input = Get-ChildItem -LiteralPath (Join-Path $RunRoot "haai") -Recurse -File -Filter "capture_input.json" | Select-Object -First 1 | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json }
if([string]$Input.messages[0].content -notmatch [regex]::Escape([string]$Receipt.turn_sha256) -or [string]$Input.messages[1].content -ne "preserve this exact turn"){ throw "PIE_HAAI_SELFTEST_PROVENANCE_BAD" }

& (Join-Path $RepoRoot "scripts\pie_haai_capture_v1.ps1") -RepoRoot $RepoRoot -SessionId $SessionId -HaaiRepo $HaaiRepo | Out-Null
if(@(Get-Content -LiteralPath (Join-Path $RunRoot "haai_receipts.ndjson")).Count -ne 1){ throw "PIE_HAAI_SELFTEST_NOT_IDEMPOTENT" }

$Envelope = Join-Path ([string]$Receipt.packet_path) "payload\run_envelope.json"
[IO.File]::AppendAllText($Envelope,"tamper",(New-Object Text.UTF8Encoding($false)))
$CorruptRejected = $false
try { & (Join-Path $RepoRoot "scripts\pie_haai_capture_v1.ps1") -RepoRoot $RepoRoot -SessionId $SessionId -HaaiRepo $HaaiRepo | Out-Null }
catch { if($_.Exception.Message -like "PIE_HAAI_PACKET_FILE_HASH_MISMATCH:*"){ $CorruptRejected = $true } }
if(-not $CorruptRejected){ throw "PIE_HAAI_SELFTEST_CORRUPTION_ACCEPTED" }

. (Join-Path $RepoRoot "scripts\_lib_pie_agent_session_v1.ps1")
$Session = PIE_GetAgentSession -RepoRoot $RepoRoot -SessionId $SessionId -RequireIntegrity
if(@($Session.conversation_turns).Count -ne 1 -or [string]$Session.conversation_turns[0].message -ne "preserve this exact turn"){ throw "PIE_HAAI_SELFTEST_CONVERSATION_MUTATED" }
$AfterStatus = Get-HaaiSourceSnapshot
if($AfterStatus -ne $BeforeStatus){ throw "PIE_HAAI_SELFTEST_SOURCE_REPOSITORY_MUTATED" }
Write-Host "PIE_HAAI_ADAPTER_SELFTEST_OK" -ForegroundColor Green
