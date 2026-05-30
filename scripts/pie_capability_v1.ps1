param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$SessionId,
  [Parameter(Mandatory=$true)][string]$CapabilityId,
  [Parameter(Mandatory=$false)][switch]$Confirm,
  [Parameter(Mandatory=$false)][switch]$AutoConfirmAllowed
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)
$RegistryPath = Join-Path $RepoRoot "policies\PIE_CAPABILITY_REGISTRY.v1.json"

if(-not (Test-Path -LiteralPath $RunRoot -PathType Container)){
  throw ("PIE_CAPABILITY_SESSION_NOT_FOUND: " + $SessionId)
}

if(-not (Test-Path -LiteralPath $RegistryPath -PathType Leaf)){
  throw ("PIE_CAPABILITY_REGISTRY_MISSING: " + $RegistryPath)
}

$Registry = Get-Content -LiteralPath $RegistryPath -Raw | ConvertFrom-Json
$Capability = $null

foreach($C in @($Registry.capabilities)){
  if([string]$C.id -eq $CapabilityId){
    $Capability = $C
    break
  }
}

if($null -eq $Capability){
  throw ("PIE_CAPABILITY_NOT_FOUND: " + $CapabilityId)
}

$ProjectRepoFile = Join-Path $RunRoot "project_repo.txt"
$ProjectRepo = ""

if(Test-Path -LiteralPath $ProjectRepoFile -PathType Leaf){
  $ProjectRepo = (Get-Content -LiteralPath $ProjectRepoFile -Raw).Trim()
}

$WorkingDirectory = $RepoRoot

if([string]$Capability.scope -eq "session_repo"){
  if([string]::IsNullOrWhiteSpace($ProjectRepo)){
    throw "PIE_CAPABILITY_SESSION_REPO_REQUIRED"
  }

  if(-not (Test-Path -LiteralPath $ProjectRepo -PathType Container)){
    throw ("PIE_CAPABILITY_SESSION_REPO_MISSING: " + $ProjectRepo)
  }

  $WorkingDirectory = (Resolve-Path -LiteralPath $ProjectRepo).Path
}

if([string]$Capability.scope -eq "pie_repo"){
  $WorkingDirectory = $RepoRoot
}

$Command = [string]$Capability.command_template

$Exec = Join-Path $RepoRoot "scripts\pie_exec_with_snapshot_v1.ps1"
if(-not (Test-Path -LiteralPath $Exec -PathType Leaf)){
  $Exec = Join-Path $RepoRoot "scripts\pie_exec_v1.ps1"
}

$Args = @(
  "-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass",
  "-File",$Exec,
  "-RepoRoot",$RepoRoot,
  "-SessionId",$SessionId,
  "-Command",$Command,
  "-WorkingDirectory",$WorkingDirectory
)

if($Confirm){ $Args += "-Confirm" }
if($AutoConfirmAllowed){ $Args += "-AutoConfirmAllowed" }

Write-Host ("PIE_CAPABILITY_SELECTED: " + $CapabilityId) -ForegroundColor Cyan
Write-Host ("working_directory: " + $WorkingDirectory)
Write-Host ("command: " + $Command)

& powershell.exe @Args | Out-Host

if($LASTEXITCODE -ne 0){
  throw ("PIE_CAPABILITY_EXEC_FAIL: " + $CapabilityId)
}

Write-Host ("PIE_CAPABILITY_OK: " + $CapabilityId) -ForegroundColor Green
