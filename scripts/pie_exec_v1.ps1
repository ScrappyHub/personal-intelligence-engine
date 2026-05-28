param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$SessionId,
  [Parameter(Mandatory=$true)][string]$Command,
  [Parameter(Mandatory=$false)][string]$WorkingDirectory = "",
  [Parameter(Mandatory=$false)][switch]$Confirm,
  [Parameter(Mandatory=$false)][switch]$AutoConfirmAllowed
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)
$ExecRoot = Join-Path $RunRoot "execution"
$SessionProjectRepoFile = Join-Path $RunRoot "project_repo.txt"
$SessionProjectRepo = ""
$Enc = New-Object System.Text.UTF8Encoding($false)

function Write-Utf8NoBomLf {
  param(
    [Parameter(Mandatory=$true)][string]$Path,
    [Parameter(Mandatory=$true)][AllowEmptyString()][string]$Text
  )

  $Dir = Split-Path -Parent $Path
  if(-not (Test-Path -LiteralPath $Dir -PathType Container)){
    New-Item -ItemType Directory -Force -Path $Dir | Out-Null
  }

  $Clean = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $Clean.EndsWith("`n")){ $Clean += "`n" }

  [System.IO.File]::WriteAllText($Path,$Clean,$Enc)
}

if(-not (Test-Path -LiteralPath $RunRoot -PathType Container)){
  throw ("PIE_EXEC_SESSION_NOT_STARTED: " + $SessionId)
}

if(Test-Path -LiteralPath $SessionProjectRepoFile -PathType Leaf){
  $SessionProjectRepo = (Get-Content -LiteralPath $SessionProjectRepoFile -Raw).Trim()
}

if([string]::IsNullOrWhiteSpace($WorkingDirectory)){
  $WorkingDirectory = $SessionProjectRepo
}

if([string]::IsNullOrWhiteSpace($WorkingDirectory)){
  $WorkingDirectory = $RepoRoot
}

if(-not (Test-Path -LiteralPath $WorkingDirectory -PathType Container)){
  throw ("PIE_EXEC_WORKDIR_NOT_FOUND: " + $WorkingDirectory)
}

$WorkingDirectory = (Resolve-Path -LiteralPath $WorkingDirectory).Path

$PolicyScript = Join-Path $RepoRoot "scripts\pie_exec_policy_v1.ps1"

if(-not (Test-Path -LiteralPath $PolicyScript -PathType Leaf)){
  throw ("PIE_EXEC_POLICY_SCRIPT_MISSING: " + $PolicyScript)
}

$PolicyJson = @(
  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File $PolicyScript `
    -RepoRoot $RepoRoot `
    -Command $Command `
    -WorkingDirectory $WorkingDirectory `
    -SessionProjectRepo $SessionProjectRepo
) -join "`n"

if($LASTEXITCODE -ne 0){
  throw "PIE_EXEC_POLICY_EVAL_FAIL"
}

$PolicyDecision = $PolicyJson | ConvertFrom-Json

$Decision = [string]$PolicyDecision.decision
$BlockReason = [string]$PolicyDecision.reason_code
$CommandClass = [string]$PolicyDecision.command_class

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
$ProposalPath = Join-Path $ExecRoot ("proposal_" + $Stamp + ".json")
$StdoutPath = Join-Path $ExecRoot ("stdout_" + $Stamp + ".txt")
$StderrPath = Join-Path $ExecRoot ("stderr_" + $Stamp + ".txt")
$ReceiptPath = Join-Path $ExecRoot "execution_receipts.ndjson"
$ChildScriptPath = Join-Path $ExecRoot ("child_exec_" + $Stamp + ".ps1")
$CommandPath = Join-Path $ExecRoot ("command_" + $Stamp + ".txt")

Write-Utf8NoBomLf -Path $CommandPath -Text $Command

$Proposal = [ordered]@{
  schema = "pie.execution.proposal.v1"
  session_id = $SessionId
  command = $Command
  command_path = $CommandPath
  working_directory = $WorkingDirectory
  decision = $Decision
  reason_code = $BlockReason
  command_class = $CommandClass
  trust_level = [string]$PolicyDecision.trust_level
  auto_confirm_allowed = [bool]$PolicyDecision.auto_confirm_allowed
  session_project_repo = $SessionProjectRepo
  policy_decision = $PolicyDecision
  stdout = $StdoutPath
  stderr = $StderrPath
  child_script = $ChildScriptPath
  created_utc = [DateTime]::UtcNow.ToString("o")
}

Write-Utf8NoBomLf -Path $ProposalPath -Text ($Proposal | ConvertTo-Json -Depth 12)

if($Decision -eq "DENY"){
  Write-Host ("PIE_EXEC_DENY: " + $BlockReason) -ForegroundColor Red
  Write-Host ("proposal: " + $ProposalPath)
  exit 3
}

if((-not $Confirm) -and -not ($AutoConfirmAllowed -and [bool]$PolicyDecision.auto_confirm_allowed)){
  Write-Host "PIE_EXEC_PROPOSAL_CREATED" -ForegroundColor Yellow
  Write-Host ("proposal: " + $ProposalPath)
  Write-Host "Re-run with -Confirm to execute."

  if([bool]$PolicyDecision.auto_confirm_allowed){
    Write-Host "Auto-confirm is allowed for this command class only if -AutoConfirmAllowed is provided."
  }

  exit 0
}

$WdJson = $WorkingDirectory | ConvertTo-Json -Compress
$CommandPathJson = $CommandPath | ConvertTo-Json -Compress

$ChildScript = @"
Set-StrictMode -Version Latest
`$ErrorActionPreference = "Stop"

`$__pie_workdir = $WdJson
`$__pie_command_path = $CommandPathJson

if(-not (Test-Path -LiteralPath `$__pie_workdir -PathType Container)){
  throw ("PIE_CHILD_WORKDIR_MISSING: " + `$__pie_workdir)
}

if(-not (Test-Path -LiteralPath `$__pie_command_path -PathType Leaf)){
  throw ("PIE_CHILD_COMMAND_PATH_MISSING: " + `$__pie_command_path)
}

Set-Location -LiteralPath `$__pie_workdir

`$__pie_command = Get-Content -LiteralPath `$__pie_command_path -Raw
Invoke-Expression `$__pie_command
"@

Write-Utf8NoBomLf -Path $ChildScriptPath -Text $ChildScript

$tok=$null
$err=$null
[void][System.Management.Automation.Language.Parser]::ParseFile($ChildScriptPath,[ref]$tok,[ref]$err)

if(@($err).Count -gt 0){
  throw ("PIE_EXEC_CHILD_PARSE_FAIL: " + $err[0].ToString())
}

$Proc = Start-Process `
  -FilePath "powershell.exe" `
  -ArgumentList @("-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass","-File",$ChildScriptPath) `
  -WorkingDirectory $WorkingDirectory `
  -NoNewWindow `
  -PassThru `
  -RedirectStandardOutput $StdoutPath `
  -RedirectStandardError $StderrPath

$TimeoutSeconds = 120

if(-not $Proc.WaitForExit($TimeoutSeconds * 1000)){
  try { $Proc.Kill() } catch { }
  throw ("PIE_EXEC_TIMEOUT stdout=" + $StdoutPath + " stderr=" + $StderrPath)
}

$Proc.Refresh()

$ExitCodeText = [string]$Proc.ExitCode
if([string]::IsNullOrWhiteSpace($ExitCodeText)){
  $ExitCodeText = "0"
}

$ExitCode = [int]$ExitCodeText

$Receipt = [ordered]@{
  schema = "pie.execution.receipt.v1"
  session_id = $SessionId
  command = $Command
  command_path = $CommandPath
  working_directory = $WorkingDirectory
  exit_code = $ExitCode
  stdout = $StdoutPath
  stderr = $StderrPath
  proposal = $ProposalPath
  child_script = $ChildScriptPath
  created_utc = [DateTime]::UtcNow.ToString("o")
}

[System.IO.File]::AppendAllText($ReceiptPath,(($Receipt | ConvertTo-Json -Depth 12 -Compress) + "`n"),$Enc)

if($ExitCode -ne 0){
  throw ("PIE_EXEC_FAIL: exit=" + [string]$ExitCode + " stdout=" + $StdoutPath + " stderr=" + $StderrPath)
}

Write-Host "PIE_EXEC_OK" -ForegroundColor Green
Write-Host ("stdout: " + $StdoutPath)
Write-Host ("stderr: " + $StderrPath)
exit 0
