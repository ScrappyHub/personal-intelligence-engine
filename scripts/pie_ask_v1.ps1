param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$SessionId,
  [Parameter(Mandatory=$true)][string]$Message,
  [Parameter(Mandatory=$false)][ValidateRange(1,86400)][int]$TimeoutSeconds = 180,
  [Parameter(Mandatory=$false)][ValidateRange(1,3)][int]$MaxAttempts = 2,
  [Parameter(Mandatory=$false)][ValidateRange(1,300)][int]$ProgressIntervalSeconds = 5
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $RepoRoot "scripts\_lib_pie_agent_session_v1.ps1")
[void](PIE_GetAgentSession -RepoRoot $RepoRoot -SessionId $SessionId -RequireRunning -RequireIntegrity)
$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)
$AttachRoot = Join-Path $RunRoot "attachments"

$Context = ""

function Read-Utf8NoBom {
  param([Parameter(Mandatory=$true)][string]$Path)

  $Enc = New-Object System.Text.UTF8Encoding($false)
  return [System.IO.File]::ReadAllText($Path,$Enc)
}

if(Test-Path -LiteralPath $AttachRoot -PathType Container){
  $Files = @(Get-ChildItem -LiteralPath $AttachRoot -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne "attachments.ndjson" })

  if(@($Files).Count -gt 0){
    $Context += "ATTACHMENTS:`n"

    foreach($File in $Files){
      $Context += "- " + $File.FullName + "`n"

      $Ext = [System.IO.Path]::GetExtension($File.FullName).ToLowerInvariant()
      if($Ext -in @(".txt",".md",".json",".csv",".ps1",".py",".js",".ts",".html",".css",".xml",".yml",".yaml",".sql")){
        $Raw = Read-Utf8NoBom -Path $File.FullName
        if($Raw.Length -gt 6000){ $Raw = $Raw.Substring(0,6000) }
        $Context += "CONTENT_BEGIN " + $File.Name + "`n" + $Raw + "`nCONTENT_END`n"
      } else {
        $Context += "NOTE: Binary or image file attached. If current backend cannot inspect pixels directly, say so clearly.`n"
      }
    }

    $Context += "`n"
  }
}

$Full = $Context + "USER:`n" + $Message
$AskInputRoot = Join-Path $RunRoot "ask_inputs"
if(-not (Test-Path -LiteralPath $AskInputRoot -PathType Container)){ New-Item -ItemType Directory -Force -Path $AskInputRoot | Out-Null }
$InputPath = Join-Path $AskInputRoot ("ask_" + (Get-Date -Format "yyyyMMdd_HHmmss_fff") + ".txt")
$ConversationMessagePath = Join-Path $AskInputRoot ("message_" + (Get-Date -Format "yyyyMMdd_HHmmss_fff") + ".txt")
$InputText = $Full.Replace("`r`n","`n").Replace("`r","`n")
if(-not $InputText.EndsWith("`n")){ $InputText += "`n" }
[System.IO.File]::WriteAllText($InputPath,$InputText,(New-Object System.Text.UTF8Encoding($false)))
$ConversationText = $Message.Replace("`r`n","`n").Replace("`r","`n")
[System.IO.File]::WriteAllText($ConversationMessagePath,$ConversationText,(New-Object System.Text.UTF8Encoding($false)))

$ContextScript = Join-Path $RepoRoot "scripts\pie_context_build_v1.ps1"
if(-not (Test-Path -LiteralPath $ContextScript -PathType Leaf)){ throw "PIE_ASK_CONTEXT_BUILDER_MISSING" }
$ContextOut = @(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $ContextScript -RepoRoot $RepoRoot -SessionId $SessionId -UserMessagePath $InputPath) -join "`n"
if($LASTEXITCODE -ne 0){ throw "PIE_ASK_CONTEXT_BUILD_FAIL" }
$PromptPath = ""
foreach($Line in @($ContextOut -split "`n")){
  if($Line -like "PIE_CONTEXT_BUILD_OK:*"){ $PromptPath = $Line.Substring("PIE_CONTEXT_BUILD_OK:".Length).Trim() }
}
if([string]::IsNullOrWhiteSpace($PromptPath)){ throw "PIE_ASK_CONTEXT_PROMPT_PATH_MISSING" }

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_agent_send_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -MessagePath $PromptPath `
  -ConversationMessagePath $ConversationMessagePath `
  -TimeoutSeconds $TimeoutSeconds `
  -MaxAttempts $MaxAttempts `
  -ProgressIntervalSeconds $ProgressIntervalSeconds
