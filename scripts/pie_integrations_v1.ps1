param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$false)][ValidateSet("status","verify")][string]$Action = "status",
  [Parameter(Mandatory=$false)][ValidateSet("all","supabase","figma","vercel","cloudflare")][string]$Provider = "all",
  [Parameter(Mandatory=$false)][ValidateRange(1,300)][int]$TimeoutSeconds = 15
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Enc = New-Object System.Text.UTF8Encoding($false)
$ReceiptPath = Join-Path $RepoRoot "runs\integrations\integration_checks.ndjson"

$Definitions = [ordered]@{
  supabase = [ordered]@{
    token_env = "SUPABASE_ACCESS_TOKEN"
    context_env = @("SUPABASE_URL","SUPABASE_ANON_KEY","SUPABASE_SERVICE_ROLE_KEY")
    cli = "supabase"
    uri = "https://api.supabase.com/v1/projects"
  }
  figma = [ordered]@{
    token_env = "FIGMA_ACCESS_TOKEN"
    context_env = @()
    cli = ""
    uri = "https://api.figma.com/v1/me"
  }
  vercel = [ordered]@{
    token_env = "VERCEL_TOKEN"
    context_env = @("VERCEL_TEAM_ID")
    cli = "vercel"
    uri = "https://api.vercel.com/v2/user"
  }
  cloudflare = [ordered]@{
    token_env = "CLOUDFLARE_API_TOKEN"
    context_env = @("CLOUDFLARE_ACCOUNT_ID","CLOUDFLARE_ZONE_ID")
    cli = "wrangler"
    uri = "https://api.cloudflare.com/client/v4/user/tokens/verify"
  }
}

function Test-Configured {
  param([Parameter(Mandatory=$true)][string]$Name)
  return -not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($Name,"Process"))
}

function Append-IntegrationReceipt {
  param(
    [Parameter(Mandatory=$true)][string]$Name,
    [Parameter(Mandatory=$true)][string]$Status,
    [Parameter(Mandatory=$true)][string]$Detail
  )

  $Dir = Split-Path -Parent $ReceiptPath
  if(-not (Test-Path -LiteralPath $Dir -PathType Container)){ New-Item -ItemType Directory -Force -Path $Dir | Out-Null }
  $Receipt = [ordered]@{
    schema = "pie.integration.check.receipt.v1"
    provider = $Name
    action = "verify"
    status = $Status
    detail = $Detail
    created_utc = [DateTime]::UtcNow.ToString("o")
  }
  [System.IO.File]::AppendAllText($ReceiptPath,(($Receipt | ConvertTo-Json -Depth 8 -Compress) + "`n"),$Enc)
}

function Get-SelectedProviders {
  if($Provider -eq "all"){ return @($Definitions.Keys) }
  return @($Provider)
}

function Write-ProviderStatus {
  param([Parameter(Mandatory=$true)][string]$Name)

  $Definition = $Definitions[$Name]
  $AuthStatus = $(if(Test-Configured -Name $Definition.token_env){ "configured" } else { "missing" })
  $CliStatus = "not-required"
  if(-not [string]::IsNullOrWhiteSpace($Definition.cli)){
    $CliStatus = $(if($null -ne (Get-Command $Definition.cli -ErrorAction SilentlyContinue)){ "installed" } else { "missing" })
  }

  Write-Host ($Name + ": auth=" + $AuthStatus + " cli=" + $CliStatus) -ForegroundColor $(if($AuthStatus -eq "configured"){ "Green" } else { "Yellow" })
  Write-Host ("  " + $Definition.token_env + ": " + $AuthStatus)
  foreach($ContextName in @($Definition.context_env)){
    $ContextStatus = $(if(Test-Configured -Name $ContextName){ "configured" } else { "missing" })
    Write-Host ("  " + $ContextName + ": " + $ContextStatus)
  }
}

function Invoke-ProviderVerification {
  param([Parameter(Mandatory=$true)][string]$Name)

  $Definition = $Definitions[$Name]
  if(-not (Test-Configured -Name $Definition.token_env)){
    Append-IntegrationReceipt -Name $Name -Status "unavailable" -Detail ("missing " + $Definition.token_env)
    Write-Host ("PIE_INTEGRATION_UNAVAILABLE: " + $Name + " missing " + $Definition.token_env) -ForegroundColor Yellow
    return $false
  }

  $Token = [Environment]::GetEnvironmentVariable($Definition.token_env,"Process")
  $Headers = @{ Authorization = ("Bearer " + $Token) }
  if($Name -eq "figma"){
    $Headers = @{ "X-Figma-Token" = $Token }
  }

  try {
    $Response = Invoke-WebRequest -Method Get -Uri $Definition.uri -Headers $Headers -UseBasicParsing -TimeoutSec $TimeoutSeconds
    $Body = $Response.Content | ConvertFrom-Json

    if($Name -eq "figma" -and -not ($Body.PSObject.Properties.Name -contains "id")){ throw "FIGMA_ID_MISSING" }
    if($Name -eq "vercel" -and -not ($Body.PSObject.Properties.Name -contains "user")){ throw "VERCEL_USER_MISSING" }
    if($Name -eq "cloudflare"){
      if(-not [bool]$Body.success -or [string]$Body.result.status -ne "active"){ throw "CLOUDFLARE_TOKEN_NOT_ACTIVE" }
    }

    Append-IntegrationReceipt -Name $Name -Status "ok" -Detail ("http " + [string]$Response.StatusCode)
    Write-Host ("PIE_INTEGRATION_VERIFY_OK: " + $Name) -ForegroundColor Green
    return $true
  }
  catch {
    $Detail = $_.Exception.Message
    Append-IntegrationReceipt -Name $Name -Status "failed" -Detail $Detail
    Write-Host ("PIE_INTEGRATION_VERIFY_FAIL: " + $Name + " :: " + $Detail) -ForegroundColor Red
    return $false
  }
}

$Selected = @(Get-SelectedProviders)

if($Action -eq "status"){
  Write-Host "PIE INTEGRATIONS" -ForegroundColor Cyan
  foreach($Name in $Selected){ Write-ProviderStatus -Name $Name }
  Write-Host "PIE_INTEGRATIONS_STATUS_OK" -ForegroundColor Green
  return
}

$Failures = 0
foreach($Name in $Selected){
  if(-not (Invoke-ProviderVerification -Name $Name)){ $Failures += 1 }
}

if($Failures -gt 0){
  Write-Host ("PIE_INTEGRATIONS_SETUP_REQUIRED: " + $Failures + " provider(s) unavailable or invalid") -ForegroundColor Yellow
  exit 2
}
Write-Host "PIE_INTEGRATIONS_VERIFY_OK" -ForegroundColor Green
