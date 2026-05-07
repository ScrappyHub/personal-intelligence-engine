param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$Text,
  [Parameter(Mandatory=$false)][string]$Lane = "active",
  [Parameter(Mandatory=$false)][string]$Project = "",
  [Parameter(Mandatory=$false)][string]$ProjectRepo = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Utf8NoBomLf {
  param(
    [Parameter(Mandatory=$true)][string]$Path,
    [Parameter(Mandatory=$true)][string]$Text
  )

  $Enc = New-Object System.Text.UTF8Encoding($false)
  $Clean = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $Clean.EndsWith("`n")){ $Clean += "`n" }

  $Dir = Split-Path -Parent $Path
  if(-not (Test-Path -LiteralPath $Dir -PathType Container)){
    New-Item -ItemType Directory -Force -Path $Dir | Out-Null
  }

  [System.IO.File]::WriteAllText($Path,$Clean,$Enc)
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

# ------------------------------------------------------------
# POLICY DECISION
# ------------------------------------------------------------

$PolicyScript = Join-Path $RepoRoot "scripts\pie_policy_decide_v1.ps1"

if(-not (Test-Path -LiteralPath $PolicyScript -PathType Leaf)){
  throw "PIE_POLICY_SCRIPT_MISSING"
}

$TmpRoot = Join-Path $RepoRoot "runs\_policy_tmp"
New-Item -ItemType Directory -Force -Path $TmpRoot | Out-Null

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
$OutLog = Join-Path $TmpRoot ("memory_policy_stdout_" + $Stamp + ".txt")
$ErrLog = Join-Path $TmpRoot ("memory_policy_stderr_" + $Stamp + ".txt")

$ArgList = @(
  "-NoProfile",
  "-NonInteractive",
  "-ExecutionPolicy","Bypass",
  "-File",$PolicyScript,
  "-RepoRoot",$RepoRoot,
  "-Event","memory_accept",
  "-Project",$Project,
  "-Text",$Text
)

$Proc = Start-Process `
  -FilePath "powershell.exe" `
  -ArgumentList $ArgList `
  -NoNewWindow `
  -Wait `
  -PassThru `
  -RedirectStandardOutput $OutLog `
  -RedirectStandardError $ErrLog

$PolicyOut = ""
$PolicyErr = ""

if(Test-Path -LiteralPath $OutLog -PathType Leaf){
  $PolicyOut = Get-Content -LiteralPath $OutLog -Raw
}

if(Test-Path -LiteralPath $ErrLog -PathType Leaf){
  $PolicyErr = Get-Content -LiteralPath $ErrLog -Raw
}

if($Proc.ExitCode -ne 0){
  if(-not [string]::IsNullOrWhiteSpace($PolicyErr)){
    Write-Host $PolicyErr -ForegroundColor Red
  }
  throw ("PIE_POLICY_DECISION_FAIL_EXIT_" + [string]$Proc.ExitCode)
}

$DecisionLine = @(
  ($PolicyOut -split "`n") | Where-Object {
    $_ -like "PIE_POLICY_DECISION:*"
  }
)

if(@($DecisionLine).Count -lt 1){
  Write-Host $PolicyOut
  throw "PIE_POLICY_DECISION_OUTPUT_MISSING"
}

$DecisionText = [string]$DecisionLine[0]

$Decision = ""
$Reason = ""

if($DecisionText -match 'PIE_POLICY_DECISION:\s*([A-Z_]+)\s*reason_code=([A-Z0-9_]+)'){
  $Decision = [string]$Matches[1]
  $Reason = [string]$Matches[2]
} else {
  throw "PIE_POLICY_DECISION_PARSE_FAIL"
}

Write-Host ("PIE_MEMORY_POLICY_DECISION: " + $Decision + " reason_code=" + $Reason) -ForegroundColor Cyan

switch($Decision){

  "DENY" {
    throw ("PIE_MEMORY_DENIED: " + $Reason)
  }

  "WARN" {
    Write-Host ("PIE_MEMORY_WARNING: " + $Reason) -ForegroundColor Yellow
  }

  "ASK_CONFIRMATION" {
    $DecisionPathLine = @(
      ($PolicyOut -split "`n") | Where-Object {
        $_ -like "decision_path:*"
      }
    )

    if(@($DecisionPathLine).Count -gt 0){
      Write-Host ([string]$DecisionPathLine[0])
    }

    Write-Host "Memory requires confirmation." -ForegroundColor Yellow
    $Answer = Read-Host "Accept memory? (Y/N)"

    if(([string]$Answer).Trim().ToUpperInvariant() -ne "Y"){
      throw "PIE_MEMORY_CONFIRMATION_DECLINED"
    }
  }

  "ALLOW" { }

  default {
    throw ("PIE_MEMORY_UNKNOWN_POLICY_DECISION: " + $Decision)
  }
}

# ------------------------------------------------------------
# MEMORY WRITE
# ------------------------------------------------------------

$MemoryRoot = Join-Path $RepoRoot "memory"

switch($Lane){

  "active" {
    $TargetDir = Join-Path $MemoryRoot "active"
  }

  "coding" {
    $TargetDir = Join-Path $MemoryRoot "coding"
  }

  "project" {
    if([string]::IsNullOrWhiteSpace($Project)){
      throw "PIE_PROJECT_MEMORY_REQUIRES_PROJECT"
    }

    $ProjectSafe = ($Project -replace '[^a-zA-Z0-9._-]','_')
    $TargetDir = Join-Path $MemoryRoot ("projects\" + $ProjectSafe)
  }

  default {
    throw ("PIE_MEMORY_UNKNOWN_LANE: " + $Lane)
  }
}

New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null

$MemoryPath = Join-Path $TargetDir "memory.ndjson"

$Obj = [ordered]@{
  schema = "pie.memory.record.v1"
  lane = $Lane
  project = $Project
  project_repo = $ProjectRepo
  text = $Text
  policy_decision = $Decision
  policy_reason_code = $Reason
  created_utc = [DateTime]::UtcNow.ToString("o")
}

$Json = $Obj | ConvertTo-Json -Depth 8 -Compress

[System.IO.File]::AppendAllText(
  $MemoryPath,
  ($Json + "`n"),
  (New-Object System.Text.UTF8Encoding($false))
)

Write-Host ("PIE_MEMORY_ACCEPT_OK: " + $MemoryPath) -ForegroundColor Green