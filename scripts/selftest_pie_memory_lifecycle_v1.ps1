param([Parameter(Mandatory=$true)][string]$RepoRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Root = Join-Path $RepoRoot "runs\pie_memory_lifecycle_selftest"
$MemoryRoot = Join-Path $Root "memory"
$PolicyPath = Join-Path $Root "policy.json"
$ReceiptPath = Join-Path $Root "receipts.ndjson"
$Enc = New-Object System.Text.UTF8Encoding($false)
if(Test-Path -LiteralPath $Root -PathType Container){ Remove-Item -LiteralPath $Root -Recurse -Force }
New-Item -ItemType Directory -Force -Path $Root | Out-Null

function Write-Policy([string]$Mode){
  $Policy = @{schema="pie.memory.policy.v1";mode=$Mode;allowed_modes=@("ask","auto_accept","manual_only","off");default_lane="active";repo_memory_enabled=$true;project_memory_enabled=$true;coding_memory_enabled=$true}
  [System.IO.File]::WriteAllText($PolicyPath,(($Policy | ConvertTo-Json -Depth 8) + "`n"),$Enc)
}

Write-Policy -Mode "auto_accept"
$Accept = Join-Path $RepoRoot "scripts\pie_memory_accept_v1.ps1"
& $Accept -RepoRoot $RepoRoot -Text "Use stable PowerShell examples." -Lane "coding" -MemoryRoot $MemoryRoot -PolicyPath $PolicyPath -ReceiptPath $ReceiptPath | Out-Null
& $Accept -RepoRoot $RepoRoot -Text "Use stable PowerShell examples." -Lane "coding" -MemoryRoot $MemoryRoot -PolicyPath $PolicyPath -ReceiptPath $ReceiptPath | Out-Null

. (Join-Path $RepoRoot "scripts\_lib_pie_memory_v1.ps1")
$Records = @(PIE_MemoryRecords -RepoRoot $RepoRoot -MemoryRoot $MemoryRoot -Query "PowerShell" -Lane "all" -Limit 25)
if($Records.Count -ne 1){ throw ("PIE_MEMORY_LIFECYCLE_DUPLICATE_BAD: " + [string]$Records.Count) }
$MemoryId = $Records[0].memory_id

Write-Policy -Mode "off"
$Denied = $false
try { & $Accept -RepoRoot $RepoRoot -Text "must be denied" -Lane "active" -MemoryRoot $MemoryRoot -PolicyPath $PolicyPath -ReceiptPath $ReceiptPath | Out-Null }
catch { if($_.Exception.Message -eq "PIE_MEMORY_DENIED: MEMORY_POLICY_OFF"){ $Denied = $true } }
if(-not $Denied){ throw "PIE_MEMORY_LIFECYCLE_OFF_NOT_ENFORCED" }

& (Join-Path $RepoRoot "scripts\pie_memory_forget_v1.ps1") -RepoRoot $RepoRoot -MemoryId $MemoryId -MemoryRoot $MemoryRoot -ReceiptPath $ReceiptPath | Out-Null
$AfterForget = @(PIE_MemoryRecords -RepoRoot $RepoRoot -MemoryRoot $MemoryRoot -Lane "all" -Limit 25)
if($AfterForget.Count -ne 0){ throw "PIE_MEMORY_LIFECYCLE_FORGET_FAILED" }

Write-Policy -Mode "auto_accept"
& $Accept -RepoRoot $RepoRoot -Text "Use stable PowerShell examples." -Lane "coding" -MemoryRoot $MemoryRoot -PolicyPath $PolicyPath -ReceiptPath $ReceiptPath | Out-Null
$AfterReaccept = @(PIE_MemoryRecords -RepoRoot $RepoRoot -MemoryRoot $MemoryRoot -Lane "all" -Limit 25)
if($AfterReaccept.Count -ne 1){ throw "PIE_MEMORY_LIFECYCLE_REACCEPT_FAILED" }
$Receipts = [System.IO.File]::ReadAllText($ReceiptPath,$Enc)
if($Receipts -notmatch '"event":"accepted"' -or $Receipts -notmatch '"event":"forgotten"'){ throw "PIE_MEMORY_LIFECYCLE_RECEIPTS_MISSING" }

Write-Host "PIE_MEMORY_LIFECYCLE_SELFTEST_OK" -ForegroundColor Green
