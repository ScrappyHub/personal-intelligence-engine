param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$SessionId,
  [Parameter(Mandatory=$false)][string]$Model = "qwen2.5-coder:7b",
  [Parameter(Mandatory=$false)][string]$Goal = "",
  [Parameter(Mandatory=$false)][switch]$NewSettings
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)
$Enc = New-Object System.Text.UTF8Encoding($false)

function Write-Utf8NoBomLf {
  param(
    [Parameter(Mandatory=$true)][string]$Path,
    [Parameter(Mandatory=$true)][AllowEmptyString()][string]$Text
  )

  $Dir = Split-Path -Parent $Path

  if(-not (Test-Path -LiteralPath $Dir -PathType Container)){
    New-Item -ItemType Directory -Force -Path $Dir | Out-Null
  }

  $Clean = $Text.Replace("`r`n","`n").Replace("`r","`n")

  if(-not $Clean.EndsWith("`n")){
    $Clean += "`n"
  }

  [System.IO.File]::WriteAllText($Path,$Clean,$Enc)
}

function Read-TextIfExists {
  param([Parameter(Mandatory=$true)][string]$Path)

  if(Test-Path -LiteralPath $Path -PathType Leaf){
    return (Get-Content -LiteralPath $Path -Raw).Trim()
  }

  return ""
}

function Pick-Menu {
  param(
    [Parameter(Mandatory=$true)][string]$Title,
    [Parameter(Mandatory=$true)][string[]]$Options
  )

  Write-Host ""
  Write-Host $Title -ForegroundColor Cyan

  for($i=0; $i -lt @($Options).Count; $i++){
    Write-Host ("  " + ($i + 1) + ") " + $Options[$i])
  }

  $N = Read-Host "select"
  $Idx = ([int]$N) - 1

  if($Idx -lt 0 -or $Idx -ge @($Options).Count){
    throw ("PIE_CHAT_INVALID_SELECTION: " + $Title)
  }

  return $Options[$Idx]
}

function Select-Repo {
  $DevRoot = "C:\dev"
  $Options = New-Object System.Collections.Generic.List[string]

  if(Test-Path -LiteralPath $DevRoot -PathType Container){
    $Dirs = @(Get-ChildItem -LiteralPath $DevRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name)

    foreach($Dir in $Dirs){
      [void]$Options.Add($Dir.FullName)
    }
  }

  [void]$Options.Add("Manual path")
  [void]$Options.Add("No repo")

  $Pick = Pick-Menu -Title "Project repo" -Options $Options.ToArray()

  if($Pick -eq "Manual path"){
    $Manual = Read-Host "repo path"

    if([string]::IsNullOrWhiteSpace($Manual)){
      return ""
    }

    if(-not (Test-Path -LiteralPath $Manual -PathType Container)){
      throw ("PIE_CHAT_REPO_NOT_FOUND: " + $Manual)
    }

    return (Resolve-Path -LiteralPath $Manual).Path
  }

  if($Pick -eq "No repo"){
    return ""
  }

  return $Pick
}

function Refresh-SessionPaths {
  $script:RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)
  $script:GoalFile = Join-Path $RunRoot "goal.txt"
  $script:LanguageFile = Join-Path $RunRoot "language.txt"
  $script:LanguageVersionFile = Join-Path $RunRoot "language_version.txt"
  $script:ProjectRepoFile = Join-Path $RunRoot "project_repo.txt"
  $script:SessionMetaFile = Join-Path $RunRoot "session.json"
}

Refresh-SessionPaths

Write-Host "PIE_CHAT_V1_START" -ForegroundColor Cyan

if($NewSettings -or -not (Test-Path -LiteralPath $RunRoot -PathType Container)){

  $Mode = Pick-Menu -Title "Session setup" -Options @(
    "Quick chat",
    "Project chat",
    "Continue existing session"
  )

  if($Mode -eq "Continue existing session"){
    $Existing = Read-Host "session id / hash / name"

    if(-not [string]::IsNullOrWhiteSpace($Existing)){
      $SessionId = $Existing.Trim()
      Refresh-SessionPaths
    }
  }

  if($Mode -eq "Project chat"){
    $ProjectRepo = Select-Repo

    $Language = Pick-Menu -Title "Coding language / stack" -Options @(
      "PowerShell",
      "Python",
      "JavaScript/TypeScript",
      "SQL",
      "Rust",
      "Go",
      "Java",
      "C#",
      "Bash",
      "Other"
    )

    $LanguageVersion = Read-Host "language version / runtime details"

    if([string]::IsNullOrWhiteSpace($Goal)){
      $Goal = Read-Host "chat goal"
    }

    New-Item -ItemType Directory -Force -Path $RunRoot | Out-Null

    Write-Utf8NoBomLf -Path $ProjectRepoFile -Text $ProjectRepo
    Write-Utf8NoBomLf -Path $LanguageFile -Text $Language
    Write-Utf8NoBomLf -Path $LanguageVersionFile -Text $LanguageVersion
    Write-Utf8NoBomLf -Path $GoalFile -Text $Goal
  }

  if($Mode -eq "Quick chat"){
    if([string]::IsNullOrWhiteSpace($Goal)){
      $Goal = Read-Host "chat goal optional"
    }

    New-Item -ItemType Directory -Force -Path $RunRoot | Out-Null

    if(-not [string]::IsNullOrWhiteSpace($Goal)){
      Write-Utf8NoBomLf -Path $GoalFile -Text $Goal
    }
  }
}

New-Item -ItemType Directory -Force -Path $RunRoot | Out-Null

$GoalText = Read-TextIfExists -Path $GoalFile
$LanguageText = Read-TextIfExists -Path $LanguageFile
$LanguageVersion = Read-TextIfExists -Path $LanguageVersionFile
$ProjectRepo = Read-TextIfExists -Path $ProjectRepoFile

$Meta = [ordered]@{
  schema = "pie.chat.session.v1"
  session_id = $SessionId
  model = $Model
  goal = $GoalText
  language = $LanguageText
  language_version = $LanguageVersion
  project_repo = $ProjectRepo
  opened_utc = [DateTime]::UtcNow.ToString("o")
}

Write-Utf8NoBomLf -Path $SessionMetaFile -Text ($Meta | ConvertTo-Json -Depth 8)

Write-Host ""
Write-Host ("session: " + $SessionId)
Write-Host ("model:   " + $Model)
Write-Host ("goal:    " + $GoalText)
Write-Host ("language:" + $LanguageText + " " + $LanguageVersion)
Write-Host ("repo:    " + $ProjectRepo)
Write-Host "commands: /exit  /drop  /settings  /goal <goal>  /language <language>  /repo"
Write-Host ""

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_agent_start_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -Model $Model `
  -Backend "ollama"

if($LASTEXITCODE -ne 0){
  throw "PIE_CHAT_START_FAIL"
}

while($true){

  $msg = Read-Host "you"

  if($null -eq $msg){
    continue
  }

  $msg = [string]$msg

  if([string]::IsNullOrWhiteSpace($msg)){
    continue
  }

  if($msg -eq "/exit"){
    break
  }

  if($msg -eq "/drop"){
    Remove-Item -LiteralPath $RunRoot -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host ("PIE_CHAT_DROPPED: " + $SessionId) -ForegroundColor Yellow
    break
  }

  if($msg -eq "/settings"){
    $GoalText = Read-TextIfExists -Path $GoalFile
    $LanguageText = Read-TextIfExists -Path $LanguageFile
    $LanguageVersion = Read-TextIfExists -Path $LanguageVersionFile
    $ProjectRepo = Read-TextIfExists -Path $ProjectRepoFile

    Write-Host ("goal: " + $GoalText)
    Write-Host ("language: " + $LanguageText + " " + $LanguageVersion)
    Write-Host ("repo: " + $ProjectRepo)
    continue
  }

  if($msg.StartsWith("/goal ")){
    $GoalText = $msg.Substring(6).Trim()
    Write-Utf8NoBomLf -Path $GoalFile -Text $GoalText
    Write-Host "PIE_CHAT_GOAL_SET" -ForegroundColor Green
    continue
  }

  if($msg.StartsWith("/language ")){
    $LanguageText = $msg.Substring(10).Trim()
    Write-Utf8NoBomLf -Path $LanguageFile -Text $LanguageText
    Write-Host "PIE_CHAT_LANGUAGE_SET" -ForegroundColor Green
    continue
  }

  if($msg -eq "/repo"){
    $ProjectRepo = Select-Repo
    Write-Utf8NoBomLf -Path $ProjectRepoFile -Text $ProjectRepo
    Write-Host ("PIE_CHAT_REPO_SET: " + $ProjectRepo) -ForegroundColor Green
    continue
  }

  Write-Host "PIE_CHAT_CONTEXT_BUILD_START" -ForegroundColor DarkCyan

  $ContextOut = @(
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
      -File (Join-Path $RepoRoot "scripts\pie_context_build_v1.ps1") `
      -RepoRoot $RepoRoot `
      -SessionId $SessionId `
      -UserMessage $msg
  ) -join "`n"

  if($LASTEXITCODE -ne 0){
    Write-Host "PIE_CHAT_CONTEXT_BUILD_FAIL" -ForegroundColor Red
    continue
  }

  $PromptPath = ""

  foreach($Line in @($ContextOut -split "`n")){
    if($Line -like "PIE_CONTEXT_BUILD_OK:*"){
      $PromptPath = $Line.Substring("PIE_CONTEXT_BUILD_OK:".Length).Trim()
    }
  }

  if([string]::IsNullOrWhiteSpace($PromptPath)){
    Write-Host "PIE_CHAT_CONTEXT_PROMPT_PATH_MISSING" -ForegroundColor Red
    continue
  }

  Write-Host "PIE_CHAT_SEND_START" -ForegroundColor DarkCyan

  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File (Join-Path $RepoRoot "scripts\pie_agent_send_v1.ps1") `
    -RepoRoot $RepoRoot `
    -SessionId $SessionId `
    -MessagePath $PromptPath

  if($LASTEXITCODE -ne 0){
    Write-Host "PIE_CHAT_SEND_FAIL" -ForegroundColor Red
  }

  Write-Host ""
}
