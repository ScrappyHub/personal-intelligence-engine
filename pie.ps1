param(
  [Parameter(Position=0)][string]$Command = "help",
  [Parameter(Position=1)][string]$Subcommand = "",

  [string]$RepoRoot = ".",
  [string]$SessionId = "pie_chat",
  [string]$Model = "",
  [string]$Backend = "ollama",
  [string]$Profile = "core",
  [string]$Mode = "",
  [string]$Path = "",
  [string]$Hash = "",
  [string]$MemoryId = "",
  [string]$Capability = "",
  [string]$Chain = "repo.health.basic",
  [string]$WorkingDirectory = "",
  [string]$Text = "",
  [string]$Lane = "",
  [string]$Project = "",
  [string]$ProjectRepo = "",
  [string]$TargetRepo = "",
  [string]$Provider = "all",
  [string]$HaaiRepo = "C:\dev\haai",
  [string]$Role = "related",
  [string]$Prompt = "",
  [string]$Goal = "",
  [string]$Language = "",
  [string]$Version = "",
  [string]$OutputDirectory = "",
  [switch]$NewSettings,
  [switch]$PullMissing,
  [switch]$SetDefault,
  [switch]$Yes,
  [switch]$LastResults,
  [switch]$Scorecard,
  [int]$Iterations = 2,
  [int]$Limit = 25,
  [int]$TimeoutSeconds = 180,
  [int]$Retries = 1,
  [int]$ProgressIntervalSeconds = 5,
  [int]$Port = 4317,
  [int]$TurnIndex = 0,
  [switch]$AllowMock,
  [switch]$PassphraseStdin
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
# PIE green command shortcuts.
# Must run before the legacy command dispatcher/default unknown-command throw.
if($Command -eq "green"){
  $ModeArg = ""

  # Depending on how the shell function invokes pie.ps1, $args may still
  # include the command token itself. Accept both:
  #   pie green governance        -> $Command=green, $args=green,governance
  #   .\pie.ps1 green governance  -> $Command=green, $args=governance
  $RemainingArgs = @()

  if(-not [string]::IsNullOrWhiteSpace($Subcommand)){
    $RemainingArgs = @($Subcommand)
  }
  else {
    $ArgsVar = Get-Variable -Name args -Scope Local -ErrorAction SilentlyContinue
    if($null -ne $ArgsVar){
      $RemainingArgs = @($ArgsVar.Value)
    }
  }

  if($RemainingArgs.Count -ge 1 -and ([string]$RemainingArgs[0]) -eq $Command){
    if($RemainingArgs.Count -ge 2){
      $ModeArg = [string]$RemainingArgs[1]
    }
  }
  elseif($RemainingArgs.Count -ge 1){
    $ModeArg = [string]$RemainingArgs[0]
  }

  if([string]::IsNullOrWhiteSpace($ModeArg)){
    throw "PIE_GREEN_USAGE: pie green status | pie green list | pie green evidence | pie green manifest | pie green audit | pie green governance | pie green governance-full | pie green full"
  }

        if($ModeArg -eq "audit"){
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
      -File (Join-Path $RepoRoot "scripts\pie_green_audit_v1.ps1") `
      -RepoRoot $RepoRoot
    exit $LASTEXITCODE
  }
if($ModeArg -eq "manifest"){
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
      -File (Join-Path $RepoRoot "scripts\pie_green_manifest_validate_v1.ps1") `
      -RepoRoot $RepoRoot
    exit $LASTEXITCODE
  }
    if($ModeArg -eq "evidence"){
    function Get-LatestGreenFreeze {
      param(
        [Parameter(Mandatory=$true)][string]$Prefix
      )

      $FreezeRoot = Join-Path $RepoRoot "proofs\freeze"

      if(-not (Test-Path -LiteralPath $FreezeRoot -PathType Container)){
        return $null
      }

      return Get-ChildItem -LiteralPath $FreezeRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like ($Prefix + "*") } |
        Sort-Object Name -Descending |
        Select-Object -First 1
    }

    function Write-FreezeEvidence {
      param(
        [Parameter(Mandatory=$true)][string]$Label,
        [AllowNull()]$FreezeDir
      )

      Write-Host ("[" + $Label + "]") -ForegroundColor Cyan

      if($null -eq $FreezeDir){
        Write-Host "freeze: none"
        return
      }

      Write-Host ("freeze: " + $FreezeDir.FullName)

      $SummaryPath = Join-Path $FreezeDir.FullName "FREEZE_SUMMARY.json"
      if(Test-Path -LiteralPath $SummaryPath -PathType Leaf){
        Write-Host ("summary: " + $SummaryPath)

        try {
          $S = Get-Content -LiteralPath $SummaryPath -Raw | ConvertFrom-Json

          foreach($Field in @("schema","mode","status","selftest_count","freeze_utc","utc","created_utc")){
            $Prop = $S.PSObject.Properties[$Field]
            if($null -ne $Prop){
              Write-Host ($Field + ": " + [string]$Prop.Value)
            }
          }
        }
        catch {
          Write-Host ("summary_parse: failed :: " + $_.Exception.Message) -ForegroundColor Yellow
        }
      }
      else {
        Write-Host "summary: missing" -ForegroundColor Yellow
      }

      $ShaPath = Join-Path $FreezeDir.FullName "sha256sums.txt"
      if(Test-Path -LiteralPath $ShaPath -PathType Leaf){
        $Hash = Get-FileHash -Algorithm SHA256 -LiteralPath $ShaPath
        Write-Host ("sha256sums: " + $ShaPath)
        Write-Host ("sha256sums_sha256: " + $Hash.Hash.ToLowerInvariant())
      }
      else {
        Write-Host "sha256sums: missing" -ForegroundColor Yellow
      }

      $ReceiptsPath = Join-Path $FreezeDir.FullName "child_receipts.ndjson"
      if(Test-Path -LiteralPath $ReceiptsPath -PathType Leaf){
        $ReceiptCount = @(Get-Content -LiteralPath $ReceiptsPath).Count
        Write-Host ("child_receipts: " + $ReceiptsPath)
        Write-Host ("child_receipt_count: " + [string]$ReceiptCount)
      }
      else {
        Write-Host "child_receipts: missing" -ForegroundColor Yellow
      }
    }

    Write-Host "PIE_GREEN_EVIDENCE" -ForegroundColor Cyan

    $LatestFull = Get-LatestGreenFreeze -Prefix "pie_tier0_green_"
    $LatestGovernance = Get-LatestGreenFreeze -Prefix "pie_governance_green_"

    Write-FreezeEvidence -Label "latest_full_green" -FreezeDir $LatestFull
    Write-FreezeEvidence -Label "latest_governance_green" -FreezeDir $LatestGovernance

    exit 0
  }
if($ModeArg -eq "list"){
    $ManifestPath = Join-Path $RepoRoot "docs\PIE_GREEN_COMMANDS.manifest.json"

    if(-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)){
      throw "PIE_GREEN_LIST_MANIFEST_MISSING"
    }

    $Manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json

    if($Manifest.schema -ne "pie.green.commands.manifest.v1"){
      throw "PIE_GREEN_LIST_MANIFEST_SCHEMA_BAD"
    }

    Write-Host "PIE_GREEN_LIST" -ForegroundColor Cyan
    Write-Host ("manifest: " + $ManifestPath)
    Write-Host ("commands: " + [string]@($Manifest.commands).Count)

    foreach($C in @($Manifest.commands)){
      Write-Host ("- " + [string]$C.command + " :: " + [string]$C.purpose)
    }

    exit 0
  }
if($ModeArg -eq "status"){
    $Branch = (& git -C $RepoRoot rev-parse --abbrev-ref HEAD 2>$null)
    $Commit = (& git -C $RepoRoot rev-parse --short HEAD 2>$null)
    $StatusLines = @(& git -C $RepoRoot status --short)

    $LatestFull = Get-ChildItem (Join-Path $RepoRoot "proofs\freeze") -Directory -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -like "pie_tier0_green_*" } |
      Sort-Object Name -Descending |
      Select-Object -First 1

    $LatestGovernance = Get-ChildItem (Join-Path $RepoRoot "proofs\freeze") -Directory -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -like "pie_governance_green_*" } |
      Sort-Object Name -Descending |
      Select-Object -First 1

    Write-Host "PIE_GREEN_STATUS" -ForegroundColor Cyan
    Write-Host ("branch: " + [string]$Branch)
    Write-Host ("commit: " + [string]$Commit)

    if(@($StatusLines).Count -eq 0){
      Write-Host "working_tree: clean" -ForegroundColor Green
    }
    else {
      Write-Host "working_tree: dirty" -ForegroundColor Yellow
      foreach($Line in $StatusLines){
        Write-Host ("  " + $Line)
      }
    }

    if($null -ne $LatestFull){
      Write-Host ("latest_full_green: " + $LatestFull.FullName)
      $FullSummary = Join-Path $LatestFull.FullName "FREEZE_SUMMARY.json"
      if(Test-Path -LiteralPath $FullSummary -PathType Leaf){
        Write-Host ("latest_full_green_summary: " + $FullSummary)
      }
    }
    else {
      Write-Host "latest_full_green: none"
    }

    if($null -ne $LatestGovernance){
      Write-Host ("latest_governance_green: " + $LatestGovernance.FullName)
      $GovSummary = Join-Path $LatestGovernance.FullName "FREEZE_SUMMARY.json"
      if(Test-Path -LiteralPath $GovSummary -PathType Leaf){
        $S = Get-Content -LiteralPath $GovSummary -Raw | ConvertFrom-Json
        Write-Host ("latest_governance_mode: " + [string]$S.mode)
        Write-Host ("latest_governance_status: " + [string]$S.status)
        Write-Host ("latest_governance_selftest_count: " + [string]$S.selftest_count)
      }
    }
    else {
      Write-Host "latest_governance_green: none"
    }

    exit 0
  }
if($ModeArg -eq "governance"){
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
      -File (Join-Path $RepoRoot "scripts\GOVERNANCE_GREEN_RUNNER_PIE_v1.ps1") `
      -RepoRoot $RepoRoot `
      -Mode "latest_governance"
    exit $LASTEXITCODE
  }

  if($ModeArg -eq "governance-full"){
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
      -File (Join-Path $RepoRoot "scripts\GOVERNANCE_GREEN_RUNNER_PIE_v1.ps1") `
      -RepoRoot $RepoRoot `
      -Mode "trusted_baseline_lifecycle"
    exit $LASTEXITCODE
  }

  if($ModeArg -eq "full"){
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
      -File (Join-Path $RepoRoot "scripts\GOVERNANCE_GREEN_RUNNER_PIE_v1.ps1") `
      -RepoRoot $RepoRoot `
      -Mode "full"
    exit $LASTEXITCODE
  }

  throw ("PIE_GREEN_UNKNOWN_MODE: " + $ModeArg)
}

$Scripts = Join-Path $RepoRoot "scripts"
. (Join-Path $Scripts "_lib_pie_agent_session_v1.ps1")

function Invoke-PieScript {
  param(
    [Parameter(Mandatory=$true)][string]$Script,
    [Parameter(Mandatory=$false)][string[]]$Args = @()
  )

  $ScriptPath = Join-Path $Scripts $Script

  if(-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)){
    throw ("PIE_CLI_SCRIPT_MISSING: " + $ScriptPath)
  }

  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $ScriptPath @Args

  if($LASTEXITCODE -ne 0){
    throw ("PIE_CLI_CHILD_FAIL: " + $Script)
  }
}

function Invoke-PieInteractiveScript {
  param(
    [Parameter(Mandatory=$true)][string]$Script,
    [Parameter(Mandatory=$false)][string[]]$Args = @()
  )

  $ScriptPath = Join-Path $Scripts $Script

  if(-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)){
    throw ("PIE_CLI_SCRIPT_MISSING: " + $ScriptPath)
  }

  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ScriptPath @Args

  if($LASTEXITCODE -ne 0){
    throw ("PIE_CLI_CHILD_FAIL: " + $Script)
  }
}

function Resolve-PieModel {
  if(-not [string]::IsNullOrWhiteSpace($Model)){ return $Model }

  $SelectedPath = Join-Path $RepoRoot "runs\runtime\config.json"
  if(Test-Path -LiteralPath $SelectedPath -PathType Leaf){
    try {
      $Selected = [string]((Get-Content -LiteralPath $SelectedPath -Raw | ConvertFrom-Json).model)
      if(-not [string]::IsNullOrWhiteSpace($Selected)){ return $Selected }
    } catch { throw ("PIE_RUNTIME_CONFIG_INVALID: " + $SelectedPath + " :: " + $_.Exception.Message) }
  }

  return "qwen2.5-coder:7b"
}

function Show-Help {
  Write-Host ""
  Write-Host "PIE - Personal Intelligence Engine" -ForegroundColor Cyan
  Write-Host "Local AI runtime, memory, models, and project workbench CLI."
  Write-Host ""
  Write-Host "Usage:"
  Write-Host "  pie <command> [options]"
  Write-Host ""
  Write-Host "Commands:"
  Write-Host "  help            Show help"
  Write-Host "  version         Show the PIE version"
  Write-Host "  setup           Setup local model/profile requirements"
  Write-Host "  agent           Run a governed local coding-agent session"
  Write-Host "  runtime         Install, start, or inspect the local model host"
  Write-Host "  integrations    Inspect or verify Supabase, Figma, Vercel, and Cloudflare"
  Write-Host "  doctor          Audit CLI, memory, conversations, models, and app surfaces"
  Write-Host "  workbench       Open the local browser workbench"
  Write-Host "  haai            Export a verified conversation turn to a HAAI evidence packet"
  Write-Host "  session         Export, verify, or restore a complete verified session backup"
  Write-Host "  package         Build a verified installable PIE package"
  Write-Host "  models          List, browse, and select local models"
  Write-Host "  pull            Download a model onto this machine"
  Write-Host "  seal-ollama     Seal a pulled Ollama model into the registry (-Model <tag>)"
  Write-Host "  run             Run one governed generation (-Prompt <text> [-Backend stub|ollama|llamacpp|onnx])"
  Write-Host "  chat            Start local chat"
  Write-Host "  ask             Ask PIE once using session memory/attachments"
  Write-Host "  doc             Send a document to PIE"
  Write-Host "  image           Send an image path to PIE"
  Write-Host "  attach          Attach a file/image to a session"
  Write-Host "  vision          Inspect latest attached image with a vision model"
  Write-Host "  vision-correct  Record user correction for latest attached image"
  Write-Host "  generate-image  Generate an image request"
  Write-Host "  memory          Memory commands"
  Write-Host "  policy          Evaluate local PIE policy decision"
  Write-Host "  integrate       Integrate PIE with a target repo"
  Write-Host "  scan            Scan a target repo (-TargetRepo <path>)"
  Write-Host "  scan-last       Show latest repo scan artifact"
  Write-Host "  save            Save conversation by hash"
  Write-Host "  open            Reopen saved conversation by hash"
  Write-Host "  init            Initialize PIE in a repo"
  Write-Host "  verify          Verify PIE repo init"
  Write-Host "  detect          Detect repo/project stack"
  Write-Host "  stress-models   Stress test local models"
  Write-Host "  score           Score latest benchmark run"
  Write-Host "  show            Show latest benchmark/model results"
  Write-Host "  verify-runtime  Verify PIE runtime command surface"
  Write-Host "  verify-engines  Verify engine adapters (parse-gate + persona + Tier-0 + trios)"
  Write-Host "  recover         Complete any interrupted multi-file state transaction"
  Write-Host ""
  Write-Host "Examples:"
  Write-Host "  pie runtime install"
  Write-Host "  pie runtime start"
  Write-Host "  pie workbench"
  Write-Host "  pie package -Version 0.1.0"
  Write-Host "  pie models catalog"
  Write-Host "  pie pull -Model qwen2.5-coder:7b -SetDefault"
  Write-Host "  pie models use -Model qwen2.5-coder:7b"
  Write-Host "  pie agent start -SessionId my_work -TargetRepo . -Goal `"Fix tests`""
  Write-Host "  pie agent inspect -SessionId my_work"
  Write-Host "  pie agent exec -SessionId my_work -Text `"git status`""
  Write-Host "  pie session export -SessionId my_work"
  Write-Host "  pie session verify -Path .\backups\pie-session-my_work-<id>.piebak"
  Write-Host "  pie session restore -Path .\backups\pie-session-my_work-<id>.piebak"
  Write-Host "  pie chat [-SessionId <id>] [-TargetRepo <path>] [-Goal <goal>]"
  Write-Host "  pie chat -NewSettings"
  Write-Host "  pie integrate -TargetRepo C:\dev\nfl -Project nfl -Language `"PowerShell 5.1`""
  Write-Host "  pie ask -SessionId my_chat -Text `"What is my current chat goal?`""
  Write-Host "  pie run -Model pie-onnx-fixture -Prompt `"Say ready`" -Backend stub"
  Write-Host "  pie seal-ollama -Model qwen2.5-coder:1.5b"
  Write-Host "  pie run -Model qwen2.5-coder:1.5b -Prompt `"Say ready`" -Backend ollama"
  Write-Host "  pie verify-engines"
  Write-Host "  pie version"
  Write-Host ""
}

function Show-AgentHelp {
  Write-Host ""
  Write-Host "PIE Agent" -ForegroundColor Cyan
  Write-Host ""
  Write-Host "  pie agent start -SessionId <id> [-TargetRepo .] [-Goal <goal>]"
  Write-Host "  pie agent sessions"
  Write-Host "  pie agent status -SessionId <id>"
  Write-Host "  pie agent history -SessionId <id>"
  Write-Host "  pie agent ask -SessionId <id> -Text <question> [-TimeoutSeconds 180] [-Retries 1]"
  Write-Host "  pie agent plan -SessionId <id> -Goal <goal>"
  Write-Host "  pie agent inspect -SessionId <id> [-Chain repo.health.basic]"
  Write-Host "  pie agent capabilities"
  Write-Host "  pie agent capability -SessionId <id> -Capability repo.status"
  Write-Host "  pie agent exec -SessionId <id> -Text <command> [-Yes]"
  Write-Host "  pie agent stop -SessionId <id>"
  Write-Host ""
}

function Show-MemoryHelp {
  Write-Host ""
  Write-Host "PIE Memory" -ForegroundColor Cyan
  Write-Host ""
  Write-Host "Usage:"
  Write-Host "  pie memory policy"
  Write-Host "  pie memory policy -Mode ask"
  Write-Host "  pie memory policy -Mode auto_accept"
  Write-Host "  pie memory policy -Mode manual_only"
  Write-Host "  pie memory policy -Mode off"
  Write-Host "  pie memory accept -Text `"Remember this`" -Lane active"
  Write-Host "  pie memory accept -Text `"Project rule`" -Lane project -Project pie"
  Write-Host "  pie memory list -Lane coding"
  Write-Host "  pie memory search -Text `"PowerShell preference`""
  Write-Host "  pie memory forget -MemoryId mem_<sha256>"
  Write-Host ""
}

switch($Command.ToLowerInvariant()){

  "help" {
    Show-Help
    return
  }

  "doctor" {
    Invoke-PieScript -Script "pie_doctor_v1.ps1" -Args @("-RepoRoot",$RepoRoot,"-HaaiRepo",$HaaiRepo)
    return
  }

  "runtime" {
    $Action = $Subcommand
    if([string]::IsNullOrWhiteSpace($Action)){ $Action = "status" }
    Invoke-PieInteractiveScript -Script "pie_runtime_v1.ps1" -Args @("-RepoRoot",$RepoRoot,"-Action",$Action)
    return
  }

  "integrations" {
    $Action = $Subcommand
    if([string]::IsNullOrWhiteSpace($Action)){ $Action = "status" }
    $IntegrationScript = Join-Path $Scripts "pie_integrations_v1.ps1"
    if(-not (Test-Path -LiteralPath $IntegrationScript -PathType Leaf)){ throw ("PIE_CLI_SCRIPT_MISSING: " + $IntegrationScript) }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $IntegrationScript `
      -RepoRoot $RepoRoot -Action $Action -Provider $Provider -TimeoutSeconds $TimeoutSeconds
    exit $LASTEXITCODE
  }

  "workbench" {
    $Action = $Subcommand
    if([string]::IsNullOrWhiteSpace($Action)){ $Action = "start" }
    $A = @("-RepoRoot",$RepoRoot,"-Action",$Action,"-Port",[string]$Port)
    if($AllowMock){ $A += "-AllowMock" }
    Invoke-PieInteractiveScript -Script "pie_workbench_v1.ps1" -Args $A
    return
  }

  "package" {
    $A = @("-RepoRoot",$RepoRoot)
    if(-not [string]::IsNullOrWhiteSpace($Version)){ $A += @("-Version",$Version) }
    if(-not [string]::IsNullOrWhiteSpace($OutputDirectory)){ $A += @("-OutputDirectory",$OutputDirectory) }
    Invoke-PieScript -Script "pie_package_v1.ps1" -Args $A
    return
  }

  "haai" {
    $Action = $Subcommand
    if([string]::IsNullOrWhiteSpace($Action)){ $Action = "capture" }
    if($Action -ne "capture"){ throw ("PIE_HAAI_UNKNOWN_COMMAND: " + $Action) }
    Invoke-PieScript -Script "pie_haai_capture_v1.ps1" -Args @("-RepoRoot",$RepoRoot,"-SessionId",$SessionId,"-TurnIndex",[string]$TurnIndex,"-HaaiRepo",$HaaiRepo)
    return
  }

  "session" {
    $Action = $Subcommand.ToLowerInvariant()
    if($Action -notin @("export","verify","restore")){ throw "PIE_SESSION_COMMAND_REQUIRED: export, verify, or restore" }
    $A = @("-RepoRoot",$RepoRoot,"-Action",$Action)
    if($Action -eq "export"){
      if([string]::IsNullOrWhiteSpace($SessionId)){ throw "PIE_SESSION_BACKUP_SESSION_ID_REQUIRED" }
      $A += @("-SessionId",$SessionId)
      if(-not [string]::IsNullOrWhiteSpace($OutputDirectory)){ $A += @("-OutputDirectory",$OutputDirectory) }
    }
    else {
      if([string]::IsNullOrWhiteSpace($Path)){ throw "PIE_SESSION_BACKUP_ARCHIVE_REQUIRED: use -Path <backup.zip>" }
      $A += @("-ArchivePath",$Path)
    }
    if($PassphraseStdin){ $A += "-PassphraseStdin" }
    Invoke-PieInteractiveScript -Script "pie_session_backup_v1.ps1" -Args $A
    return
  }

  "agent" {
    switch($Subcommand.ToLowerInvariant()){
      "" { Show-AgentHelp; return }
      "help" { Show-AgentHelp; return }
      "start" {
        $Model = Resolve-PieModel
        if([string]::IsNullOrWhiteSpace($TargetRepo)){ $TargetRepo = (Get-Location).Path }
        if(-not (Test-Path -LiteralPath $TargetRepo -PathType Container)){
          throw ("PIE_AGENT_TARGET_REPO_NOT_FOUND: " + $TargetRepo + ". Use -TargetRepo . for the current repository or provide an existing directory.")
        }
        $A = @("-RepoRoot",$RepoRoot,"-SessionId",$SessionId,"-Backend",$Backend,"-Model",$Model,"-ProjectRepo",$TargetRepo)
        if(-not [string]::IsNullOrWhiteSpace($Goal)){ $A += @("-Goal",$Goal) }
        Invoke-PieScript -Script "pie_agent_start_v1.ps1" -Args $A
        return
      }
      "status" {
        [void](PIE_GetAgentSession -RepoRoot $RepoRoot -SessionId $SessionId)
        Invoke-PieScript -Script "pie_agent_status_v1.ps1" -Args @("-RepoRoot",$RepoRoot,"-SessionId",$SessionId)
        return
      }
      "history" {
        [void](PIE_GetAgentSession -RepoRoot $RepoRoot -SessionId $SessionId)
        Invoke-PieScript -Script "pie_agent_history_v1.ps1" -Args @("-RepoRoot",$RepoRoot,"-SessionId",$SessionId)
        return
      }
      "sessions" {
        Invoke-PieScript -Script "pie_agent_list_v1.ps1" -Args @("-RepoRoot",$RepoRoot)
        return
      }
      "ask" {
        if([string]::IsNullOrWhiteSpace($Text)){ throw "PIE_AGENT_ASK_TEXT_REQUIRED" }
        if($TimeoutSeconds -lt 1){ throw "PIE_AGENT_TIMEOUT_SECONDS_INVALID" }
        if($Retries -lt 0 -or $Retries -gt 2){ throw "PIE_AGENT_RETRIES_INVALID: expected 0..2" }
        if($ProgressIntervalSeconds -lt 1){ throw "PIE_AGENT_PROGRESS_INTERVAL_INVALID" }
        [void](PIE_GetAgentSession -RepoRoot $RepoRoot -SessionId $SessionId -RequireRunning -RequireIntegrity)
        Invoke-PieScript -Script "pie_ask_v1.ps1" -Args @(
          "-RepoRoot",$RepoRoot,
          "-SessionId",$SessionId,
          "-Message",$Text,
          "-TimeoutSeconds",$TimeoutSeconds,
          "-MaxAttempts",($Retries + 1),
          "-ProgressIntervalSeconds",$ProgressIntervalSeconds
        )
        return
      }
      "plan" {
        if([string]::IsNullOrWhiteSpace($Goal)){ throw "PIE_AGENT_PLAN_GOAL_REQUIRED" }
        [void](PIE_GetAgentSession -RepoRoot $RepoRoot -SessionId $SessionId -RequireRunning -RequireIntegrity)
        Invoke-PieScript -Script "pie_plan_v1.ps1" -Args @("-RepoRoot",$RepoRoot,"-SessionId",$SessionId,"-Goal",$Goal)
        return
      }
      "inspect" {
        [void](PIE_GetAgentSession -RepoRoot $RepoRoot -SessionId $SessionId -RequireRunning -RequireIntegrity)
        Invoke-PieScript -Script "pie_orchestrate_v1.ps1" -Args @("-RepoRoot",$RepoRoot,"-SessionId",$SessionId,"-ChainId",$Chain,"-AutoConfirmAllowed")
        return
      }
      "capabilities" {
        Invoke-PieScript -Script "pie_capability_list_v1.ps1" -Args @("-RepoRoot",$RepoRoot)
        return
      }
      "capability" {
        if([string]::IsNullOrWhiteSpace($Capability)){ throw "PIE_AGENT_CAPABILITY_REQUIRED" }
        [void](PIE_GetAgentSession -RepoRoot $RepoRoot -SessionId $SessionId -RequireRunning -RequireIntegrity)
        $A = @("-RepoRoot",$RepoRoot,"-SessionId",$SessionId,"-CapabilityId",$Capability,"-AutoConfirmAllowed")
        if($Yes){ $A += "-Confirm" }
        Invoke-PieScript -Script "pie_capability_v1.ps1" -Args $A
        return
      }
      "exec" {
        if([string]::IsNullOrWhiteSpace($Text)){ throw "PIE_AGENT_EXEC_COMMAND_REQUIRED" }
        [void](PIE_GetAgentSession -RepoRoot $RepoRoot -SessionId $SessionId -RequireRunning -RequireIntegrity)
        $A = @("-RepoRoot",$RepoRoot,"-SessionId",$SessionId,"-Command",$Text,"-AutoConfirmAllowed")
        if(-not [string]::IsNullOrWhiteSpace($WorkingDirectory)){ $A += @("-WorkingDirectory",$WorkingDirectory) }
        if($Yes){ $A += "-Confirm" }
        Invoke-PieScript -Script "pie_exec_with_snapshot_v1.ps1" -Args $A
        return
      }
      "stop" {
        [void](PIE_GetAgentSession -RepoRoot $RepoRoot -SessionId $SessionId)
        Invoke-PieScript -Script "pie_agent_stop_v1.ps1" -Args @("-RepoRoot",$RepoRoot,"-SessionId",$SessionId)
        return
      }
      default { throw ("PIE_AGENT_UNKNOWN_COMMAND: " + $Subcommand) }
    }
  }

  "setup" {
    Invoke-PieScript `
      -Script "pie_setup_v1.ps1" `
      -Args @(
        "-RepoRoot",$RepoRoot,
        "-Profile",$Profile
      )
    return
  }

  "models" {
    $Action = $Subcommand
    if([string]::IsNullOrWhiteSpace($Action)){ $Action = "list" }
    $A = @("-RepoRoot",$RepoRoot,"-Action",$Action)
    if(-not [string]::IsNullOrWhiteSpace($Model)){ $A += @("-Model",$Model) }
    Invoke-PieScript -Script "pie_models_v1.ps1" -Args $A
    return
  }

  "pull" {
    if([string]::IsNullOrWhiteSpace($Model)){
      throw "PIE_CLI_MODEL_REQUIRED"
    }

    $A = @("-RepoRoot",$RepoRoot,"-Action","pull","-Model",$Model)
    if($SetDefault){ $A += "-SetDefault" }
    Invoke-PieInteractiveScript -Script "pie_models_v1.ps1" -Args $A

    return
  }

  "chat" {
    $Model = Resolve-PieModel
    $A = @(
      "-RepoRoot",$RepoRoot,
      "-SessionId",$SessionId,
      "-Model",$Model,
      "-Backend",$Backend
    )

    $ChatProjectRepo = $(if(-not [string]::IsNullOrWhiteSpace($TargetRepo)){ $TargetRepo } else { $ProjectRepo })
    if(-not [string]::IsNullOrWhiteSpace($ChatProjectRepo)){ $A += @("-ProjectRepo",$ChatProjectRepo) }

    if(-not [string]::IsNullOrWhiteSpace($Goal)){
      $A += @("-Goal",$Goal)
    }

    if($NewSettings){
      $A += "-NewSettings"
    }

    Invoke-PieInteractiveScript `
      -Script "pie_chat_v1.ps1" `
      -Args $A

    return
  }

  "ask" {
    if([string]::IsNullOrWhiteSpace($Text)){
      if(-not [string]::IsNullOrWhiteSpace($Subcommand)){
        $Text = $Subcommand
      } else {
        throw "PIE_ASK_TEXT_REQUIRED"
      }
    }

    Invoke-PieScript `
      -Script "pie_ask_v1.ps1" `
      -Args @(
        "-RepoRoot",$RepoRoot,
        "-SessionId",$SessionId,
        "-Message",$Text,
        "-TimeoutSeconds",$TimeoutSeconds,
        "-MaxAttempts",($Retries + 1),
        "-ProgressIntervalSeconds",$ProgressIntervalSeconds
      )

    return
  }

  "doc" {
    if([string]::IsNullOrWhiteSpace($Path)){
      throw "PIE_DOC_PATH_REQUIRED"
    }

    $Msg = "Summarize this document and identify actionable next steps:`n`n" + (Get-Content -LiteralPath $Path -Raw)

    Invoke-PieScript `
      -Script "pie_agent_send_v1.ps1" `
      -Args @(
        "-RepoRoot",$RepoRoot,
        "-SessionId",$SessionId,
        "-Message",$Msg
      )

    return
  }

  "image" {
    if([string]::IsNullOrWhiteSpace($Path)){
      throw "PIE_IMAGE_PATH_REQUIRED"
    }

    $Msg = "Image path attached for local review: " + $Path + "`nIf the backend cannot inspect pixels, say so clearly."

    Invoke-PieScript `
      -Script "pie_agent_send_v1.ps1" `
      -Args @(
        "-RepoRoot",$RepoRoot,
        "-SessionId",$SessionId,
        "-Message",$Msg
      )

    return
  }

  "attach" {
    if([string]::IsNullOrWhiteSpace($Path)){
      throw "PIE_ATTACH_PATH_REQUIRED"
    }

    Invoke-PieScript `
      -Script "pie_attach_v1.ps1" `
      -Args @(
        "-RepoRoot",$RepoRoot,
        "-SessionId",$SessionId,
        "-Path",$Path
      )

    return
  }

  "vision" {
    $Model = Resolve-PieModel
    if([string]::IsNullOrWhiteSpace($Prompt)){
      $Prompt = "Describe the attached image clearly and concisely."
    }

    Invoke-PieScript `
      -Script "pie_vision_ollama_v1.ps1" `
      -Args @(
        "-RepoRoot",$RepoRoot,
        "-SessionId",$SessionId,
        "-Model",$Model,
        "-Prompt",$Prompt
      )

    return
  }

  "vision-correct" {
    if([string]::IsNullOrWhiteSpace($Text)){
      if(-not [string]::IsNullOrWhiteSpace($Subcommand)){
        $Text = $Subcommand
      } else {
        throw "PIE_VISION_CORRECTION_TEXT_REQUIRED"
      }
    }

    Invoke-PieScript `
      -Script "pie_vision_correct_v1.ps1" `
      -Args @(
        "-RepoRoot",$RepoRoot,
        "-SessionId",$SessionId,
        "-Text",$Text
      )

    return
  }

  "generate-image" {
    if([string]::IsNullOrWhiteSpace($Prompt)){
      throw "PIE_IMAGE_PROMPT_REQUIRED"
    }

    Invoke-PieScript `
      -Script "pie_generate_image_v1.ps1" `
      -Args @(
        "-RepoRoot",$RepoRoot,
        "-SessionId",$SessionId,
        "-Prompt",$Prompt,
        "-Backend",$Backend
      )

    return
  }

  "memory" {
    switch($Subcommand.ToLowerInvariant()){

      "" {
        Show-MemoryHelp
        return
      }

      "help" {
        Show-MemoryHelp
        return
      }

      "policy" {
        if([string]::IsNullOrWhiteSpace($Mode)){
          Invoke-PieScript `
            -Script "pie_memory_policy_v1.ps1" `
            -Args @("-RepoRoot",$RepoRoot)
        } else {
          Invoke-PieScript `
            -Script "pie_memory_policy_v1.ps1" `
            -Args @(
              "-RepoRoot",$RepoRoot,
              "-Mode",$Mode
            )
        }

        return
      }

      "accept" {
        if([string]::IsNullOrWhiteSpace($Text)){
          throw "PIE_MEMORY_TEXT_REQUIRED"
        }

        $EffectiveLane = $Lane
        if([string]::IsNullOrWhiteSpace($EffectiveLane)){ $EffectiveLane = "active" }
        $A = @(
          "-RepoRoot",$RepoRoot,
          "-Text",$Text,
          "-Lane",$EffectiveLane
        )

        if(-not [string]::IsNullOrWhiteSpace($Project)){
          $A += @("-Project",$Project)
        }

        if(-not [string]::IsNullOrWhiteSpace($ProjectRepo)){
          $A += @("-ProjectRepo",$ProjectRepo)
        }

        if($Yes){ $A += "-Yes" }

        Invoke-PieInteractiveScript `
          -Script "pie_memory_accept_v1.ps1" `
          -Args $A

        return
      }

      "list" {
        $EffectiveLane = $Lane
        if([string]::IsNullOrWhiteSpace($EffectiveLane)){ $EffectiveLane = "all" }
        $A = @("-RepoRoot",$RepoRoot,"-Lane",$EffectiveLane,"-Limit",([string]$Limit))
        if(-not [string]::IsNullOrWhiteSpace($Project)){ $A += @("-Project",$Project) }
        Invoke-PieScript -Script "pie_memory_query_v1.ps1" -Args $A
        return
      }

      "search" {
        if([string]::IsNullOrWhiteSpace($Text)){ throw "PIE_MEMORY_QUERY_REQUIRED" }
        $EffectiveLane = $Lane
        if([string]::IsNullOrWhiteSpace($EffectiveLane)){ $EffectiveLane = "all" }
        $A = @("-RepoRoot",$RepoRoot,"-Query",$Text,"-Lane",$EffectiveLane,"-Limit",([string]$Limit))
        if(-not [string]::IsNullOrWhiteSpace($Project)){ $A += @("-Project",$Project) }
        Invoke-PieScript -Script "pie_memory_query_v1.ps1" -Args $A
        return
      }

      "forget" {
        if([string]::IsNullOrWhiteSpace($MemoryId)){ throw "PIE_MEMORY_ID_REQUIRED" }
        Invoke-PieScript -Script "pie_memory_forget_v1.ps1" -Args @("-RepoRoot",$RepoRoot,"-MemoryId",$MemoryId)
        return
      }

      default {
        throw ("PIE_MEMORY_UNKNOWN_COMMAND: " + $Subcommand)
      }
    }
  }

  "policy" {
    if([string]::IsNullOrWhiteSpace($Mode)){
      throw "PIE_POLICY_EVENT_REQUIRED_USE_MODE"
    }

    if([string]::IsNullOrWhiteSpace($Text)){
      if(-not [string]::IsNullOrWhiteSpace($Subcommand)){
        $Text = $Subcommand
      }
    }

    Invoke-PieScript `
      -Script "pie_policy_decide_v1.ps1" `
      -Args @(
        "-RepoRoot",$RepoRoot,
        "-Event",$Mode,
        "-Project",$Project,
        "-Text",$Text
      )

    return
  }

  "integrate" {
    if([string]::IsNullOrWhiteSpace($TargetRepo)){
      throw "PIE_INTEGRATE_TARGET_REPO_REQUIRED"
    }

    Invoke-PieScript `
      -Script "pie_repo_integrate_v1.ps1" `
      -Args @(
        "-RepoRoot",$RepoRoot,
        "-TargetRepo",$TargetRepo,
        "-Project",$Project,
        "-Language",$Language,
        "-Intent",$Profile
      )

    return
  }

  "repo-link" {
    if([string]::IsNullOrWhiteSpace($SessionId)){
      throw "PIE_REPO_LINK_SESSION_REQUIRED"
    }

    if([string]::IsNullOrWhiteSpace($TargetRepo)){
      throw "PIE_REPO_LINK_TARGET_REPO_REQUIRED"
    }

    Invoke-PieScript `
      -Script "pie_repo_link_v1.ps1" `
      -Args @(
        "-RepoRoot",$RepoRoot,
        "-SessionId",$SessionId,
        "-TargetRepo",$TargetRepo,
        "-Role",$Role
      )

    return
  }
  "scan-last" {
    if([string]::IsNullOrWhiteSpace($TargetRepo)){
      throw "PIE_SCAN_LAST_TARGET_REPO_REQUIRED"
    }

    $TargetRepo = (Resolve-Path -LiteralPath $TargetRepo).Path
    $ArtifactRoot = Join-Path $TargetRepo ".pie\scan\artifacts"

    if(-not (Test-Path -LiteralPath $ArtifactRoot -PathType Container)){
      throw "PIE_SCAN_ARTIFACTS_MISSING"
    }

    $Latest = Get-ChildItem -LiteralPath $ArtifactRoot -Directory |
      Sort-Object Name -Descending |
      Select-Object -First 1

    if($null -eq $Latest){
      throw "PIE_SCAN_LAST_NOT_FOUND"
    }

    $Desc = Join-Path $Latest.FullName "ai_repo_description.md"
    $Diff = Join-Path $Latest.FullName "diff.txt"

    Write-Host ("PIE_SCAN_LAST: " + $Latest.FullName) -ForegroundColor Green

    if(Test-Path -LiteralPath $Desc -PathType Leaf){
      Write-Host ""
      Write-Host "AI DESCRIPTION" -ForegroundColor Cyan
      Get-Content -LiteralPath $Desc -Raw
    }

    if(Test-Path -LiteralPath $Diff -PathType Leaf){
      Write-Host ""
      Write-Host "DIFF" -ForegroundColor Cyan
      Get-Content -LiteralPath $Diff -Raw
    }

    return
  }
  "save" {
    Invoke-PieScript `
      -Script "pie_conversation_save_v1.ps1" `
      -Args @(
        "-RepoRoot",$RepoRoot,
        "-SessionId",$SessionId
      )

    return
  }

  "open" {
    if([string]::IsNullOrWhiteSpace($Hash)){
      throw "PIE_CONVERSATION_HASH_REQUIRED"
    }

    Invoke-PieScript `
      -Script "pie_conversation_open_v1.ps1" `
      -Args @(
        "-RepoRoot",$RepoRoot,
        "-ConversationHash",$Hash,
        "-SessionId",$SessionId
      )

    return
  }

  "init" {
    if([string]::IsNullOrWhiteSpace($TargetRepo)){
      $TargetRepo = (Get-Location).Path
    }

    Invoke-PieScript `
      -Script "pie_init_repo_v1.ps1" `
      -Args @(
        "-TargetRepo",$TargetRepo,
        "-Project",$Project,
        "-Intent",$Profile
      )

    return
  }

  "verify" {
    if([string]::IsNullOrWhiteSpace($TargetRepo)){
      $TargetRepo = (Get-Location).Path
    }

    Invoke-PieScript `
      -Script "pie_verify_init_v1.ps1" `
      -Args @(
        "-TargetRepo",$TargetRepo
      )

    return
  }

  "detect" {
    if([string]::IsNullOrWhiteSpace($TargetRepo)){
      $TargetRepo = (Get-Location).Path
    }

    Invoke-PieScript `
      -Script "pie_project_detect_v1.ps1" `
      -Args @(
        "-TargetRepo",$TargetRepo
      )

    return
  }

  "stress-models" {
    $Model = Resolve-PieModel
    $A = @(
      "-RepoRoot",$RepoRoot,
      "-Model",$Model,
      "-Iterations",([string]$Iterations)
    )

    if($PullMissing){
      $A += "-PullMissing"
    }

    Invoke-PieScript `
      -Script "pie_model_matrix_stress_v1.ps1" `
      -Args $A

    return
  }

  "score" {
    Invoke-PieScript `
      -Script "pie_benchmark_score_v1.ps1" `
      -Args @(
        "-RepoRoot",$RepoRoot
      )

    return
  }

  "show" {
    $A = @("-RepoRoot",$RepoRoot)

    if(-not [string]::IsNullOrWhiteSpace($Model)){
      $A += @("-Model",$Model)
    }

    if($LastResults){
      $A += "-LastResults"
    }

    if($Scorecard){
      $A += "-Scorecard"
    }

    Invoke-PieScript `
      -Script "pie_show_results_v1.ps1" `
      -Args $A

    return
  }

"scan" {
  if([string]::IsNullOrWhiteSpace($TargetRepo)){
    throw "PIE_SCAN_TARGET_REPO_REQUIRED"
  }

  $Model = Resolve-PieModel

  Invoke-PieScript `
    -Script "pie_repo_scan_v1.ps1" `
    -Args @(
      "-RepoRoot",$RepoRoot,
      "-TargetRepo",$TargetRepo,
      "-Project",$Project,
      "-Model",$Model
    )

  return
}

  "verify-runtime" {
    Invoke-PieScript `
      -Script "_RUN_pie_runtime_green_v1.ps1" `
      -Args @(
        "-RepoRoot",$RepoRoot
      )

    return
  }

  "version" {
    $v = "0.1.0-dev"
    $verFile = Join-Path $RepoRoot "VERSION"
    if(Test-Path -LiteralPath $verFile -PathType Leaf){
      $fromFile = ((Get-Content -LiteralPath $verFile -Raw)).Trim()
      if(-not [string]::IsNullOrWhiteSpace($fromFile)){ $v = $fromFile }
    }
    Write-Host ("PIE " + $v) -ForegroundColor Cyan
    return
  }

  "run" {
    # Direct governed run through an engine backend (stub|ollama|llamacpp|onnx). Non-stub backends
    # require a sealed model manifest under registry\models\<model>\ and a live backend.
    if([string]::IsNullOrWhiteSpace($Prompt)){ throw "PIE_RUN_PROMPT_REQUIRED: use -Prompt <text>" }
    $RunModel = Resolve-PieModel
    $A = @("-RepoRoot",$RepoRoot,"-ModelId",$RunModel,"-Prompt",$Prompt)
    if(-not [string]::IsNullOrWhiteSpace($Backend)){ $A += @("-Backend",$Backend) }
    Invoke-PieScript -Script "pie_run_v1.ps1" -Args $A
    return
  }

  "verify-engines" {
    # Consolidated engine verification: parse-gate + persona alignment + Tier-0 + the three trios.
    Invoke-PieScript -Script "_RUN_pie_engine_verify_all_v1.ps1" -Args @("-RepoRoot",$RepoRoot,"-IncludeTier0")
    return
  }

  "recover" {
    # Complete any interrupted multi-file state transaction (roll back pre-commit, roll forward post-commit).
    Invoke-PieScript -Script "pie_recover_v1.ps1" -Args @("-RepoRoot",$RepoRoot)
    return
  }

  "seal-ollama" {
    if([string]::IsNullOrWhiteSpace($Model)){ throw "PIE_SEAL_OLLAMA_MODEL_REQUIRED: use -Model <ollama_tag>" }
    Invoke-PieInteractiveScript -Script "pie_seal_ollama_model_v1.ps1" -Args @("-RepoRoot",$RepoRoot,"-Model",$Model)
    return
  }

  default {
    Write-Host ("Unknown command: " + $Command) -ForegroundColor Yellow
    Write-Host "Run 'pie help' to see available commands." -ForegroundColor Yellow
    throw ("PIE_CLI_UNKNOWN_COMMAND: " + $Command)
  }
}
