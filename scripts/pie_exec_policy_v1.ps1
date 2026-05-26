param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$Command,
  [Parameter(Mandatory=$false)][string]$WorkingDirectory = "",
  [Parameter(Mandatory=$false)][string]$SessionProjectRepo = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$PolicyPath = Join-Path $RepoRoot "policies\PIE_EXEC_POLICY.v1.json"

if(-not (Test-Path -LiteralPath $PolicyPath -PathType Leaf)){
  throw ("PIE_EXEC_POLICY_MISSING: " + $PolicyPath)
}

$Policy = Get-Content -LiteralPath $PolicyPath -Raw | ConvertFrom-Json

function Get-CommandClass {
  param([string]$Command)

  $C = $Command.Trim().ToLowerInvariant()

  if($C -match '^(get-childitem|dir|ls|type|cat|get-content|select-string)\b'){ return "read_only" }
  if($C -match '^(git status|git log|git diff)\b'){ return "git_status" }
  if($C -match '^(write-output|echo)\b'){ return "diagnostic" }
  if($C -match '(selftest|test|parsefile|parse-gate)'){ return "selftest" }
  if($C -match '^git add\b'){ return "git_add" }
  if($C -match '^git commit\b'){ return "git_commit" }
  if($C -match '^git push\b'){ return "git_push" }
  if($C -match 'set-content|writealltext|out-file|new-item|copy-item|move-item'){ return "file_write" }
  if($C -match '\.ps1\b|powershell\.exe|pwsh'){ return "script_run" }
  if($C -match 'npm install|pip install|winget|choco|scoop'){ return "package_install" }

  return "unknown"
}

function Is-UnderPath {
  param(
    [Parameter(Mandatory=$true)][string]$Child,
    [Parameter(Mandatory=$true)][string]$Parent
  )

  if([string]::IsNullOrWhiteSpace($Child) -or [string]::IsNullOrWhiteSpace($Parent)){ return $false }

  $C = (Resolve-Path -LiteralPath $Child).Path.TrimEnd("\")
  $P = (Resolve-Path -LiteralPath $Parent).Path.TrimEnd("\")

  return ($C.Equals($P,[System.StringComparison]::OrdinalIgnoreCase) -or $C.StartsWith($P + "\",[System.StringComparison]::OrdinalIgnoreCase))
}

$Class = Get-CommandClass -Command $Command
$Decision = [string]$Policy.default_decision
$Reason = "DEFAULT_" + $Decision

$TrustLevel = "UNKNOWN"
if($null -ne $Policy.trust_levels.$Class){
  $TrustLevel = [string]$Policy.trust_levels.$Class
}

foreach($Pattern in @($Policy.deny_command_patterns)){
  if($Command.ToLowerInvariant() -match [string]$Pattern){
    $Decision = "DENY"
    $Reason = "DENY_PATTERN_MATCH"
    break
  }
}

if($Decision -ne "DENY"){
  if($Policy.repo_boundary.require_working_directory_exists -eq $true){
    if([string]::IsNullOrWhiteSpace($WorkingDirectory) -or -not (Test-Path -LiteralPath $WorkingDirectory -PathType Container)){
      $Decision = "DENY"
      $Reason = "WORKING_DIRECTORY_REQUIRED_OR_MISSING"
    }
  }
}

if($Decision -ne "DENY"){
  if($Policy.repo_boundary.require_working_directory_under_session_repo -eq $true){
    if(-not [string]::IsNullOrWhiteSpace($SessionProjectRepo)){
      if(Test-Path -LiteralPath $SessionProjectRepo -PathType Container){
        if(-not (Is-UnderPath -Child $WorkingDirectory -Parent $SessionProjectRepo)){
          $Decision = "DENY"
          $Reason = "WORKDIR_OUTSIDE_SESSION_REPO"
        }
      }
    }
  }
}

if($Decision -ne "DENY"){
  if(@($Policy.allow_classes) -contains $Class){
    $Decision = "ALLOW"
    $Reason = "ALLOW_CLASS_" + $Class.ToUpperInvariant()
  }
  elseif(@($Policy.ask_confirmation_classes) -contains $Class){
    $Decision = "ASK_CONFIRMATION"
    $Reason = "ASK_CLASS_" + $Class.ToUpperInvariant()
  }
}

$AutoConfirmAllowed = $false
if(@($Policy.allow_auto_confirm_for_classes) -contains $Class){
  if($Decision -eq "ALLOW"){
    $AutoConfirmAllowed = $true
  }
}

$Obj = [ordered]@{
  schema = "pie.exec.policy.decision.v2"
  command = $Command
  command_class = $Class
  trust_level = $TrustLevel
  working_directory = $WorkingDirectory
  session_project_repo = $SessionProjectRepo
  decision = $Decision
  reason_code = $Reason
  auto_confirm_allowed = $AutoConfirmAllowed
  created_utc = [DateTime]::UtcNow.ToString("o")
}

Write-Output ($Obj | ConvertTo-Json -Depth 12 -Compress)
