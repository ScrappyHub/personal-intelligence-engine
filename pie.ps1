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
  [switch]$PullMissing,
  [switch]$LastResults,
  [switch]$Scorecard,
  [int]$Iterations = 2
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
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

  & powershell.exe `
    -NoProfile `
    -NonInteractive `
    -ExecutionPolicy Bypass `
    -File $ScriptPath `
    @Args

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
  Write-Host "  help           Show help"
  Write-Host "  setup          Setup local model/profile requirements"
  Write-Host "  models         List local models"
  Write-Host "  pull           Download a model"
  Write-Host "  chat           Start local chat"
  Write-Host "  doc            Send a document to PIE"
  Write-Host "  image          Send an image path to PIE"
  Write-Host "  attach         Attach a file/image to a session"
  Write-Host "  generate-image Generate an image request"
  Write-Host "  memory         Memory commands"
  Write-Host "  save           Save conversation by hash"
  Write-Host "  open           Reopen saved conversation by hash"
  Write-Host "  init           Initialize PIE in a repo"
  Write-Host "  verify         Verify PIE repo init"
  Write-Host "  detect         Detect repo/project stack"
  Write-Host "  stress-models  Stress test local models"
  Write-Host "  score          Score latest benchmark run"
  Write-Host "  show           Show latest benchmark/model results"
  Write-Host ""

  Write-Host "Examples:"
  Write-Host "  pie setup -Profile core"
  Write-Host "  pie models"
  Write-Host "  pie pull -Model qwen2.5-coder:7b"
  Write-Host "  pie chat -SessionId my_chat"
  Write-Host "  pie detect -TargetRepo C:\dev\pie"
  Write-Host "  pie stress-models -Iterations 1"
  Write-Host "  pie score"
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

    Invoke-PieScript `
      -Script "pie_chat_v1.ps1" `
      -Args @(
        "-RepoRoot",$RepoRoot,
        "-SessionId",$SessionId,
        "-Model",$Model
      )

    return
  }

  "doc" {

    if([string]::IsNullOrWhiteSpace($Path)){
      throw "PIE_DOC_PATH_REQUIRED"
    }

    $Msg =
      "Summarize this document and identify actionable next steps:`n`n" +
      (Get-Content -LiteralPath $Path -Raw)

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

    $Msg =
      "Image path attached for local review: " + $Path +
      "`nIf the backend cannot inspect pixels, say so clearly."

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

        Invoke-PieScript `
          -Script "pie_memory_accept_v1.ps1" `
          -Args $A

        return
      }

    
  "show" {

    $A = @(
      "-RepoRoot",$RepoRoot
    )

    if(-not [string]::IsNullOrWhiteSpace($Model)){
      $A += @(
        "-Model",$Model
      )
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
  default {
        throw ("PIE_MEMORY_UNKNOWN_COMMAND: " + $Subcommand)
      }
    }
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

    $A = @(
      "-RepoRoot",$RepoRoot
    )

    if(-not [string]::IsNullOrWhiteSpace($Model)){
      $A += @(
        "-Model",$Model
      )
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
  default {
    throw ("PIE_CLI_UNKNOWN_COMMAND: " + $Command)
  }
}


