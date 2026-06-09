param(
  [Parameter(Position=0)][string]$Command = "help",
  [Parameter(Position=1)][string]$Subcommand = "",

  [string]$RepoRoot = ".",
  [string]$SessionId = "pie_chat",
  [string]$Model = "qwen2.5-coder:7b",
  [string]$Backend = "ollama",
  [string]$Profile = "core",
  [string]$Mode = "",
  [string]$Path = "",
  [string]$Hash = "",
  [string]$Text = "",
  [string]$Lane = "active",
  [string]$Project = "",
  [string]$ProjectRepo = "",
  [string]$TargetRepo = "",
  [string]$Prompt = "",
  [string]$Goal = "",
  [string]$Language = "",
  [switch]$NewSettings,
  [switch]$PullMissing,
  [switch]$LastResults,
  [switch]$Scorecard,
  [int]$Iterations = 2
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
  $RemainingArgs = @($args)

  if($RemainingArgs.Count -ge 1 -and ([string]$RemainingArgs[0]) -eq $Command){
    if($RemainingArgs.Count -ge 2){
      $ModeArg = [string]$RemainingArgs[1]
    }
  }
  elseif($RemainingArgs.Count -ge 1){
    $ModeArg = [string]$RemainingArgs[0]
  }

  if([string]::IsNullOrWhiteSpace($ModeArg)){
    throw "PIE_GREEN_USAGE: pie green governance | pie green governance-full | pie green full"
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
  Write-Host "  setup           Setup local model/profile requirements"
  Write-Host "  models          List local models"
  Write-Host "  pull            Download a model"
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
  Write-Host ""
  Write-Host "Examples:"
  Write-Host "  pie chat"
  Write-Host "  pie chat -NewSettings"
  Write-Host "  pie integrate -TargetRepo C:\dev\nfl -Project nfl -Language `"PowerShell 5.1`""
  Write-Host "  pie ask -SessionId my_chat -Text `"What is my current chat goal?`""
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
  Write-Host ""
}

switch($Command.ToLowerInvariant()){

  "help" {
    Show-Help
    return
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
    & ollama list
    return
  }

  "pull" {
    if([string]::IsNullOrWhiteSpace($Model)){
      throw "PIE_CLI_MODEL_REQUIRED"
    }

    & ollama pull $Model

    if($LASTEXITCODE -ne 0){
      throw ("PIE_MODEL_PULL_FAIL: " + $Model)
    }

    return
  }

  "chat" {
    $A = @(
      "-RepoRoot",$RepoRoot,
      "-SessionId",$SessionId,
      "-Model",$Model
    )

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
        "-Message",$Text
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

        $A = @(
          "-RepoRoot",$RepoRoot,
          "-Text",$Text,
          "-Lane",$Lane
        )

        if(-not [string]::IsNullOrWhiteSpace($Project)){
          $A += @("-Project",$Project)
        }

        if(-not [string]::IsNullOrWhiteSpace($ProjectRepo)){
          $A += @("-ProjectRepo",$ProjectRepo)
        }

        Invoke-PieInteractiveScript `
          -Script "pie_memory_accept_v1.ps1" `
          -Args $A

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
    $A = @(
      "-RepoRoot",$RepoRoot,
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

  default {
    throw ("PIE_CLI_UNKNOWN_COMMAND: " + $Command)
  }
}










