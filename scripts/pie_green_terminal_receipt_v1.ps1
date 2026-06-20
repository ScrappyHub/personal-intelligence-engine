param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
Set-Location $RepoRoot

$OutRoot = Join-Path $RepoRoot "proofs\receipts\pie_green_terminal"
$Enc = New-Object System.Text.UTF8Encoding($false)

function Write-Utf8NoBomLf {
  param(
    [Parameter(Mandatory=$true)][string]$Path,
    [Parameter(Mandatory=$true)][AllowEmptyString()][string]$Text
  )

  $Dir = Split-Path -Parent $Path
  if($Dir -and -not (Test-Path -LiteralPath $Dir -PathType Container)){
    New-Item -ItemType Directory -Force -Path $Dir | Out-Null
  }

  $Clean = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $Clean.EndsWith("`n")){ $Clean += "`n" }

  [System.IO.File]::WriteAllText($Path,$Clean,$Enc)
}

function Get-JsonOrNull {
  param([string]$Path)

  if([string]::IsNullOrWhiteSpace($Path)){ return $null }
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ return $null }

  return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
}

function Invoke-Child {
  param(
    [Parameter(Mandatory=$true)][string]$Name,
    [Parameter(Mandatory=$true)][string]$ScriptPath,
    [Parameter(Mandatory=$true)][string]$SuccessToken
  )

  $StdoutPath = Join-Path $OutRoot ($Name + "_stdout.txt")
  $StderrPath = Join-Path $OutRoot ($Name + "_stderr.txt")

  $P = Start-Process -FilePath "powershell.exe" `
    -ArgumentList @(
      "-NoProfile",
      "-NonInteractive",
      "-ExecutionPolicy",
      "Bypass",
      "-File",
      $ScriptPath,
      "-RepoRoot",
      $RepoRoot
    ) `
    -Wait `
    -PassThru `
    -WindowStyle Hidden `
    -RedirectStandardOutput $StdoutPath `
    -RedirectStandardError $StderrPath

  $Stdout = [string]""
  $Stderr = [string]""

  if(Test-Path -LiteralPath $StdoutPath -PathType Leaf){
    $Stdout = [System.IO.File]::ReadAllText($StdoutPath,[System.Text.UTF8Encoding]::new($false))
  }

  if(Test-Path -LiteralPath $StderrPath -PathType Leaf){
    $Stderr = [System.IO.File]::ReadAllText($StderrPath,[System.Text.UTF8Encoding]::new($false))
  }

  if($P.ExitCode -ne 0){
    throw ("PIE_GREEN_TERMINAL_RECEIPT_CHILD_FAIL: " + $Name + " exit=" + [string]$P.ExitCode)
  }

  if($Stdout -notmatch [regex]::Escape($SuccessToken)){
    throw ("PIE_GREEN_TERMINAL_RECEIPT_CHILD_TOKEN_MISSING: " + $Name)
  }

  if(-not [string]::IsNullOrWhiteSpace($Stderr)){
    throw ("PIE_GREEN_TERMINAL_RECEIPT_CHILD_STDERR_NOT_EMPTY: " + $Name)
  }

  return [ordered]@{
    name = $Name
    script = $ScriptPath
    exit_code = [int]$P.ExitCode
    stdout_path = $StdoutPath
    stderr_path = $StderrPath
    stdout_bytes = $(if(Test-Path -LiteralPath $StdoutPath -PathType Leaf){ [int64](Get-Item -LiteralPath $StdoutPath).Length } else { 0 })
    stderr_bytes = $(if(Test-Path -LiteralPath $StderrPath -PathType Leaf){ [int64](Get-Item -LiteralPath $StderrPath).Length } else { 0 })
    success_token = $SuccessToken
  }
}

$ProofSuiteVerify = Join-Path $RepoRoot "scripts\verify_pie_green_proof_suite_v1.ps1"
$LockReceiptVerify = Join-Path $RepoRoot "scripts\verify_pie_green_lock_receipt_v1.ps1"

foreach($Required in @($ProofSuiteVerify,$LockReceiptVerify)){
  if(-not (Test-Path -LiteralPath $Required -PathType Leaf)){
    throw ("PIE_GREEN_TERMINAL_RECEIPT_REQUIRED_SCRIPT_MISSING: " + $Required)
  }

  $tok = $null
  $err = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Required,[ref]$tok,[ref]$err)
  if(@($err).Count -gt 0){
    throw ("PIE_GREEN_TERMINAL_RECEIPT_REQUIRED_SCRIPT_PARSE_FAIL: " + $Required + " :: " + $err[0].ToString())
  }
}

$Tracked = @(git -C $RepoRoot status --short --untracked-files=no)
if(@($Tracked).Count -gt 0){
  throw ("PIE_GREEN_TERMINAL_RECEIPT_REQUIRES_CLEAN_TREE: " + ($Tracked -join " | "))
}

New-Item -ItemType Directory -Force -Path $OutRoot | Out-Null

$HeadShort = ((git -C $RepoRoot rev-parse --short HEAD) -join "").Trim()
$HeadLong = ((git -C $RepoRoot rev-parse HEAD) -join "").Trim()
$Branch = ((git -C $RepoRoot rev-parse --abbrev-ref HEAD) -join "").Trim()
$Tag = "pie_green_lock_" + $HeadShort

$LocalTag = ((git -C $RepoRoot tag --list $Tag) -join "").Trim()
if([string]::IsNullOrWhiteSpace($LocalTag)){
  throw "PIE_GREEN_TERMINAL_RECEIPT_LOCAL_TAG_MISSING"
}

$TagTarget = ((git -C $RepoRoot rev-list -n 1 $Tag) -join "").Trim()
if($TagTarget -ne $HeadLong){
  throw ("PIE_GREEN_TERMINAL_RECEIPT_TAG_TARGET_BAD: " + $TagTarget + " != " + $HeadLong)
}

$RemoteTagLine = ((git -C $RepoRoot ls-remote --tags origin ("refs/tags/" + $Tag)) -join "").Trim()
if([string]::IsNullOrWhiteSpace($RemoteTagLine)){
  throw "PIE_GREEN_TERMINAL_RECEIPT_REMOTE_TAG_MISSING"
}

$LatestLockReceiptPath = Join-Path $RepoRoot "proofs\receipts\pie_green_lock\latest_pie_green_lock_receipt.json"
$LatestSnapshotPath = Join-Path $RepoRoot "proofs\receipts\pie_green_final_snapshot\latest_pie_green_final_snapshot.json"

$LockReceipt = Get-JsonOrNull -Path $LatestLockReceiptPath
$Snapshot = Get-JsonOrNull -Path $LatestSnapshotPath

if($null -eq $LockReceipt){
  throw "PIE_GREEN_TERMINAL_RECEIPT_LOCK_RECEIPT_MISSING"
}
if($null -eq $Snapshot){
  throw "PIE_GREEN_TERMINAL_RECEIPT_SNAPSHOT_MISSING"
}

if([string]$LockReceipt.schema -ne "pie.green.lock.receipt.v1"){
  throw ("PIE_GREEN_TERMINAL_RECEIPT_LOCK_RECEIPT_SCHEMA_BAD: " + [string]$LockReceipt.schema)
}
if([string]$LockReceipt.lock_tag -ne $Tag){
  throw ("PIE_GREEN_TERMINAL_RECEIPT_LOCK_TAG_BAD: " + [string]$LockReceipt.lock_tag + " != " + $Tag)
}
if([string]$LockReceipt.lock_commit -ne $HeadLong){
  throw ("PIE_GREEN_TERMINAL_RECEIPT_LOCK_COMMIT_BAD: " + [string]$LockReceipt.lock_commit + " != " + $HeadLong)
}

if([string]$Snapshot.schema -ne "pie.green.final.snapshot.v2"){
  throw ("PIE_GREEN_TERMINAL_RECEIPT_SNAPSHOT_SCHEMA_BAD: " + [string]$Snapshot.schema)
}
if(-not [bool]$Snapshot.git_status_clean){
  throw "PIE_GREEN_TERMINAL_RECEIPT_SNAPSHOT_NOT_CLEAN"
}
if([string]$Snapshot.commit -ne $HeadShort){
  throw ("PIE_GREEN_TERMINAL_RECEIPT_SNAPSHOT_COMMIT_BAD: " + [string]$Snapshot.commit + " != " + $HeadShort)
}

$ChildResults = @(
  [pscustomobject](Invoke-Child -Name "verify_green_proof_suite" -ScriptPath $ProofSuiteVerify -SuccessToken "PIE_GREEN_PROOF_SUITE_VERIFY_OK")
  [pscustomobject](Invoke-Child -Name "verify_green_lock_receipt" -ScriptPath $LockReceiptVerify -SuccessToken "PIE_GREEN_LOCK_RECEIPT_VERIFY_OK")
)

$Receipt = [ordered]@{
  schema = "pie.green.terminal.receipt.v1"
  created_utc = [DateTime]::UtcNow.ToString("o")
  repo_root = $RepoRoot
  branch = $Branch
  head_commit = $HeadShort
  head_commit_long = $HeadLong
  lock_tag = $Tag
  latest_lock_receipt_path = $LatestLockReceiptPath
  latest_final_snapshot_path = $LatestSnapshotPath
  child_count = @($ChildResults).Count
  children = @($ChildResults)
}

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
$OutPath = Join-Path $OutRoot ("pie_green_terminal_receipt_" + $Stamp + ".json")
$LatestPath = Join-Path $OutRoot "latest_pie_green_terminal_receipt.json"

$Json = $Receipt | ConvertTo-Json -Depth 50
Write-Utf8NoBomLf -Path $OutPath -Text $Json
Write-Utf8NoBomLf -Path $LatestPath -Text $Json

Write-Host "PIE_GREEN_TERMINAL_RECEIPT_OK" -ForegroundColor Green
Write-Host ("receipt: " + $OutPath)
