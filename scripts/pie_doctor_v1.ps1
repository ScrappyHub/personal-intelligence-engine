param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$false)][string]$HaaiRepo = "C:\dev\haai"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $RepoRoot "scripts\_lib_pie_agent_session_v1.ps1")
$Enc = New-Object System.Text.UTF8Encoding($false)
$Components = New-Object System.Collections.Generic.List[object]

function Add-Component {
  param([string]$Id,[string]$Status,[bool]$Required,[string]$Summary,[hashtable]$Details=@{})
  [void]$Components.Add([ordered]@{id=$Id;status=$Status;required=$Required;summary=$Summary;details=$Details})
}

function Read-JsonFile {
  param([string]$Path)
  return (PIE_ReadUtf8Text -Path $Path | ConvertFrom-Json)
}

$RequiredScripts = @(
  "pie_agent_start_v1.ps1","pie_agent_send_v1.ps1","pie_agent_stop_v1.ps1","pie_agent_status_v1.ps1",
  "pie_agent_history_v1.ps1","pie_agent_list_v1.ps1","pie_chat_v1.ps1","pie_ask_v1.ps1",
  "pie_memory_accept_v1.ps1","pie_memory_resolve_v1.ps1","pie_models_v1.ps1","pie_workbench_v1.ps1"
  ,"pie_session_backup_v1.ps1"
)
$MissingScripts = @($RequiredScripts | Where-Object { -not (Test-Path -LiteralPath (Join-Path $RepoRoot ("scripts\" + $_)) -PathType Leaf) })
Add-Component -Id "cli" -Status $(if($MissingScripts.Count){"failed"}else{"ready"}) -Required $true -Summary $(if($MissingScripts.Count){"Required command scripts are missing."}else{"Core command surface is present."}) -Details @{required_scripts=$RequiredScripts.Count;missing=$MissingScripts}

try {
  $Policy = Read-JsonFile -Path (Join-Path $RepoRoot "memory\policy.json")
  $Registry = Read-JsonFile -Path (Join-Path $RepoRoot "memory\PIE_MEMORY_REGISTRY.v1.json")
  $MemoryReady = [string]$Policy.schema -eq "pie.memory.policy.v1" -and [string]$Registry.schema -eq "pie.memory.registry.v1"
  Add-Component "memory" $(if($MemoryReady){"ready"}else{"failed"}) $true $(if($MemoryReady){"Policy and registry are readable and versioned."}else{"Memory policy or registry schema is invalid."}) @{mode=[string]$Policy.mode}
} catch { Add-Component "memory" "failed" $true "Memory policy or registry could not be read." @{error=$_.Exception.Message} }

try {
  $ModelRegistry = Read-JsonFile -Path (Join-Path $RepoRoot "models\PIE_MODEL_REGISTRY.v1.json")
  $Catalog = @($ModelRegistry.catalog)
  $Names = @($Catalog | ForEach-Object { [string]$_.name })
  $Unique = @($Names | Sort-Object -Unique)
  $ModelsReady = [string]$ModelRegistry.schema -eq "pie.model.registry.v1" -and $Catalog.Count -gt 0 -and $Names.Count -eq $Unique.Count
  Add-Component "models" $(if($ModelsReady){"ready"}else{"failed"}) $true $(if($ModelsReady){"Verified local model catalog is available."}else{"Model catalog is empty, duplicated, or invalid."}) @{catalog_count=$Catalog.Count}
} catch { Add-Component "models" "failed" $true "Model catalog could not be read." @{error=$_.Exception.Message} }

$Ollama = Get-Command ollama -ErrorAction SilentlyContinue
if($null -eq $Ollama -and -not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)){
  $Candidate = Join-Path $env:LOCALAPPDATA "Programs\Ollama\ollama.exe"
  if(Test-Path -LiteralPath $Candidate -PathType Leaf){ $Ollama = Get-Item -LiteralPath $Candidate }
}
$RuntimeRunning = $false
if($null -ne $Ollama){ try { $null = Invoke-RestMethod -Method Get -Uri "http://127.0.0.1:11434/api/tags" -TimeoutSec 2; $RuntimeRunning = $true } catch {} }
Add-Component "runtime" $(if($RuntimeRunning){"ready"}elseif($null -ne $Ollama){"attention"}else{"unavailable"}) $false $(if($RuntimeRunning){"Ollama is installed and responding locally."}elseif($null -ne $Ollama){"Ollama is installed but not responding."}else{"Ollama is not installed; mock verification remains available."}) @{installed=($null -ne $Ollama);running=$RuntimeRunning}

$SessionCounts = @{verified=0;legacy=0;corrupt=0;busy=0;total=0;fixture_verified=0;fixture_legacy=0;fixture_corrupt=0;fixture_busy=0;fixture_total=0}
$RunsRoot = Join-Path $RepoRoot "runs"
if(Test-Path -LiteralPath $RunsRoot -PathType Container){
  foreach($Directory in @(Get-ChildItem -LiteralPath $RunsRoot -Directory)){
    if(-not (Test-Path -LiteralPath (Join-Path $Directory.FullName "session_manifest.json") -PathType Leaf) -and -not (Test-Path -LiteralPath (Join-Path $Directory.FullName "state\session.state.json") -PathType Leaf)){ continue }
    $TestOnly = $Directory.Name -match '(^|_)(selftest|smoke)(_|$)' -or $Directory.Name -match '^(stress_agent_|external_stress_|external_demo_|runtime_green($|_)|pie_drift_)'
    if($TestOnly){ $SessionCounts.fixture_total++ } else { $SessionCounts.total++ }
    try {
      $Session = PIE_GetAgentSession -RepoRoot $RepoRoot -SessionId $Directory.Name
      if([string]$Session.integrity -eq "verified"){
        if($TestOnly){ $SessionCounts.fixture_verified++ } else { $SessionCounts.verified++ }
      } else {
        if($TestOnly){ $SessionCounts.fixture_legacy++ } else { $SessionCounts.legacy++ }
      }
    } catch {
      if($_.Exception.Message -like "PIE_AGENT_SESSION_BUSY*"){
        if($TestOnly){ $SessionCounts.fixture_busy++ } else { $SessionCounts.busy++ }
      } else {
        if($TestOnly){ $SessionCounts.fixture_corrupt++ } else { $SessionCounts.corrupt++ }
      }
    }
  }
}
$ConversationAttention = $SessionCounts.corrupt -gt 0 -or $SessionCounts.legacy -gt 0 -or $SessionCounts.busy -gt 0
Add-Component "conversations" $(if($ConversationAttention){"attention"}else{"ready"}) $true $(if($ConversationAttention){"Verified conversations are isolated; legacy, busy, or blocked development sessions need review."}else{"Conversation bindings and histories are readable."}) $SessionCounts

$WorkbenchFiles = @("workbench\server.js","workbench\public\index.html","workbench\public\app.js","workbench\public\styles.css","workbench\contracts\PIE_WORKBENCH_HTTP.v1.json")
$WorkbenchMissing = @($WorkbenchFiles | Where-Object { -not (Test-Path -LiteralPath (Join-Path $RepoRoot $_) -PathType Leaf) })
try { if(-not $WorkbenchMissing.Count){ $null = Read-JsonFile -Path (Join-Path $RepoRoot "workbench\contracts\PIE_WORKBENCH_HTTP.v1.json") } }
catch { $WorkbenchMissing += "invalid HTTP contract" }
Add-Component "workbench" $(if($WorkbenchMissing.Count){"failed"}else{"ready"}) $true $(if($WorkbenchMissing.Count){"Workbench files or contract are incomplete."}else{"Local workbench assets and HTTP contract are present."}) @{missing=$WorkbenchMissing}

$BackupContract = Join-Path $RepoRoot "workbench\contracts\PIE_SESSION_BACKUP.v1.json"
try {
  $BackupDefinition = Read-JsonFile -Path $BackupContract
  $BackupReady = [string]$BackupDefinition.schema -eq "pie.session.backup.contract.v1" -and [string]$BackupDefinition.encryption.cipher -eq "aes-256-gcm" -and [string]$BackupDefinition.encryption.kdf -eq "scrypt" -and (Test-Path -LiteralPath (Join-Path $RepoRoot "scripts\pie_session_backup_v1.ps1") -PathType Leaf) -and (Test-Path -LiteralPath (Join-Path $RepoRoot "scripts\pie_backup_crypto_v1.js") -PathType Leaf)
  Add-Component "backups" $(if($BackupReady){"ready"}else{"failed"}) $true $(if($BackupReady){"Authenticated encrypted session backup and collision-safe restore are available."}else{"Encrypted session backup contract or command is invalid."}) @{contract=[string]$BackupDefinition.schema;cipher=[string]$BackupDefinition.encryption.cipher;kdf=[string]$BackupDefinition.encryption.kdf}
} catch { Add-Component "backups" "failed" $true "Session backup contract could not be read." @{error=$_.Exception.Message} }

$DesktopFiles = @("desktop\package.json","desktop\main.js","desktop\preload.js","desktop\runtime-workspace.js","desktop\forge.config.js")
$DesktopMissing = @($DesktopFiles | Where-Object { -not (Test-Path -LiteralPath (Join-Path $RepoRoot $_) -PathType Leaf) })
$ElectronInstalled = Test-Path -LiteralPath (Join-Path $RepoRoot "desktop\node_modules\electron") -PathType Container
Add-Component "desktop" $(if($DesktopMissing.Count){"failed"}else{"attention"}) $true $(if($DesktopMissing.Count){"Desktop application source is incomplete."}elseif($ElectronInstalled){"Desktop development runtime is present; release gates remain open."}else{"Desktop source is present; dependencies and release verification remain outstanding."}) @{missing=$DesktopMissing;dependencies_installed=$ElectronInstalled;release_verified=$false}

$HostedContract = Join-Path $RepoRoot "workbench\contracts\PIE_HOSTED_GATEWAY.v1.json"
try {
  $Hosted = Read-JsonFile -Path $HostedContract
  Add-Component "hosted" "attention" $false "The hosted gateway is specified, but no isolated production gateway is implemented in this repository." @{schema=[string]$Hosted.schema;contract_only=$true}
} catch { Add-Component "hosted" "unavailable" $false "Hosted gateway contract is missing or invalid." @{contract_only=$true;error=$_.Exception.Message} }

$IntegrationTokens = @("SUPABASE_ACCESS_TOKEN","FIGMA_ACCESS_TOKEN","VERCEL_TOKEN","CLOUDFLARE_API_TOKEN")
$ConfiguredIntegrations = @($IntegrationTokens | Where-Object { -not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($_,"Process")) }).Count
Add-Component "integrations" $(if($ConfiguredIntegrations -gt 0){"ready"}else{"unavailable"}) $false $(if($ConfiguredIntegrations -gt 0){"Optional service credentials are configured locally."}else{"Optional service credentials are not configured."}) @{configured=$ConfiguredIntegrations}

$HaaiCli = Join-Path $HaaiRepo "core\python\haai_core\cli.py"
$HaaiContract = Join-Path $RepoRoot "workbench\contracts\PIE_HAAI_ADAPTER.v1.json"
$HaaiReady = (Test-Path -LiteralPath $HaaiCli -PathType Leaf) -and (Test-Path -LiteralPath $HaaiContract -PathType Leaf)
Add-Component "haai" $(if($HaaiReady){"ready"}else{"unavailable"}) $false $(if($HaaiReady){"Explicit local HAAI evidence export is available."}else{"HAAI is optional and was not found at the configured path."}) @{repository=$HaaiRepo;adapter_contract=(Test-Path -LiteralPath $HaaiContract -PathType Leaf)}

$RequiredFailures = @($Components | Where-Object { $_.required -and $_.status -eq "failed" })
$Attention = @($Components | Where-Object { $_.status -in @("attention","unavailable") })
$Overall = if($RequiredFailures.Count){"failed"}elseif($Attention.Count){"attention"}else{"ready"}
$Report = [ordered]@{schema="pie.doctor.report.v1";generated_utc=[DateTime]::UtcNow.ToString("o");repo_root=$RepoRoot;overall=$Overall;release_ready=$false;components=@($Components.ToArray())}
$ReportRoot = Join-Path $RepoRoot "runs\doctor"
New-Item -ItemType Directory -Force -Path $ReportRoot | Out-Null
$Stamp = [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss_fff")
$ReportPath = Join-Path $ReportRoot ("doctor_report_" + $Stamp + ".json")
$Json = $Report | ConvertTo-Json -Depth 12
[IO.File]::WriteAllText($ReportPath,$Json + "`n",$Enc)
[IO.File]::WriteAllText((Join-Path $ReportRoot "latest.json"),$Json + "`n",$Enc)

Write-Host "PIE HEALTH AUDIT" -ForegroundColor Cyan
foreach($Component in $Components){ Write-Host (("{0,-14} {1,-11} {2}" -f $Component.id,$Component.status,$Component.summary)) }
Write-Host ("overall: " + $Overall)
Write-Host "release ready: no"
Write-Host ("report: " + $ReportPath)
if($RequiredFailures.Count){ throw ("PIE_DOCTOR_REQUIRED_COMPONENT_FAILED: " + (($RequiredFailures | ForEach-Object { $_.id }) -join ",")) }
Write-Host "PIE_DOCTOR_OK" -ForegroundColor Green
