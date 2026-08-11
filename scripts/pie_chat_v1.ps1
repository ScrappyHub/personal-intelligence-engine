param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$SessionId,
  [Parameter(Mandatory=$false)][string]$Model = "qwen2.5-coder:7b",
  [Parameter(Mandatory=$false)][ValidateSet("ollama","mock")][string]$Backend = "ollama",
  [Parameter(Mandatory=$false)][string]$Goal = "",
  [Parameter(Mandatory=$false)][string]$ProjectRepo = "",
  [Parameter(Mandatory=$false)][switch]$NewSettings,
  [Parameter(Mandatory=$false)][switch]$SetupOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $RepoRoot "scripts\_lib_pie_agent_session_v1.ps1")

if($SessionId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$'){ throw "PIE_CHAT_SESSION_ID_INVALID" }
$Enc = New-Object System.Text.UTF8Encoding($false)
$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)

function Write-Utf8NoBomLf {
  param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)][AllowEmptyString()][string]$Text)
  $Dir = Split-Path -Parent $Path
  if(-not (Test-Path -LiteralPath $Dir -PathType Container)){ New-Item -ItemType Directory -Force -Path $Dir | Out-Null }
  $Clean = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $Clean.EndsWith("`n")){ $Clean += "`n" }
  [System.IO.File]::WriteAllText($Path,$Clean,$Enc)
}

function Pick-Menu {
  param([Parameter(Mandatory=$true)][string]$Title,[Parameter(Mandatory=$true)][string[]]$Options)
  Write-Host ""
  Write-Host $Title -ForegroundColor Cyan
  for($Index = 0; $Index -lt $Options.Count; $Index++){ Write-Host ("  " + ($Index + 1) + ") " + $Options[$Index]) }
  $Selection = 0
  if(-not [int]::TryParse((Read-Host "select"),[ref]$Selection) -or $Selection -lt 1 -or $Selection -gt $Options.Count){
    throw ("PIE_CHAT_INVALID_SELECTION: " + $Title)
  }
  return $Options[$Selection - 1]
}

function Select-Repo {
  $Options = New-Object System.Collections.Generic.List[string]
  if(Test-Path -LiteralPath "C:\dev" -PathType Container){
    foreach($Directory in @(Get-ChildItem -LiteralPath "C:\dev" -Directory -ErrorAction SilentlyContinue | Sort-Object Name)){ [void]$Options.Add($Directory.FullName) }
  }
  [void]$Options.Add("Manual path")
  [void]$Options.Add("No repo")
  $Selected = Pick-Menu -Title "Project repo" -Options $Options.ToArray()
  if($Selected -eq "No repo"){ return "" }
  if($Selected -eq "Manual path"){ $Selected = (Read-Host "repo path").Trim() }
  if([string]::IsNullOrWhiteSpace($Selected)){ return "" }
  if(-not (Test-Path -LiteralPath $Selected -PathType Container)){ throw ("PIE_CHAT_REPO_NOT_FOUND: " + $Selected) }
  return (Resolve-Path -LiteralPath $Selected).Path
}

function Show-VerifiedHistory {
  param([Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$Turns)
  if($Turns.Count -eq 0){ return }
  Write-Host ""
  Write-Host ("Recalled " + $Turns.Count + " verified turn(s).") -ForegroundColor DarkCyan
  $Start = [Math]::Max(0,$Turns.Count - 6)
  for($Index = $Start; $Index -lt $Turns.Count; $Index++){
    Write-Host ("you: " + [string]$Turns[$Index].message)
    Write-Host ("PIE: " + [string]$Turns[$Index].response)
  }
}

$Session = $null
if(Test-Path -LiteralPath $RunRoot -PathType Container){
  if($NewSettings){ throw ("PIE_CHAT_SESSION_ALREADY_EXISTS: " + $SessionId + ". Choose a new session name for different settings.") }
  $Session = PIE_GetAgentSession -RepoRoot $RepoRoot -SessionId $SessionId -RequireIntegrity
  if(-not [string]::IsNullOrWhiteSpace($ProjectRepo)){
    $RequestedRepo = (Resolve-Path -LiteralPath $ProjectRepo).Path
    if($RequestedRepo -ine [string]$Session.project_repo){ throw ("PIE_CHAT_PROJECT_SWITCH_REQUIRES_NEW_SESSION: " + $SessionId) }
  }
  if(-not [string]::IsNullOrWhiteSpace($Goal) -and $Goal -ne [string]$Session.goal){ throw ("PIE_CHAT_GOAL_SWITCH_REQUIRES_NEW_SESSION: " + $SessionId) }
  $Model = [string]$Session.model
  $Backend = [string]$Session.backend
  $ProjectRepo = [string]$Session.project_repo
  $Goal = [string]$Session.goal
  if([string]$Session.status -ne "running"){
    & (Join-Path $RepoRoot "scripts\pie_agent_start_v1.ps1") -RepoRoot $RepoRoot -SessionId $SessionId -Model $Model -Backend $Backend -ProjectRepo $ProjectRepo -Goal $Goal | Out-Host
    $Session = PIE_GetAgentSession -RepoRoot $RepoRoot -SessionId $SessionId -RequireRunning -RequireIntegrity
  }
}
else {
  $Language = ""
  $LanguageVersion = ""
  if(-not $SetupOnly -and [string]::IsNullOrWhiteSpace($ProjectRepo)){
    $Mode = Pick-Menu -Title "Session setup" -Options @("Quick chat","Project chat")
    if($Mode -eq "Project chat"){
      $ProjectRepo = Select-Repo
      $Language = Pick-Menu -Title "Coding language / stack" -Options @("PowerShell","Python","JavaScript/TypeScript","SQL","Rust","Go","Java","C#","Bash","Other")
      $LanguageVersion = Read-Host "language version / runtime details"
    }
    if([string]::IsNullOrWhiteSpace($Goal)){ $Goal = Read-Host "chat goal optional" }
  }
  elseif(-not [string]::IsNullOrWhiteSpace($ProjectRepo)){
    if(-not (Test-Path -LiteralPath $ProjectRepo -PathType Container)){ throw ("PIE_CHAT_REPO_NOT_FOUND: " + $ProjectRepo) }
    $ProjectRepo = (Resolve-Path -LiteralPath $ProjectRepo).Path
  }

  & (Join-Path $RepoRoot "scripts\pie_agent_start_v1.ps1") -RepoRoot $RepoRoot -SessionId $SessionId -Model $Model -Backend $Backend -ProjectRepo $ProjectRepo -Goal $Goal | Out-Host
  $Session = PIE_GetAgentSession -RepoRoot $RepoRoot -SessionId $SessionId -RequireRunning -RequireIntegrity
  if(-not [string]::IsNullOrWhiteSpace($Language)){ Write-Utf8NoBomLf -Path (Join-Path $RunRoot "language.txt") -Text $Language }
  if(-not [string]::IsNullOrWhiteSpace($LanguageVersion)){ Write-Utf8NoBomLf -Path (Join-Path $RunRoot "language_version.txt") -Text $LanguageVersion }
}

$Meta = [ordered]@{
  schema="pie.chat.session.v2"; session_id=$SessionId; binding_sha256=$Session.binding_sha256
  model=$Session.model; backend=$Session.backend; goal=$Session.goal; project_repo=$Session.project_repo
  opened_utc=[DateTime]::UtcNow.ToString("o")
}
Write-Utf8NoBomLf -Path (Join-Path $RunRoot "session.json") -Text ($Meta | ConvertTo-Json -Depth 8)

Write-Host "PIE_CHAT_V2_READY" -ForegroundColor Cyan
Write-Host ("session: " + $SessionId)
Write-Host ("model:   " + $Session.model)
Write-Host ("goal:    " + $Session.goal)
Write-Host ("repo:    " + $Session.project_repo)
Write-Host ("integrity: " + $Session.integrity)
Show-VerifiedHistory -Turns @($Session.conversation_turns)
if($SetupOnly){ return }

Write-Host ""
Write-Host "commands: /exit  /settings"
while($true){
  $Message = Read-Host "you"
  if($null -eq $Message -or [string]::IsNullOrWhiteSpace([string]$Message)){ continue }
  $Message = [string]$Message
  if($Message -eq "/exit"){ break }
  if($Message -eq "/settings"){
    $Current = PIE_GetAgentSession -RepoRoot $RepoRoot -SessionId $SessionId -RequireIntegrity
    Write-Host ("goal: " + $Current.goal)
    Write-Host ("repo: " + $Current.project_repo)
    Write-Host ("model: " + $Current.model)
    Write-Host ("turns: " + @($Current.conversation_turns).Count)
    continue
  }
  if($Message -eq "/drop"){ Write-Host "PIE_CHAT_DROP_DISABLED: use a future governed archive/delete workflow." -ForegroundColor Yellow; continue }
  if($Message.StartsWith("/goal ") -or $Message -eq "/repo" -or $Message.StartsWith("/language ")){
    Write-Host "PIE_CHAT_BINDING_IMMUTABLE: start a new session for different project or goal settings." -ForegroundColor Yellow
    continue
  }
  if($Message -match "^(git|powershell|pwsh|node|npm|python|py|ollama|supabase|docker|dotnet)\s+"){
    Write-Host "PIE_CHAT_COMMAND_DETECTED: run shell commands in PowerShell; PIE will not execute them as chat text." -ForegroundColor Yellow
    continue
  }
  & (Join-Path $RepoRoot "scripts\pie_ask_v1.ps1") -RepoRoot $RepoRoot -SessionId $SessionId -Message $Message | Out-Host
}
