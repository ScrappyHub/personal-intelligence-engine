param([Parameter(Mandatory=$true)][string]$RepoRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Node = Get-Command node -ErrorAction SilentlyContinue
if($null -eq $Node){ throw "PIE_WORKBENCH_SELFTEST_NODE_REQUIRED" }

$SessionId = "pie_workbench_api_selftest"
$BackupPassphrase = "Workbench backup selftest 2026!"
$SessionRoot = Join-Path $RepoRoot ("runs\" + $SessionId)
$TestRoot = Join-Path $RepoRoot "runs\workbench_selftest"
if(Test-Path -LiteralPath $SessionRoot -PathType Container){ Remove-Item -LiteralPath $SessionRoot -Recurse -Force }
if(Test-Path -LiteralPath $TestRoot -PathType Container){ Remove-Item -LiteralPath $TestRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path $TestRoot | Out-Null

$Port = Get-Random -Minimum 44000 -Maximum 48000
$BaseUri = "http://127.0.0.1:" + $Port
$Stdout = Join-Path $TestRoot "server.stdout.txt"
$Stderr = Join-Path $TestRoot "server.stderr.txt"
$Server = Join-Path $RepoRoot "workbench\server.js"
$Process = $null

function Invoke-PieWorkbenchJson {
  param(
    [Parameter(Mandatory=$true)][string]$Method,
    [Parameter(Mandatory=$true)][string]$Uri,
    [Parameter(Mandatory=$true)][string]$Token,
    [Parameter(Mandatory=$false)]$Body = $null
  )
  $Arguments = @{ Method = $Method; Uri = $Uri; Headers = @{ "X-PIE-Workbench-Token" = $Token }; TimeoutSec = 45 }
  if($null -ne $Body){
    $Arguments.ContentType = "application/json"
    $Arguments.Body = ($Body | ConvertTo-Json -Depth 8 -Compress)
  }
  return Invoke-RestMethod @Arguments
}

try {
  $Process = Start-Process -FilePath $Node.Source -ArgumentList @($Server,"--repo-root",$RepoRoot,"--port",[string]$Port,"--allow-mock") `
    -WorkingDirectory $RepoRoot -WindowStyle Hidden -RedirectStandardOutput $Stdout -RedirectStandardError $Stderr -PassThru

  $Ready = $false
  for($Attempt = 0; $Attempt -lt 40; $Attempt++){
    Start-Sleep -Milliseconds 250
    if($Process.HasExited){
      $Detail = $(if(Test-Path -LiteralPath $Stderr){ Get-Content -LiteralPath $Stderr -Raw } else { "server exited" })
      throw ("PIE_WORKBENCH_SELFTEST_SERVER_EXITED: " + $Detail)
    }
    try {
      $Health = Invoke-RestMethod -Method Get -Uri ($BaseUri + "/health") -TimeoutSec 2
      if([string]$Health.status -eq "ok"){ $Ready = $true; break }
    } catch {}
  }
  if(-not $Ready){ throw "PIE_WORKBENCH_SELFTEST_SERVER_NOT_READY" }

  $Page = Invoke-WebRequest -Method Get -Uri ($BaseUri + "/") -TimeoutSec 10 -UseBasicParsing
  if($Page.StatusCode -ne 200){ throw "PIE_WORKBENCH_SELFTEST_PAGE_STATUS_BAD" }
  if([string]$Page.Headers["X-Frame-Options"] -ne "DENY"){ throw "PIE_WORKBENCH_SELFTEST_SECURITY_HEADERS_MISSING" }
  if($Page.Content -notmatch "PIE Workbench" -or $Page.Content -notmatch "Your workspace is ready"){ throw "PIE_WORKBENCH_SELFTEST_UI_MARKERS_MISSING" }
  if($Page.Content -notmatch '<style>:root' -or $Page.Content -notmatch "<script>'use strict'"){
    throw "PIE_WORKBENCH_SELFTEST_INLINE_ASSETS_MISSING"
  }
  if($Page.Content -notmatch 'href="/styles.css\?v=20260806.5"' -or $Page.Content -notmatch 'src="/app.js\?v=20260806.5"'){
    throw "PIE_WORKBENCH_SELFTEST_FALLBACK_ASSETS_MISSING"
  }
  if([string]$Health.build -ne '2026.08.06.5'){ throw "PIE_WORKBENCH_SELFTEST_BUILD_MARKER_MISSING" }
  $Sunset = Invoke-WebRequest -Method Get -Uri ($BaseUri + "/sunset-horizon.png") -TimeoutSec 10 -UseBasicParsing
  if($Sunset.StatusCode -ne 200 -or [string]$Sunset.Headers['Content-Type'] -ne 'image/png' -or $Sunset.RawContentLength -lt 100000){
    throw "PIE_WORKBENCH_SELFTEST_SUNSET_ASSET_BAD"
  }
  $Manifest = Invoke-RestMethod -Method Get -Uri ($BaseUri + "/manifest.webmanifest") -TimeoutSec 10
  if([string]$Manifest.display -ne 'standalone' -or [string]$Manifest.short_name -ne 'PIE'){ throw "PIE_WORKBENCH_SELFTEST_PWA_MANIFEST_BAD" }
  $Icon = Invoke-WebRequest -Method Get -Uri ($BaseUri + "/pie-icon.png") -TimeoutSec 10 -UseBasicParsing
  if($Icon.StatusCode -ne 200 -or [string]$Icon.Headers['Content-Type'] -ne 'image/png' -or $Icon.RawContentLength -lt 100000){ throw "PIE_WORKBENCH_SELFTEST_ICON_BAD" }
  if($Page.Content -notmatch 'data-theme-choice="dusk"' -or $Page.Content -notmatch 'id="repoPickerButton"'){ throw "PIE_WORKBENCH_SELFTEST_DESKTOP_UI_MISSING" }
  if($Page.Content -notmatch 'syncConversation' -or $Page.Content -notmatch '/api/session/history'){ throw "PIE_WORKBENCH_SELFTEST_HISTORY_UI_MISSING" }
  if($Page.Content -notmatch 'id="sessionSelect"' -or $Page.Content -notmatch 'id="newSessionButton"' -or $Page.Content -notmatch 'id="backupButton"' -or $Page.Content -notmatch 'id="restoreButton"' -or $Page.Content -notmatch '/api/sessions'){
    throw "PIE_WORKBENCH_SELFTEST_SESSION_BROWSER_MISSING"
  }
  $BootstrapMatch = [regex]::Match($Page.Content,'window\.__PIE_BOOTSTRAP__\s*=\s*(\{[^;]+\});')
  if(-not $BootstrapMatch.Success){ throw "PIE_WORKBENCH_SELFTEST_BOOTSTRAP_MISSING" }
  $Bootstrap = $BootstrapMatch.Groups[1].Value | ConvertFrom-Json
  $Token = [string]$Bootstrap.requestToken
  if([string]::IsNullOrWhiteSpace($Token)){ throw "PIE_WORKBENCH_SELFTEST_TOKEN_MISSING" }

  $Denied = $false
  try { Invoke-RestMethod -Method Get -Uri ($BaseUri + "/api/state") -TimeoutSec 10 | Out-Null }
  catch { if([int]$_.Exception.Response.StatusCode -eq 403){ $Denied = $true } }
  if(-not $Denied){ throw "PIE_WORKBENCH_SELFTEST_UNAUTHENTICATED_API_ALLOWED" }

  $State = Invoke-PieWorkbenchJson -Method Get -Uri ($BaseUri + "/api/state?sessionId=" + $SessionId) -Token $Token
  if([string]$State.schema -ne "pie.workbench.state.v1"){ throw "PIE_WORKBENCH_SELFTEST_STATE_SCHEMA_BAD" }
  if($null -eq $State.models -or $null -eq $State.integrations -or $null -eq $State.haai){ throw "PIE_WORKBENCH_SELFTEST_STATE_INCOMPLETE" }
  if(@($State.models.catalog).Count -lt 14){ throw "PIE_WORKBENCH_SELFTEST_CATALOG_MISSING" }
  if([int64]$State.system.memoryBytes -lt 1 -or [string]::IsNullOrWhiteSpace([string]$State.system.modelRoot)){
    throw "PIE_WORKBENCH_SELFTEST_SYSTEM_PREFLIGHT_MISSING"
  }
  $Projects = Invoke-PieWorkbenchJson -Method Get -Uri ($BaseUri + "/api/projects") -Token $Token
  if([string]$Projects.schema -ne "pie.project.index.v1" -or @($Projects.projects | Where-Object { [string]$_.path -ieq $RepoRoot }).Count -ne 1){
    throw "PIE_WORKBENCH_SELFTEST_PROJECT_INDEX_BAD"
  }

  $RuntimeInstall = Invoke-PieWorkbenchJson -Method Post -Uri ($BaseUri + "/api/runtime/install") -Token $Token -Body @{}
  $RuntimeStart = Invoke-PieWorkbenchJson -Method Post -Uri ($BaseUri + "/api/runtime/start") -Token $Token -Body @{}
  if(-not [bool]$RuntimeInstall.ok -or -not [bool]$RuntimeStart.ok){ throw "PIE_WORKBENCH_SELFTEST_RUNTIME_SETUP_BAD" }

  $InvalidModelRejected = $false
  try {
    Invoke-PieWorkbenchJson -Method Post -Uri ($BaseUri + "/api/models/pull") -Token $Token -Body @{ model = "bad model name" } | Out-Null
  } catch { if([int]$_.Exception.Response.StatusCode -eq 400){ $InvalidModelRejected = $true } }
  if(-not $InvalidModelRejected){ throw "PIE_WORKBENCH_SELFTEST_INVALID_MODEL_ALLOWED" }

  $PullStarted = Invoke-PieWorkbenchJson -Method Post -Uri ($BaseUri + "/api/models/pull") -Token $Token -Body @{ model = "workbench-mock:latest" }
  if(-not [bool]$PullStarted.ok -or [string]::IsNullOrWhiteSpace([string]$PullStarted.job.id)){ throw "PIE_WORKBENCH_SELFTEST_PULL_JOB_START_BAD" }
  $PullComplete = $false
  for($PullAttempt = 0; $PullAttempt -lt 20; $PullAttempt++){
    Start-Sleep -Milliseconds 100
    $PullState = Invoke-PieWorkbenchJson -Method Get -Uri ($BaseUri + "/api/models/pull/status?jobId=" + [string]$PullStarted.job.id) -Token $Token
    if([string]$PullState.job.state -eq "complete"){
      if([int]$PullState.job.percent -ne 100){ throw "PIE_WORKBENCH_SELFTEST_PULL_JOB_PERCENT_BAD" }
      $PullComplete = $true
      break
    }
  }
  if(-not $PullComplete){ throw "PIE_WORKBENCH_SELFTEST_PULL_JOB_NOT_COMPLETE" }

  $InvalidRejected = $false
  try {
    Invoke-PieWorkbenchJson -Method Post -Uri ($BaseUri + "/api/session/start") -Token $Token -Body @{ sessionId = "bad id"; targetRepo = $RepoRoot; backend = "mock" } | Out-Null
  } catch { if([int]$_.Exception.Response.StatusCode -eq 400){ $InvalidRejected = $true } }
  if(-not $InvalidRejected){ throw "PIE_WORKBENCH_SELFTEST_INVALID_SESSION_ALLOWED" }

  $Started = Invoke-PieWorkbenchJson -Method Post -Uri ($BaseUri + "/api/session/start") -Token $Token -Body @{
    sessionId = $SessionId; targetRepo = $RepoRoot; goal = "Verify workbench API"; backend = "mock"; model = "workbench-mock"
  }
  if(-not [bool]$Started.ok -or [string]$Started.session.status -ne "running"){ throw "PIE_WORKBENCH_SELFTEST_SESSION_START_BAD" }

  $DefaultSessionIndex = Invoke-PieWorkbenchJson -Method Get -Uri ($BaseUri + "/api/sessions") -Token $Token
  if(@($DefaultSessionIndex.sessions | Where-Object { [string]$_.id -eq $SessionId }).Count -ne 0){ throw "PIE_WORKBENCH_SELFTEST_FIXTURE_VISIBLE_BY_DEFAULT" }
  $SessionIndex = Invoke-PieWorkbenchJson -Method Get -Uri ($BaseUri + "/api/sessions?includeFixtures=1") -Token $Token
  $Indexed = @($SessionIndex.sessions | Where-Object { [string]$_.id -eq $SessionId })
  if([string]$SessionIndex.schema -ne "pie.session.index.v1" -or $Indexed.Count -ne 1 -or [string]$Indexed[0].integrity -ne "verified"){
    throw "PIE_WORKBENCH_SELFTEST_SESSION_INDEX_BAD"
  }

  $Asked = Invoke-PieWorkbenchJson -Method Post -Uri ($BaseUri + "/api/ask") -Token $Token -Body @{
    sessionId = $SessionId; text = "Reply briefly with the repository root."; timeoutSeconds = 30
  }
  if(-not [bool]$Asked.ok -or [string]::IsNullOrWhiteSpace([string]$Asked.answer)){ throw "PIE_WORKBENCH_SELFTEST_ASK_BAD" }

  $Haai = Invoke-PieWorkbenchJson -Method Post -Uri ($BaseUri + "/api/haai/capture") -Token $Token -Body @{ sessionId = $SessionId; turnIndex = 0 }
  if(-not [bool]$Haai.ok -or [string]$Haai.packetId -ne ("0" * 64)){ throw "PIE_WORKBENCH_SELFTEST_HAAI_BAD" }

  $History = Invoke-PieWorkbenchJson -Method Get -Uri ($BaseUri + "/api/session/history?sessionId=" + $SessionId) -Token $Token
  if([string]$History.schema -ne "pie.conversation.history.v1" -or [int]$History.total_turns -ne 1){ throw "PIE_WORKBENCH_SELFTEST_HISTORY_BAD" }
  if([string]$History.turns[0].message -notmatch "repository root" -or [string]$History.project_repo -ine $RepoRoot){ throw "PIE_WORKBENCH_SELFTEST_HISTORY_BINDING_BAD" }

  $Stopped = Invoke-PieWorkbenchJson -Method Post -Uri ($BaseUri + "/api/session/stop") -Token $Token -Body @{ sessionId = $SessionId }
  if(-not [bool]$Stopped.ok){ throw "PIE_WORKBENCH_SELFTEST_SESSION_STOP_BAD" }

  $StoppedState = Invoke-PieWorkbenchJson -Method Get -Uri ($BaseUri + "/api/state?sessionId=" + $SessionId) -Token $Token
  if([string]$StoppedState.session.status -ne "stopped" -or [int]$StoppedState.session.turns -ne 1){ throw "PIE_WORKBENCH_SELFTEST_STOPPED_SESSION_HIDDEN" }

  $Backup = Invoke-PieWorkbenchJson -Method Post -Uri ($BaseUri + "/api/session/backup") -Token $Token -Body @{ sessionId = $SessionId; passphrase = $BackupPassphrase }
  if(-not [bool]$Backup.ok -or [string]$Backup.backupId -notmatch '^[0-9a-f]{64}$' -or -not (Test-Path -LiteralPath ([string]$Backup.archive) -PathType Leaf)){ throw "PIE_WORKBENCH_SELFTEST_BACKUP_BAD" }
  $BackupAgain = Invoke-PieWorkbenchJson -Method Post -Uri ($BaseUri + "/api/session/backup") -Token $Token -Body @{ sessionId = $SessionId; passphrase = $BackupPassphrase }
  if([string]$BackupAgain.backupId -ne [string]$Backup.backupId -or [string]$BackupAgain.archive -ne [string]$Backup.archive){ throw "PIE_WORKBENCH_SELFTEST_BACKUP_NOT_IDEMPOTENT" }
  Remove-Item -LiteralPath ([string]$Backup.archive) -Force

  $Resumed = Invoke-PieWorkbenchJson -Method Post -Uri ($BaseUri + "/api/session/start") -Token $Token -Body @{
    sessionId = $SessionId; targetRepo = $RepoRoot; goal = "Verify workbench API"; backend = "mock"; model = "workbench-mock"
  }
  if([string]$Resumed.session.status -ne "running" -or [int]$Resumed.session.turns -ne 1){ throw "PIE_WORKBENCH_SELFTEST_RESUME_HISTORY_LOST" }

  $RebindRejected = $false
  try {
    Invoke-PieWorkbenchJson -Method Post -Uri ($BaseUri + "/api/session/start") -Token $Token -Body @{
      sessionId = $SessionId; targetRepo = $TestRoot; goal = "Verify workbench API"; backend = "mock"; model = "workbench-mock"
    } | Out-Null
  } catch { if([int]$_.Exception.Response.StatusCode -ge 400){ $RebindRejected = $true } }
  if(-not $RebindRejected){ throw "PIE_WORKBENCH_SELFTEST_SESSION_REBIND_ALLOWED" }

  [void](Invoke-PieWorkbenchJson -Method Post -Uri ($BaseUri + "/api/session/stop") -Token $Token -Body @{ sessionId = $SessionId })
  [System.IO.File]::AppendAllText((Join-Path $SessionRoot "conversation.ndjson"),"{not-json}`n",(New-Object System.Text.UTF8Encoding($false)))
  $CorruptStateRejected = $false
  try { Invoke-PieWorkbenchJson -Method Get -Uri ($BaseUri + "/api/state?sessionId=" + $SessionId) -Token $Token | Out-Null }
  catch { if([int]$_.Exception.Response.StatusCode -ge 400){ $CorruptStateRejected = $true } }
  if(-not $CorruptStateRejected){ throw "PIE_WORKBENCH_SELFTEST_CORRUPT_SESSION_HIDDEN" }

  $CorruptIndex = Invoke-PieWorkbenchJson -Method Get -Uri ($BaseUri + "/api/sessions?includeFixtures=1") -Token $Token
  $CorruptItem = @($CorruptIndex.sessions | Where-Object { [string]$_.id -eq $SessionId })
  if($CorruptItem.Count -ne 1 -or [string]$CorruptItem[0].integrity -ne "corrupt" -or [string]::IsNullOrWhiteSpace([string]$CorruptItem[0].error)){
    throw "PIE_WORKBENCH_SELFTEST_CORRUPT_SESSION_NOT_INDEXED"
  }

  Write-Host "PIE_WORKBENCH_SELFTEST_OK" -ForegroundColor Green
}
finally {
  if($null -ne $Process -and -not $Process.HasExited){ Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue }
}
