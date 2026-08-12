param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$Text,
  [Parameter(Mandatory=$false)][ValidateSet("active","coding","project")][string]$Lane = "active",
  [Parameter(Mandatory=$false)][string]$Project = "",
  [Parameter(Mandatory=$false)][string]$ProjectRepo = "",
  [Parameter(Mandatory=$false)][switch]$Yes,
  [Parameter(Mandatory=$false)][string]$MemoryRoot = "",
  [Parameter(Mandatory=$false)][string]$PolicyPath = "",
  [Parameter(Mandatory=$false)][string]$ReceiptPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$MemoryLock = $null
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $RepoRoot "scripts\_lib_pie_memory_v1.ps1")
. (Join-Path $RepoRoot "scripts\_lib_pie_agent_session_v1.ps1")
$Enc = New-Object System.Text.UTF8Encoding($false)

if([string]::IsNullOrWhiteSpace($Text)){ throw "PIE_MEMORY_TEXT_REQUIRED" }
if($Lane -eq "project" -and [string]::IsNullOrWhiteSpace($Project)){ throw "PIE_PROJECT_MEMORY_REQUIRES_PROJECT" }
if($Lane -eq "project" -and [string]::IsNullOrWhiteSpace($ProjectRepo)){ throw "PIE_PROJECT_MEMORY_REQUIRES_REPO" }
if(-not [string]::IsNullOrWhiteSpace($ProjectRepo)){
  if(-not (Test-Path -LiteralPath $ProjectRepo -PathType Container)){ throw ("PIE_MEMORY_PROJECT_REPO_NOT_FOUND: " + $ProjectRepo) }
  $ProjectRepo = (Resolve-Path -LiteralPath $ProjectRepo).Path
}
$ProjectIdentityHash = $(if([string]::IsNullOrWhiteSpace($ProjectRepo)){ "" } else { PIE_ProjectIdentityHash -ProjectRepo $ProjectRepo })

$Policy = PIE_MemoryPolicy -RepoRoot $RepoRoot -PolicyPath $PolicyPath
$Mode = [string]$Policy.mode
if($Mode -notin @("ask","auto_accept","manual_only","off")){ throw ("PIE_MEMORY_POLICY_MODE_INVALID: " + $Mode) }
if($Mode -eq "off"){ throw "PIE_MEMORY_DENIED: MEMORY_POLICY_OFF" }
if($Lane -eq "coding" -and -not [bool]$Policy.coding_memory_enabled){ throw "PIE_MEMORY_DENIED: CODING_MEMORY_DISABLED" }
if($Lane -eq "project" -and -not [bool]$Policy.project_memory_enabled){ throw "PIE_MEMORY_DENIED: PROJECT_MEMORY_DISABLED" }

$Decision = "ALLOW"
$Reason = if($Mode -eq "auto_accept"){ "MEMORY_POLICY_AUTO_ACCEPT" } elseif($Mode -eq "manual_only"){ "MEMORY_POLICY_MANUAL" } else { "MEMORY_POLICY_ASK" }

if($Mode -eq "ask"){
  $PolicyScript = Join-Path $RepoRoot "scripts\pie_policy_decide_v1.ps1"
  if(-not (Test-Path -LiteralPath $PolicyScript -PathType Leaf)){ throw "PIE_POLICY_SCRIPT_MISSING" }
  $PolicyArgs = @("-RepoRoot",$RepoRoot,"-Event","memory_accept","-Text",$Text)
  if(-not [string]::IsNullOrWhiteSpace($Project)){ $PolicyArgs += @("-Project",$Project) }
  $PolicyOut = @(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $PolicyScript @PolicyArgs 2>&1) -join "`n"
  if($LASTEXITCODE -ne 0){ throw ("PIE_POLICY_DECISION_FAIL: " + $PolicyOut) }
  $DecisionLine = @(($PolicyOut -split "`n") | Where-Object { $_ -like "PIE_POLICY_DECISION:*" } | Select-Object -First 1)
  if($DecisionLine.Count -ne 1){ throw "PIE_POLICY_DECISION_OUTPUT_MISSING" }
  if([string]$DecisionLine[0] -notmatch 'PIE_POLICY_DECISION:\s*([A-Z_]+)\s*reason_code=([A-Z0-9_]+)'){ throw "PIE_POLICY_DECISION_PARSE_FAIL" }
  $PolicyDecision = [string]$Matches[1]
  $Reason = [string]$Matches[2]
  if($PolicyDecision -eq "DENY"){ throw ("PIE_MEMORY_DENIED: " + $Reason) }
  if($PolicyDecision -notin @("ALLOW","WARN","ASK_CONFIRMATION")){ throw ("PIE_MEMORY_UNKNOWN_POLICY_DECISION: " + $PolicyDecision) }
  if($PolicyDecision -eq "ASK_CONFIRMATION" -and -not $Yes){
    $Answer = Read-Host "Accept memory? (Y/N)"
    if(([string]$Answer).Trim().ToUpperInvariant() -ne "Y"){ throw "PIE_MEMORY_CONFIRMATION_DECLINED" }
  }
  $Decision = "ALLOW"
}

if([string]::IsNullOrWhiteSpace($MemoryRoot)){ $MemoryRoot = Join-Path $RepoRoot "memory" }
$MemoryLock = PIE_AcquireMemoryLock -MemoryRoot $MemoryRoot
trap {
  if($null -ne $MemoryLock){ $MemoryLock.Dispose(); $MemoryLock = $null }
  throw $_
}
if($Lane -eq "active"){ $TargetDir = Join-Path $MemoryRoot "active" }
elseif($Lane -eq "coding"){ $TargetDir = Join-Path $MemoryRoot "coding" }
else {
  $RepoKey = (PIE_MemorySha256Text -Text $ProjectRepo).Substring(0,12)
  $ProjectSafe = ($Project.ToLowerInvariant() -replace '[^a-z0-9._-]','_') + "_" + $RepoKey
  $TargetDir = Join-Path $MemoryRoot ("projects\" + $ProjectSafe)
}

$MemoryId = PIE_MemoryId -Lane $Lane -Project $Project -ProjectRepo $ProjectRepo -Text $Text
$Existing = @(PIE_MemoryRecords -RepoRoot $RepoRoot -MemoryRoot $MemoryRoot -Project $Project -ProjectRepo $ProjectRepo -ProjectIdentityHash $ProjectIdentityHash -Lane $Lane -Limit 200 | Where-Object { $_.memory_id -eq $MemoryId })
if($Existing.Count -gt 0){
  Write-Host ("PIE_MEMORY_ALREADY_PRESENT: " + $MemoryId) -ForegroundColor Yellow
  $MemoryLock.Dispose()
  $MemoryLock = $null
  return
}

New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
$MemoryPath = Join-Path $TargetDir "memory.ndjson"
$Obj = [ordered]@{
  schema = "pie.memory.record.v1"
  memory_id = $MemoryId
  lane = $Lane
  project = $Project
  project_repo = $ProjectRepo
  project_identity_sha256 = $ProjectIdentityHash
  text = $Text
  status = "active"
  policy_decision = $Decision
  policy_reason_code = $Reason
  created_utc = [DateTime]::UtcNow.ToString("o")
}
[System.IO.File]::AppendAllText($MemoryPath,(($Obj | ConvertTo-Json -Depth 8 -Compress) + "`n"),$Enc)
PIE_MemoryAppendReceipt -RepoRoot $RepoRoot -Event "accepted" -MemoryId $MemoryId -Lane $Lane -Project $Project -ReceiptPath $ReceiptPath
$MemoryLock.Dispose()
$MemoryLock = $null

Write-Host ("PIE_MEMORY_ACCEPT_OK: " + $MemoryId) -ForegroundColor Green
Write-Host ("path: " + $MemoryPath)
