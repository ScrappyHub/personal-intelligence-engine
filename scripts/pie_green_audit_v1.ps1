param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$CliPath = Join-Path $RepoRoot "pie.ps1"
$ManifestPath = Join-Path $RepoRoot "docs\PIE_GREEN_COMMANDS.manifest.json"
$DocPath = Join-Path $RepoRoot "docs\PIE_GREEN_COMMANDS.md"
$RunnerPath = Join-Path $RepoRoot "scripts\GOVERNANCE_GREEN_RUNNER_PIE_v1.ps1"

function Fail {
  param([string]$Code,[string]$Detail = "")
  if([string]::IsNullOrWhiteSpace($Detail)){
    throw $Code
  }
  throw ($Code + ": " + $Detail)
}

function Quote-Arg {
  param([Parameter(Mandatory=$true)][string]$Value)
  return '"' + ($Value.Replace('\','\\').Replace('"','\"')) + '"'
}

function Invoke-PieGreenSmoke {
  param(
    [Parameter(Mandatory=$true)][string]$Name,
    [Parameter(Mandatory=$true)][string]$Mode
  )

  $Args = @(
    "-NoProfile",
    "-NonInteractive",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    $CliPath,
    "green",
    $Mode
  )

  $Psi = [System.Diagnostics.ProcessStartInfo]::new()
  $Psi.FileName = "powershell.exe"
  $Psi.UseShellExecute = $false
  $Psi.CreateNoWindow = $true
  $Psi.RedirectStandardOutput = $true
  $Psi.RedirectStandardError = $true
  $Psi.Arguments = (($Args | ForEach-Object { Quote-Arg ([string]$_) }) -join " ")

  $P = [System.Diagnostics.Process]::new()
  $P.StartInfo = $Psi

  [void]$P.Start()
  $Stdout = [string]$P.StandardOutput.ReadToEnd()
  $Stderr = [string]$P.StandardError.ReadToEnd()
  $P.WaitForExit()

  $Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
  $TempRoot = Join-Path $env:TEMP "pie_green_audit"
  New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null

  $OutFile = Join-Path $TempRoot ($Name + "_stdout.txt")
  $ErrFile = Join-Path $TempRoot ($Name + "_stderr.txt")

  [System.IO.File]::WriteAllText($OutFile,($Stdout.Replace("`r`n","`n").Replace("`r","`n")),$Utf8NoBom)
  [System.IO.File]::WriteAllText($ErrFile,($Stderr.Replace("`r`n","`n").Replace("`r","`n")),$Utf8NoBom)

  return [ordered]@{
    name = $Name
    mode = $Mode
    exit_code = [int]$P.ExitCode
    stdout_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $OutFile).Hash.ToLowerInvariant()
    stderr_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $ErrFile).Hash.ToLowerInvariant()
    stdout_first_1000 = $(if($Stdout.Length -gt 1000){ $Stdout.Substring(0,1000) } else { $Stdout })
    stderr_first_1000 = $(if($Stderr.Length -gt 1000){ $Stderr.Substring(0,1000) } else { $Stderr })
  }
}

foreach($RequiredFile in @($CliPath,$ManifestPath,$DocPath,$RunnerPath)){
  if(-not (Test-Path -LiteralPath $RequiredFile -PathType Leaf)){
    Fail "PIE_GREEN_AUDIT_REQUIRED_FILE_MISSING" $RequiredFile
  }
}

foreach($ScriptFile in @($CliPath,$RunnerPath)){
  $tok=$null
  $err=$null
  [void][System.Management.Automation.Language.Parser]::ParseFile($ScriptFile,[ref]$tok,[ref]$err)
  if(@($err).Count -gt 0){
    Fail "PIE_GREEN_AUDIT_PARSE_FAIL" ($ScriptFile + " :: " + $err[0].ToString())
  }
}

$Branch = ((git -C $RepoRoot rev-parse --abbrev-ref HEAD) -join "").Trim()
$Commit = ((git -C $RepoRoot rev-parse --short HEAD) -join "").Trim()
$GitStatus = @(git -C $RepoRoot status --short)

$Manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
$ManifestCommands = @($Manifest.commands | ForEach-Object { [string]$_.command })

$ExpectedCommands = @(
  "pie green status",
  "pie green list",
  "pie green evidence",
  "pie green manifest",
  "pie green audit",
  "pie green governance",
  "pie green governance-full",
  "pie green full"
)

$Findings = @()

foreach($Cmd in $ExpectedCommands){
  if($ManifestCommands -notcontains $Cmd){
    $Findings += [ordered]@{ code = "MANIFEST_COMMAND_MISSING"; detail = $Cmd }
  }
}

foreach($Cmd in $ManifestCommands){
  if($ExpectedCommands -notcontains $Cmd){
    $Findings += [ordered]@{ code = "MANIFEST_COMMAND_UNEXPECTED"; detail = $Cmd }
  }
}

$CliRaw = Get-Content -LiteralPath $CliPath -Raw
foreach($Mode in @("status","list","evidence","manifest","audit","governance","governance-full","full")){
  $Needle = 'if($ModeArg -eq "' + $Mode + '")'
  if($CliRaw -notlike ("*" + $Needle + "*")){
    $Findings += [ordered]@{ code = "CLI_ROUTE_MISSING"; detail = $Needle }
  }
}

$Smokes = @(
  Invoke-PieGreenSmoke -Name "manifest" -Mode "manifest"
  Invoke-PieGreenSmoke -Name "list" -Mode "list"
  Invoke-PieGreenSmoke -Name "evidence" -Mode "evidence"
  Invoke-PieGreenSmoke -Name "status" -Mode "status"
)

foreach($S in $Smokes){
  if($S.exit_code -ne 0){
    $Findings += [ordered]@{ code = "SMOKE_FAIL"; detail = ($S.name + " exit=" + [string]$S.exit_code) }
  }
}

$OutDir = Join-Path $RepoRoot "runs\green_audit"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
$OutPath = Join-Path $OutDir ("green_audit_" + $Stamp + ".json")
$LatestPath = Join-Path $OutDir "latest_green_audit.json"

$Audit = [ordered]@{
  schema = "pie.green.audit.v1"
  created_utc = [DateTime]::UtcNow.ToString("o")
  repo_root = $RepoRoot
  branch = $Branch
  commit = $Commit
  git_status_clean = (@($GitStatus).Count -eq 0)
  git_status = @($GitStatus)
  manifest_schema = [string]$Manifest.schema
  manifest_command_count = @($Manifest.commands).Count
  manifest_commands = @($ManifestCommands)
  expected_commands = @($ExpectedCommands)
  smoke = @($Smokes)
  finding_count = @($Findings).Count
  findings = @($Findings)
}

$Json = $Audit | ConvertTo-Json -Depth 50
$Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$Clean = $Json.Replace("`r`n","`n").Replace("`r","`n")
if(-not $Clean.EndsWith("`n")){ $Clean += "`n" }

[System.IO.File]::WriteAllText($OutPath,$Clean,$Utf8NoBom)
[System.IO.File]::WriteAllText($LatestPath,$Clean,$Utf8NoBom)

if(@($Findings).Count -gt 0){
  Write-Host "PIE_GREEN_AUDIT_FINDINGS" -ForegroundColor Yellow
  Write-Host ("audit: " + $OutPath)
  Write-Host ("finding_count: " + [string]@($Findings).Count)
  foreach($F in $Findings){
    Write-Host ("- " + $F.code + " :: " + $F.detail)
  }
  exit 1
}

Write-Host "PIE_GREEN_AUDIT_OK" -ForegroundColor Green
Write-Host ("audit: " + $OutPath)
Write-Host ("latest: " + $LatestPath)
Write-Host ("commands: " + [string]@($Manifest.commands).Count)
