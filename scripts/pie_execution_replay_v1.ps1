param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$SessionId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)
$ReceiptPath = Join-Path $RunRoot "execution\execution_receipts.ndjson"
$ReplayRoot = Join-Path $RunRoot "replay"
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

function Get-Sha256OrEmpty {
  param([string]$Path)
  if(Test-Path -LiteralPath $Path -PathType Leaf){
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
  }
  return ""
}

if(-not (Test-Path -LiteralPath $RunRoot -PathType Container)){
  throw ("PIE_REPLAY_SESSION_NOT_FOUND: " + $SessionId)
}

if(-not (Test-Path -LiteralPath $ReceiptPath -PathType Leaf)){
  throw ("PIE_REPLAY_RECEIPTS_NOT_FOUND: " + $ReceiptPath)
}

$Receipts = New-Object System.Collections.Generic.List[object]
foreach($Line in @(Get-Content -LiteralPath $ReceiptPath -ErrorAction Stop)){
  if([string]::IsNullOrWhiteSpace($Line)){ continue }
  $Obj = $Line | ConvertFrom-Json
  [void]$Receipts.Add($Obj)
}

$Checks = New-Object System.Collections.Generic.List[object]
$Failures = New-Object System.Collections.Generic.List[string]

foreach($R in @($Receipts.ToArray())){
  $Stdout = [string]$R.stdout
  $Stderr = [string]$R.stderr
  $Proposal = [string]$R.proposal

  $StdoutExists = Test-Path -LiteralPath $Stdout -PathType Leaf
  $StderrExists = Test-Path -LiteralPath $Stderr -PathType Leaf
  $ProposalExists = $true

  if(-not [string]::IsNullOrWhiteSpace($Proposal)){
    $ProposalExists = Test-Path -LiteralPath $Proposal -PathType Leaf
  }

  if(-not $StdoutExists){ [void]$Failures.Add("MISSING_STDOUT: " + $Stdout) }
  if(-not $StderrExists){ [void]$Failures.Add("MISSING_STDERR: " + $Stderr) }
  if(-not $ProposalExists){ [void]$Failures.Add("MISSING_PROPOSAL: " + $Proposal) }

  $Check = [ordered]@{
    schema = "pie.execution.replay.check.v1"
    command = [string]$R.command
    exit_code = [int]$R.exit_code
    stdout = $Stdout
    stdout_exists = $StdoutExists
    stdout_sha256 = Get-Sha256OrEmpty $Stdout
    stderr = $Stderr
    stderr_exists = $StderrExists
    stderr_sha256 = Get-Sha256OrEmpty $Stderr
    proposal = $Proposal
    proposal_exists = $ProposalExists
    proposal_sha256 = Get-Sha256OrEmpty $Proposal
  }

  [void]$Checks.Add([pscustomobject]$Check)
}

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
$ReplayPath = Join-Path $ReplayRoot ("execution_replay_" + $Stamp + ".json")
$LatestPath = Join-Path $ReplayRoot "latest_execution_replay.json"

$Status = "PIE_EXECUTION_REPLAY_OK"
if(@($Failures.ToArray()).Count -gt 0){
  $Status = "PIE_EXECUTION_REPLAY_FAIL"
}

$Replay = [ordered]@{
  schema = "pie.execution.replay.v1"
  session_id = $SessionId
  status = $Status
  receipt_path = $ReceiptPath
  receipt_count = @($Receipts.ToArray()).Count
  checks = $Checks.ToArray()
  failures = $Failures.ToArray()
  non_mutating = $true
  created_utc = [DateTime]::UtcNow.ToString("o")
}

$Json = $Replay | ConvertTo-Json -Depth 40
Write-Utf8NoBomLf -Path $ReplayPath -Text $Json
Write-Utf8NoBomLf -Path $LatestPath -Text $Json

if($Status -ne "PIE_EXECUTION_REPLAY_OK"){
  Write-Host ("PIE_EXECUTION_REPLAY_FAIL: " + $ReplayPath) -ForegroundColor Red
  exit 2
}

Write-Host ("PIE_EXECUTION_REPLAY_OK: " + $ReplayPath) -ForegroundColor Green
