param(
  [Parameter(Mandatory=$false)][ValidateSet("status","start","install")][string]$Action = "status",
  [Parameter(Mandatory=$false)][string]$RepoRoot = "."
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

function Test-OllamaApi {
  try {
    $Response = Invoke-WebRequest -Uri "http://127.0.0.1:11434/api/tags" -UseBasicParsing -TimeoutSec 2
    return ($Response.StatusCode -eq 200)
  } catch { return $false }
}

function Get-OllamaCommand {
  $Command = Get-Command ollama -ErrorAction SilentlyContinue
  if($null -ne $Command){ return $Command.Source }
  $Candidate = Join-Path $env:LOCALAPPDATA "Programs\Ollama\ollama.exe"
  if(Test-Path -LiteralPath $Candidate -PathType Leaf){ return $Candidate }
  return ""
}

if($Action -eq "status"){
  $Ollama = Get-OllamaCommand
  Write-Host "PIE LOCAL RUNTIME" -ForegroundColor Cyan
  if([string]::IsNullOrWhiteSpace($Ollama)){
    Write-Host "installed: no"
    Write-Host "running: no"
    Write-Host "next: pie runtime install"
    return
  }
  Write-Host "installed: yes" -ForegroundColor Green
  Write-Host ("executable: " + $Ollama)
  $ConfigPath = Join-Path $RepoRoot "runs\runtime\config.json"
  if(Test-Path -LiteralPath $ConfigPath -PathType Leaf){
    try { Write-Host ("selected model: " + [string]((Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json).model)) }
    catch { Write-Host "selected model: invalid local config" -ForegroundColor Yellow }
  } else { Write-Host "selected model: none" }
  if(Test-OllamaApi){
    Write-Host "running: yes" -ForegroundColor Green
    try {
      $Running = Invoke-RestMethod -Method Get -Uri "http://127.0.0.1:11434/api/ps" -TimeoutSec 5
      if(@($Running.models).Count -eq 0){ Write-Host "loaded models: none" }
      foreach($Loaded in @($Running.models)){ Write-Host ("loaded: " + [string]$Loaded.name) }
    } catch { Write-Host ("loaded models: unavailable :: " + $_.Exception.Message) }
  }
  else { Write-Host "running: no"; Write-Host "next: pie runtime start" }
  return
}

if($Action -eq "start"){
  if([string]::IsNullOrWhiteSpace((Get-OllamaCommand))){ throw "PIE_OLLAMA_MISSING: run 'pie runtime install' first" }
  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $RepoRoot "scripts\pie_ollama_ensure_v1.ps1") | Out-Host
  if($LASTEXITCODE -ne 0){ throw "PIE_RUNTIME_START_FAIL" }
  Write-Host "PIE_RUNTIME_START_OK" -ForegroundColor Green
  return
}

$Winget = Get-Command winget -ErrorAction SilentlyContinue
if($null -eq $Winget){ throw "PIE_WINGET_MISSING: install Ollama from https://ollama.com/download/windows" }
Write-Host "PIE_RUNTIME_INSTALL_START: Ollama.Ollama" -ForegroundColor Cyan
& $Winget.Source install --id Ollama.Ollama --exact --accept-package-agreements --accept-source-agreements
if($LASTEXITCODE -ne 0){ throw "PIE_RUNTIME_INSTALL_FAIL" }
Write-Host "PIE_RUNTIME_INSTALL_OK" -ForegroundColor Green
Write-Host "next: open a new PowerShell window, then run 'pie runtime start'"
