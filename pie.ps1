param(
  [Parameter(Mandatory=$false, Position=0)]
  [ValidateSet("help","chat","pull","models","doc","image")]
  [string]$Command = "chat",

  [Parameter(Mandatory=$false)]
  [string]$SessionId = "pie_chat",

  [Parameter(Mandatory=$false)]
  [string]$Model = "qwen2.5-coder:7b",

  [Parameter(Mandatory=$false)]
  [string]$RepoRoot = $PSScriptRoot,

  [Parameter(Mandatory=$false)]
  [string]$Path,

  [Parameter(Mandatory=$false)]
  [string]$AttachPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

function Show-Help {
  Write-Host ""
  Write-Host "PIE CLI" -ForegroundColor Cyan
  Write-Host ""

  Write-Host "Commands:"
  Write-Host "  .\pie.ps1 help"
  Write-Host "  .\pie.ps1 models"
  Write-Host "  .\pie.ps1 pull  -Model qwen2.5-coder:7b"
  Write-Host "  .\pie.ps1 chat  -SessionId my_chat -Model qwen2.5-coder:7b"
  Write-Host "  .\pie.ps1 chat  -AttachPath C:\path\file.txt"
  Write-Host "  .\pie.ps1 doc   -Path C:\path\document.txt"
  Write-Host "  .\pie.ps1 image -Path C:\path\image.png"

  Write-Host ""
  Write-Host "Chat Commands:"
  Write-Host "  /exit"
  Write-Host "  /drop"
  Write-Host "  /new <sessionId>"
  Write-Host ""
}

if($Command -eq "help"){
  Show-Help
  exit 0
}

if($Command -eq "models"){
  ollama list
  exit 0
}

if($Command -eq "pull"){
  ollama pull $Model
  exit $LASTEXITCODE
}

if($Command -eq "doc"){

  if([string]::IsNullOrWhiteSpace($Path)){
    throw "PIE_DOC_PATH_REQUIRED"
  }

  $Full = (Resolve-Path -LiteralPath $Path).Path

  $Text = [System.IO.File]::ReadAllText($Full)

  powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File (Join-Path $RepoRoot "scripts\pie_agent_send_v1.ps1") `
    -RepoRoot $RepoRoot `
    -SessionId $SessionId `
    -Message ("Read and summarize this document.`nPATH: " + $Full + "`n`n" + $Text)

  exit $LASTEXITCODE
}

if($Command -eq "image"){

  if([string]::IsNullOrWhiteSpace($Path)){
    throw "PIE_IMAGE_PATH_REQUIRED"
  }

  $Full = (Resolve-Path -LiteralPath $Path).Path

  powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File (Join-Path $RepoRoot "scripts\pie_agent_send_v1.ps1") `
    -RepoRoot $RepoRoot `
    -SessionId $SessionId `
    -Message ("Image path received for future multimodal support: " + $Full)

  exit $LASTEXITCODE
}

if($Command -eq "chat"){

  if(-not [string]::IsNullOrWhiteSpace($AttachPath)){
    $FullAttach = (Resolve-Path -LiteralPath $AttachPath).Path
    Write-Host ("PIE_ATTACH_PATH: " + $FullAttach) -ForegroundColor DarkCyan
  }

  powershell.exe -NoProfile -ExecutionPolicy Bypass `
    -File (Join-Path $RepoRoot "scripts\pie_chat_v1.ps1") `
    -RepoRoot $RepoRoot `
    -SessionId $SessionId `
    -Model $Model

  exit $LASTEXITCODE
}

throw ("PIE_UNKNOWN_COMMAND: " + $Command)
