param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$SessionId = "pie_context_selftest"
$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)
$Enc = New-Object System.Text.UTF8Encoding($false)

function Write-Utf8NoBomLf {
  param([string]$Path,[string]$Text)
  $Dir = Split-Path -Parent $Path
  if(-not (Test-Path -LiteralPath $Dir -PathType Container)){
    New-Item -ItemType Directory -Force -Path $Dir | Out-Null
  }
  $Clean = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $Clean.EndsWith("`n")){ $Clean += "`n" }
  [System.IO.File]::WriteAllText($Path,$Clean,$Enc)
}

New-Item -ItemType Directory -Force -Path $RunRoot | Out-Null

Write-Utf8NoBomLf -Path (Join-Path $RunRoot "goal.txt") -Text "selftest context packet"
Write-Utf8NoBomLf -Path (Join-Path $RunRoot "language.txt") -Text "PowerShell"
Write-Utf8NoBomLf -Path (Join-Path $RunRoot "language_version.txt") -Text "5.1"
Write-Utf8NoBomLf -Path (Join-Path $RunRoot "project_repo.txt") -Text "C:\dev\nfl"

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_repo_link_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -TargetRepo "C:\dev\csl" `
  -Role "conformance-layer" | Out-Host

$ContextOut = @(
  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File (Join-Path $RepoRoot "scripts\pie_context_build_v1.ps1") `
    -RepoRoot $RepoRoot `
    -SessionId $SessionId `
    -UserMessage "what repos are in context?"
) -join "`n"

if($LASTEXITCODE -ne 0){
  throw "PIE_CONTEXT_SELFTEST_BUILD_FAIL"
}

$PromptPath = ""

foreach($Line in @($ContextOut -split "`n")){
  if($Line -like "PIE_CONTEXT_BUILD_OK:*"){
    $PromptPath = $Line.Substring("PIE_CONTEXT_BUILD_OK:".Length).Trim()
  }
}

if([string]::IsNullOrWhiteSpace($PromptPath)){
  throw "PIE_CONTEXT_SELFTEST_PROMPT_PATH_MISSING"
}

$Prompt = Get-Content -LiteralPath $PromptPath -Raw

if($Prompt -notmatch [regex]::Escape("C:\dev\nfl")){
  throw "PIE_CONTEXT_SELFTEST_PRIMARY_REPO_MISSING"
}

if($Prompt -notmatch [regex]::Escape("C:\dev\csl")){
  throw "PIE_CONTEXT_SELFTEST_LINKED_REPO_MISSING"
}

if($Prompt -notmatch "IMPORTANT PATH RULE"){
  throw "PIE_CONTEXT_SELFTEST_PATH_RULE_MISSING"
}

Write-Host "PIE_CONTEXT_SELFTEST_OK" -ForegroundColor Green
Write-Host ("prompt: " + $PromptPath)
