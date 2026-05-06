param(
  [Parameter(Position=0)][string]$Command = "help",

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
  [string]$TargetRepo = ""
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

  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $ScriptPath @Args
  if($LASTEXITCODE -ne 0){
    throw ("PIE_CLI_CHILD_FAIL: " + $Script)
  }
}

switch($Command.ToLowerInvariant()){
  "help" {
    Write-Host ""
    Write-Host "PIE CLI" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Core:"
    Write-Host "  .\pie.ps1 help"
    Write-Host "  .\pie.ps1 setup -Profile core"
    Write-Host "  .\pie.ps1 models"
    Write-Host "  .\pie.ps1 pull -Model qwen2.5-coder:7b"
    Write-Host "  .\pie.ps1 chat -SessionId my_chat -Model qwen2.5-coder:7b"
    Write-Host ""
    Write-Host "Documents:"
    Write-Host "  .\pie.ps1 doc -Path C:\path\file.txt"
    Write-Host "  .\pie.ps1 image -Path C:\path\image.png"
    Write-Host ""
    Write-Host "Memory:"
    Write-Host "  .\pie.ps1 memory-policy"
    Write-Host "  .\pie.ps1 memory-policy -Mode ask"
    Write-Host "  .\pie.ps1 memory-policy -Mode auto_accept"
    Write-Host "  .\pie.ps1 memory-accept -Text `"Remember this`" -Lane active"
    Write-Host "  .\pie.ps1 memory-accept -Text `"Project rule`" -Lane project -Project pie"
    Write-Host ""
    Write-Host "Saved Conversations:"
    Write-Host "  .\pie.ps1 save -SessionId my_chat"
    Write-Host "  .\pie.ps1 open -Hash <conversation_hash>"
    Write-Host ""
    Write-Host "Repo Init / Verify:"
    Write-Host "  .\pie.ps1 init -TargetRepo C:\path\repo -Project my_project -Profile coding"
    Write-Host "  .\pie.ps1 verify-init -TargetRepo C:\path\repo"
    Write-Host ""
    Write-Host "Chat Commands:"
    Write-Host "  /exit"
    Write-Host "  /drop"
    Write-Host "  /new <sessionId>"
    Write-Host ""
    return
  }

  "setup" {
    Invoke-PieScript -Script "pie_setup_v1.ps1" -Args @("-RepoRoot",$RepoRoot,"-Profile",$Profile)
    return
  }

  "models" {
    & ollama list
    return
  }

  "pull" {
    if([string]::IsNullOrWhiteSpace($Model)){ throw "PIE_CLI_MODEL_REQUIRED" }
    & ollama pull $Model
    if($LASTEXITCODE -ne 0){ throw ("PIE_MODEL_PULL_FAIL: " + $Model) }
    return
  }

  "chat" {
    Invoke-PieScript -Script "pie_chat_v1.ps1" -Args @("-RepoRoot",$RepoRoot,"-SessionId",$SessionId,"-Model",$Model)
    return
  }

  "doc" {
    if([string]::IsNullOrWhiteSpace($Path)){ throw "PIE_DOC_PATH_REQUIRED" }
    $Msg = "Summarize this document and identify actionable next steps:`n`n" + (Get-Content -LiteralPath $Path -Raw)
    Invoke-PieScript -Script "pie_agent_send_v1.ps1" -Args @("-RepoRoot",$RepoRoot,"-SessionId",$SessionId,"-Message",$Msg)
    return
  }

  "image" {
    if([string]::IsNullOrWhiteSpace($Path)){ throw "PIE_IMAGE_PATH_REQUIRED" }
    $Msg = "Image path attached for local review: " + $Path + "`nDescribe what should be done with this image. If the current backend cannot inspect pixels, say so clearly."
    Invoke-PieScript -Script "pie_agent_send_v1.ps1" -Args @("-RepoRoot",$RepoRoot,"-SessionId",$SessionId,"-Message",$Msg)
    return
  }

  "memory-policy" {
    if([string]::IsNullOrWhiteSpace($Mode)){
      Invoke-PieScript -Script "pie_memory_policy_v1.ps1" -Args @("-RepoRoot",$RepoRoot)
    } else {
      Invoke-PieScript -Script "pie_memory_policy_v1.ps1" -Args @("-RepoRoot",$RepoRoot,"-Mode",$Mode)
    }
    return
  }

  "memory-accept" {
    if([string]::IsNullOrWhiteSpace($Text)){ throw "PIE_MEMORY_TEXT_REQUIRED" }

    $args = @("-RepoRoot",$RepoRoot,"-Text",$Text,"-Lane",$Lane)
    if(-not [string]::IsNullOrWhiteSpace($Project)){ $args += @("-Project",$Project) }
    if(-not [string]::IsNullOrWhiteSpace($ProjectRepo)){ $args += @("-ProjectRepo",$ProjectRepo) }

    Invoke-PieScript -Script "pie_memory_accept_v1.ps1" -Args $args
    return
  }

  "save" {
    Invoke-PieScript -Script "pie_conversation_save_v1.ps1" -Args @("-RepoRoot",$RepoRoot,"-SessionId",$SessionId)
    return
  }

  "open" {
    if([string]::IsNullOrWhiteSpace($Hash)){ throw "PIE_CONVERSATION_HASH_REQUIRED" }
    Invoke-PieScript -Script "pie_conversation_open_v1.ps1" -Args @("-RepoRoot",$RepoRoot,"-ConversationHash",$Hash,"-SessionId",$SessionId)
    return
  }

  "init" {
    if([string]::IsNullOrWhiteSpace($TargetRepo)){ $TargetRepo = (Get-Location).Path }
    Invoke-PieScript -Script "pie_init_repo_v1.ps1" -Args @("-TargetRepo",$TargetRepo,"-Project",$Project,"-Intent",$Profile)
    return
  }

  "verify-init" {
    if([string]::IsNullOrWhiteSpace($TargetRepo)){ $TargetRepo = (Get-Location).Path }
    Invoke-PieScript -Script "pie_verify_init_v1.ps1" -Args @("-TargetRepo",$TargetRepo)
    return
  }

  default {
    throw ("PIE_CLI_UNKNOWN_COMMAND: " + $Command)
  }
}
