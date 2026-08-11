param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$false)][ValidateSet("list","catalog","catalog-json","validate","pull","use","selected")][string]$Action = "list",
  [Parameter(Mandatory=$false)][string]$Model = "",
  [Parameter(Mandatory=$false)][switch]$SetDefault,
  [Parameter(Mandatory=$false)][string]$OllamaPath = "",
  [Parameter(Mandatory=$false)][string]$StatePath = "",
  [Parameter(Mandatory=$false)][string]$RegistryPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
if([string]::IsNullOrWhiteSpace($RegistryPath)){ $RegistryPath = Join-Path $RepoRoot "models\PIE_MODEL_REGISTRY.v1.json" }
if([string]::IsNullOrWhiteSpace($StatePath)){ $StatePath = Join-Path $RepoRoot "runs\runtime\config.json" }
$Enc = New-Object System.Text.UTF8Encoding($false)
$EventPath = Join-Path (Split-Path -Parent $StatePath) "events.ndjson"
$DownloadReceiptRoot = Join-Path (Split-Path -Parent $StatePath) "downloads"

function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $Dir = Split-Path -Parent $Path
  if(-not (Test-Path -LiteralPath $Dir -PathType Container)){ New-Item -ItemType Directory -Force -Path $Dir | Out-Null }
  $Clean = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $Clean.EndsWith("`n")){ $Clean += "`n" }
  [System.IO.File]::WriteAllText($Path,$Clean,$Enc)
}

function Add-RuntimeEvent([string]$EventName,[string]$ModelName){
  $Dir = Split-Path -Parent $EventPath
  if(-not (Test-Path -LiteralPath $Dir -PathType Container)){ New-Item -ItemType Directory -Force -Path $Dir | Out-Null }
  $Event = [ordered]@{
    schema = "pie.local.runtime.event.v1"
    event = $EventName
    backend = "ollama"
    model = $ModelName
    utc = [DateTime]::UtcNow.ToString("o")
  }
  [System.IO.File]::AppendAllText($EventPath,(($Event | ConvertTo-Json -Depth 8 -Compress) + "`n"),$Enc)
}

function Write-DownloadReceipt([string]$ModelName,[string]$Status,[string]$Detail,[string]$Digest = "",[int64]$Bytes = 0){
  if(-not (Test-Path -LiteralPath $DownloadReceiptRoot -PathType Container)){ New-Item -ItemType Directory -Force -Path $DownloadReceiptRoot | Out-Null }
  $SafeModel = $ModelName -replace '[^A-Za-z0-9._-]','_'
  $ReceiptPath = Join-Path $DownloadReceiptRoot ("model_" + $SafeModel + "_" + (Get-Date -Format "yyyyMMdd_HHmmss_fff") + ".json")
  $Receipt = [ordered]@{
    schema = "pie.model.download.receipt.v1"
    backend = "ollama"
    model = $ModelName
    status = $Status
    verified_local = ($Status -eq "complete")
    ollama_digest = $Digest
    bytes = $Bytes
    detail = $Detail
    completed_utc = [DateTime]::UtcNow.ToString("o")
  }
  Write-Utf8NoBomLf -Path $ReceiptPath -Text ($Receipt | ConvertTo-Json -Depth 8)
  return $ReceiptPath
}

function Resolve-Ollama {
  if(-not [string]::IsNullOrWhiteSpace($OllamaPath)){
    if(-not (Test-Path -LiteralPath $OllamaPath -PathType Leaf)){ throw ("PIE_OLLAMA_PATH_NOT_FOUND: " + $OllamaPath) }
    return (Resolve-Path -LiteralPath $OllamaPath).Path
  }
  $Command = Get-Command ollama -ErrorAction SilentlyContinue
  if($null -eq $Command){ throw "PIE_OLLAMA_MISSING: run 'pie runtime install', then 'pie runtime start'" }
  return $Command.Source
}

function Ensure-Ollama {
  if(-not [string]::IsNullOrWhiteSpace($OllamaPath)){ return }
  $EnsureScript = Join-Path $RepoRoot "scripts\pie_ollama_ensure_v1.ps1"
  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $EnsureScript | Out-Null
  if($LASTEXITCODE -ne 0){ throw "PIE_OLLAMA_ENSURE_FAIL" }
}

function Invoke-Ollama([string[]]$Arguments){
  $Exe = Resolve-Ollama
  $Output = @(& $Exe @Arguments)
  if($LASTEXITCODE -ne 0){ throw ("PIE_OLLAMA_COMMAND_FAIL: " + ($Arguments -join " ")) }
  return $Output
}

function Get-OllamaTags {
  if(-not [string]::IsNullOrWhiteSpace($OllamaPath)){
    $Names = New-Object System.Collections.Generic.List[object]
    foreach($Line in @(Invoke-Ollama -Arguments @("list"))){
      $Text = [string]$Line
      if([string]::IsNullOrWhiteSpace($Text) -or $Text -match "^NAME\s+"){ continue }
      $Parts = @($Text.Trim() -split "\s+")
      if($Parts.Count -gt 0){ [void]$Names.Add([pscustomobject]@{ name=$Parts[0]; size=0; modified_at="" }) }
    }
    return @($Names.ToArray())
  }

  Ensure-Ollama
  try {
    $Response = Invoke-RestMethod -Method Get -Uri "http://127.0.0.1:11434/api/tags" -TimeoutSec 10
    return @($Response.models)
  }
  catch { throw ("PIE_OLLAMA_TAGS_FAILED: " + $_.Exception.Message) }
}

function Pull-OllamaModel([string]$ModelName){
  if(-not [string]::IsNullOrWhiteSpace($OllamaPath)){
    foreach($Line in @(Invoke-Ollama -Arguments @("pull",$ModelName))){ Write-Output $Line }
    return
  }

  Ensure-Ollama
  Add-Type -AssemblyName System.Net.Http
  $Handler = New-Object System.Net.Http.HttpClientHandler
  $Client = New-Object System.Net.Http.HttpClient($Handler)
  $Client.Timeout = [TimeSpan]::FromHours(24)
  $Request = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Post,"http://127.0.0.1:11434/api/pull")
  $Body = @{ name=$ModelName; stream=$true } | ConvertTo-Json -Compress
  $Request.Content = New-Object System.Net.Http.StringContent($Body,[System.Text.Encoding]::UTF8,"application/json")
  $Succeeded = $false
  $Response = $null
  $Stream = $null
  $Reader = $null
  try {
    $Response = $Client.SendAsync($Request,[System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
    if(-not $Response.IsSuccessStatusCode){
      $ErrorBody = $Response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
      throw ("http_status=" + [int]$Response.StatusCode + " body=" + $ErrorBody)
    }
    $Stream = $Response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
    $Reader = New-Object System.IO.StreamReader($Stream,[System.Text.Encoding]::UTF8)
    while(-not $Reader.EndOfStream){
      $Line = $Reader.ReadLine()
      if([string]::IsNullOrWhiteSpace($Line)){ continue }
      try { $Progress = $Line | ConvertFrom-Json }
      catch { throw ("invalid_progress_json=" + $Line) }
      if(-not [string]::IsNullOrWhiteSpace([string]$Progress.error)){ throw ([string]$Progress.error) }
      $Status = [string]$Progress.status
      $Completed = 0L
      $Total = 0L
      if($null -ne $Progress.PSObject.Properties["completed"]){ $Completed = [int64]$Progress.completed }
      if($null -ne $Progress.PSObject.Properties["total"]){ $Total = [int64]$Progress.total }
      $Percent = 0
      if($Total -gt 0){ $Percent = [Math]::Min(100,[Math]::Floor(($Completed * 100.0) / $Total)) }
      Write-Output ("PIE_MODEL_PULL_PROGRESS: " + $ModelName + " status=" + $Status + " completed=" + $Completed + " total=" + $Total + " percent=" + $Percent)
      if($Status -eq "success"){ $Succeeded = $true }
    }
    if(-not $Succeeded){ throw "stream_ended_without_success" }
  }
  catch { throw ("PIE_OLLAMA_PULL_FAILED: " + $ModelName + " :: " + $_.Exception.Message) }
  finally {
    if($null -ne $Reader){ $Reader.Dispose() }
    if($null -ne $Stream){ $Stream.Dispose() }
    if($null -ne $Response){ $Response.Dispose() }
    $Request.Dispose()
    $Client.Dispose()
    $Handler.Dispose()
  }
}

function Get-SelectedModel {
  if(-not (Test-Path -LiteralPath $StatePath -PathType Leaf)){ return "" }
  try { return [string](([System.IO.File]::ReadAllText($StatePath,$Enc) | ConvertFrom-Json).model) }
  catch { throw ("PIE_RUNTIME_CONFIG_INVALID: " + $StatePath + " :: " + $_.Exception.Message) }
}

function Set-SelectedModel([string]$ModelName){
  $Config = [ordered]@{ schema="pie.local.runtime.config.v1"; backend="ollama"; model=$ModelName; updated_utc=[DateTime]::UtcNow.ToString("o") }
  Write-Utf8NoBomLf -Path $StatePath -Text ($Config | ConvertTo-Json -Depth 8)
  Add-RuntimeEvent -EventName "model_selected" -ModelName $ModelName
  Write-Host ("PIE_MODEL_SELECTED: " + $ModelName) -ForegroundColor Green
}

function Get-LocalModelNames {
  $Names = New-Object System.Collections.Generic.List[string]
  foreach($Tag in @(Get-OllamaTags)){
    if(-not [string]::IsNullOrWhiteSpace([string]$Tag.name)){ [void]$Names.Add([string]$Tag.name) }
  }
  return @($Names.ToArray())
}

function Get-ValidatedRegistry {
  if(-not (Test-Path -LiteralPath $RegistryPath -PathType Leaf)){ throw ("PIE_MODEL_REGISTRY_MISSING: " + $RegistryPath) }
  try { $Registry = [System.IO.File]::ReadAllText($RegistryPath,$Enc) | ConvertFrom-Json }
  catch { throw ("PIE_MODEL_REGISTRY_JSON_INVALID: " + $_.Exception.Message) }
  if([string]$Registry.schema -ne "pie.model.registry.v1"){ throw "PIE_MODEL_REGISTRY_SCHEMA_INVALID" }
  $Catalog = @($Registry.catalog)
  if($Catalog.Count -lt 1){ throw "PIE_MODEL_REGISTRY_CATALOG_EMPTY" }
  $Names = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  foreach($Entry in $Catalog){
    $Name = [string]$Entry.name
    if($Name -notmatch '^[A-Za-z0-9][A-Za-z0-9._/-]{0,127}(?::[A-Za-z0-9][A-Za-z0-9._-]{0,63})?$'){ throw ("PIE_MODEL_REGISTRY_NAME_INVALID: " + $Name) }
    if(-not $Names.Add($Name)){ throw ("PIE_MODEL_REGISTRY_NAME_DUPLICATE: " + $Name) }
    if([string]::IsNullOrWhiteSpace([string]$Entry.title) -or [string]::IsNullOrWhiteSpace([string]$Entry.purpose)){ throw ("PIE_MODEL_REGISTRY_DESCRIPTION_MISSING: " + $Name) }
    if([int64]$Entry.size_bytes -lt 100MB){ throw ("PIE_MODEL_REGISTRY_SIZE_INVALID: " + $Name) }
    if([int]$Entry.min_ram_gb -lt 1 -or [int]$Entry.context_tokens -lt 1024){ throw ("PIE_MODEL_REGISTRY_REQUIREMENTS_INVALID: " + $Name) }
    if(([string]$Entry.source) -notmatch '^https://(www\.)?ollama\.com/library/'){ throw ("PIE_MODEL_REGISTRY_SOURCE_INVALID: " + $Name) }
    if(@($Entry.modalities).Count -lt 1){ throw ("PIE_MODEL_REGISTRY_MODALITIES_MISSING: " + $Name) }
  }
  foreach($ProfileProperty in $Registry.profiles.PSObject.Properties){
    foreach($ProfileModel in @($ProfileProperty.Value.models)){
      if(-not $Names.Contains([string]$ProfileModel)){ throw ("PIE_MODEL_REGISTRY_PROFILE_MODEL_UNKNOWN: " + $ProfileProperty.Name + " :: " + [string]$ProfileModel) }
    }
  }
  return $Registry
}

switch($Action){
  "catalog" {
    $Registry = Get-ValidatedRegistry
    Write-Host "PIE MODEL CATALOG" -ForegroundColor Cyan
    foreach($Tier in @($Registry.catalog | Group-Object tier)){
      Write-Host ("[" + [string]$Tier.Name + "]")
      foreach($Entry in @($Tier.Group)){
        $SizeText = "{0:N1} GB" -f ([int64]$Entry.size_bytes / 1GB)
        Write-Host ("  " + [string]$Entry.name + "  " + $SizeText + "  " + [string]$Entry.title)
      }
    }
    return
  }
  "catalog-json" {
    $Registry = Get-ValidatedRegistry
    Write-Output ([ordered]@{ schema="pie.model.catalog.v1"; updated_utc=[string]$Registry.catalog_updated_utc; models=@($Registry.catalog) } | ConvertTo-Json -Depth 12 -Compress)
    return
  }
  "validate" {
    $Registry = Get-ValidatedRegistry
    Write-Host ("PIE_MODEL_REGISTRY_OK: " + @($Registry.catalog).Count + " models") -ForegroundColor Green
    return
  }
  "selected" {
    $Selected = Get-SelectedModel
    if([string]::IsNullOrWhiteSpace($Selected)){ Write-Host "PIE_MODEL_SELECTED: none" }
    else { Write-Host ("PIE_MODEL_SELECTED: " + $Selected) -ForegroundColor Green }
    return
  }
  "list" {
    $Selected = Get-SelectedModel
    Write-Host "PIE LOCAL MODELS" -ForegroundColor Cyan
    $Tags = @(Get-OllamaTags)
    if($Tags.Count -eq 0){ Write-Host "none downloaded" }
    foreach($Tag in $Tags){
      $Size = [int64]$Tag.size
      $SizeText = if($Size -gt 0){ ("{0:N1} GB" -f ($Size / 1GB)) } else { "unknown size" }
      Write-Host ("  " + [string]$Tag.name + "  " + $SizeText)
    }
    if([string]::IsNullOrWhiteSpace($Selected)){ Write-Host "selected: none (use 'pie models use -Model <name>')" }
    else { Write-Host ("selected: " + $Selected) -ForegroundColor Green }
    return
  }
  "pull" {
    if([string]::IsNullOrWhiteSpace($Model)){ throw "PIE_CLI_MODEL_REQUIRED" }
    Write-Host ("PIE_MODEL_PULL_START: " + $Model) -ForegroundColor Cyan
    try {
      Pull-OllamaModel -ModelName $Model
      $DownloadedTag = @(Get-OllamaTags | Where-Object { [string]$_.name -eq $Model } | Select-Object -First 1)
      if($DownloadedTag.Count -eq 0){
        throw ("PIE_MODEL_PULL_VERIFY_FAILED: " + $Model + " was not reported by the local Ollama registry after download")
      }
      $Digest = ""
      $DownloadedBytes = 0L
      if($null -ne $DownloadedTag[0].PSObject.Properties["digest"]){ $Digest = [string]$DownloadedTag[0].digest }
      if($null -ne $DownloadedTag[0].PSObject.Properties["size"]){ $DownloadedBytes = [int64]$DownloadedTag[0].size }
      Add-RuntimeEvent -EventName "model_pulled" -ModelName $Model
      $ReceiptPath = Write-DownloadReceipt -ModelName $Model -Status "complete" -Detail "verified in local Ollama registry" -Digest $Digest -Bytes $DownloadedBytes
      Write-Host ("PIE_MODEL_PULL_OK: " + $Model) -ForegroundColor Green
      Write-Host ("receipt: " + $ReceiptPath)
      if($SetDefault){ Set-SelectedModel -ModelName $Model }
    }
    catch {
      [void](Write-DownloadReceipt -ModelName $Model -Status "failed" -Detail $_.Exception.Message)
      throw
    }
    return
  }
  "use" {
    if([string]::IsNullOrWhiteSpace($Model)){ throw "PIE_CLI_MODEL_REQUIRED" }
    if(-not (@(Get-LocalModelNames) -contains $Model)){ throw ("PIE_MODEL_NOT_LOCAL: " + $Model + " (run 'pie pull -Model " + $Model + "')") }
    Set-SelectedModel -ModelName $Model
    return
  }
}
