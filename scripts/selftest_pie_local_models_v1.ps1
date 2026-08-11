param([Parameter(Mandatory=$true)][string]$RepoRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$TestRoot = Join-Path $RepoRoot "runs\selftest_local_models"
$FakeOllama = Join-Path $TestRoot "ollama.cmd"
$StatePath = Join-Path $TestRoot "runtime_config.json"
$Enc = New-Object System.Text.UTF8Encoding($false)
New-Item -ItemType Directory -Force -Path $TestRoot | Out-Null

$Fake = @"
@echo off
if "%1"=="list" (
  echo NAME                 ID              SIZE      MODIFIED
  echo tinyllama:latest     abc123          637 MB    1 minute ago
  exit /b 0
)
if "%1"=="pull" (
  echo pulled %2
  exit /b 0
)
exit /b 2
"@
[System.IO.File]::WriteAllText($FakeOllama,$Fake.Replace("`r`n","`n"),$Enc)
$ModelsScript = Join-Path $RepoRoot "scripts\pie_models_v1.ps1"

& $ModelsScript -RepoRoot $RepoRoot -Action catalog | Out-Null
& $ModelsScript -RepoRoot $RepoRoot -Action list -OllamaPath $FakeOllama -StatePath $StatePath | Out-Null
& $ModelsScript -RepoRoot $RepoRoot -Action pull -Model "tinyllama:latest" -OllamaPath $FakeOllama -StatePath $StatePath | Out-Null
& $ModelsScript -RepoRoot $RepoRoot -Action use -Model "tinyllama:latest" -OllamaPath $FakeOllama -StatePath $StatePath | Out-Null

$Config = [System.IO.File]::ReadAllText($StatePath,$Enc) | ConvertFrom-Json
if($Config.schema -ne "pie.local.runtime.config.v1"){ throw "PIE_LOCAL_MODELS_SCHEMA_BAD" }
if($Config.backend -ne "ollama"){ throw "PIE_LOCAL_MODELS_BACKEND_BAD" }
if($Config.model -ne "tinyllama:latest"){ throw "PIE_LOCAL_MODELS_SELECTION_BAD" }
$Events = [System.IO.File]::ReadAllText((Join-Path $TestRoot "events.ndjson"),$Enc)
if($Events -notmatch '"event":"model_pulled"'){ throw "PIE_LOCAL_MODELS_PULL_EVENT_MISSING" }
if($Events -notmatch '"event":"model_selected"'){ throw "PIE_LOCAL_MODELS_SELECT_EVENT_MISSING" }

$FailedAsExpected = $false
try { & $ModelsScript -RepoRoot $RepoRoot -Action use -Model "missing:latest" -OllamaPath $FakeOllama -StatePath $StatePath | Out-Null }
catch { if($_.Exception.Message -like "PIE_MODEL_NOT_LOCAL:*"){ $FailedAsExpected = $true } }
if(-not $FailedAsExpected){ throw "PIE_LOCAL_MODELS_MISSING_MODEL_NOT_REJECTED" }

$PullVerifyFailed = $false
try { & $ModelsScript -RepoRoot $RepoRoot -Action pull -Model "not-reported:latest" -OllamaPath $FakeOllama -StatePath $StatePath | Out-Null }
catch { if($_.Exception.Message -like "PIE_MODEL_PULL_VERIFY_FAILED:*"){ $PullVerifyFailed = $true } }
if(-not $PullVerifyFailed){ throw "PIE_LOCAL_MODELS_UNVERIFIED_PULL_ALLOWED" }
$Receipts = @(Get-ChildItem -LiteralPath (Join-Path $TestRoot "downloads") -File -Filter "model_*.json" | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json })
if(@($Receipts | Where-Object { $_.status -eq "complete" -and [bool]$_.verified_local }).Count -lt 1){ throw "PIE_LOCAL_MODELS_COMPLETE_RECEIPT_MISSING" }
if(@($Receipts | Where-Object { $_.status -eq "failed" -and -not [bool]$_.verified_local }).Count -lt 1){ throw "PIE_LOCAL_MODELS_FAILED_RECEIPT_MISSING" }
Write-Host "PIE_LOCAL_MODELS_SELFTEST_OK" -ForegroundColor Green
