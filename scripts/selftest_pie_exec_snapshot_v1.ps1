param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$SessionId = "pie_exec_snapshot_selftest"
$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)
$WorkDir = Join-Path $RunRoot "work"
$AfterPath = Join-Path $WorkDir "after.txt"
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

if(Test-Path -LiteralPath $RunRoot -PathType Container){
  Remove-Item -LiteralPath $RunRoot -Recurse -Force
}

New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

Write-Utf8NoBomLf -Path (Join-Path $RunRoot "project_repo.txt") -Text $WorkDir
Write-Utf8NoBomLf -Path (Join-Path $WorkDir "before.txt") -Text "before"

$Cmd = 'Set-Content -LiteralPath ".\after.txt" -Value "after" -NoNewline'

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_exec_with_snapshot_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -Command $Cmd `
  -WorkingDirectory $WorkDir `
  -Confirm | Out-Host

if($LASTEXITCODE -ne 0){
  throw "PIE_EXEC_SNAPSHOT_SELFTEST_CHILD_FAIL"
}

if(-not (Test-Path -LiteralPath $AfterPath -PathType Leaf)){
  $LatestErr = Get-ChildItem -LiteralPath (Join-Path $RunRoot "execution") -Filter "stderr_*.txt" -File |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

  if($null -ne $LatestErr){
    Write-Host "LATEST_STDERR:" -ForegroundColor Yellow
    Get-Content -LiteralPath $LatestErr.FullName -Raw | Write-Host
  }

  throw "PIE_EXEC_SNAPSHOT_SELFTEST_AFTER_FILE_NOT_WRITTEN"
}

$AfterText = Get-Content -LiteralPath $AfterPath -Raw
if($AfterText.Trim() -ne "after"){
  throw "PIE_EXEC_SNAPSHOT_SELFTEST_AFTER_CONTENT_BAD"
}

$LatestSnapshot = Get-ChildItem -LiteralPath (Join-Path $RunRoot "snapshots") -Directory |
  Sort-Object Name -Descending |
  Select-Object -First 1

if($null -eq $LatestSnapshot){
  throw "PIE_EXEC_SNAPSHOT_SELFTEST_NO_SNAPSHOT"
}

$Diff = Join-Path $LatestSnapshot.FullName "diff_from_previous.json"

if(-not (Test-Path -LiteralPath $Diff -PathType Leaf)){
  throw "PIE_EXEC_SNAPSHOT_SELFTEST_DIFF_MISSING"
}

$DiffObj = Get-Content -LiteralPath $Diff -Raw | ConvertFrom-Json

if(-not (@($DiffObj.added) -contains "after.txt")){
  throw "PIE_EXEC_SNAPSHOT_SELFTEST_AFTER_NOT_ADDED"
}

Write-Host "PIE_EXEC_SNAPSHOT_SELFTEST_OK" -ForegroundColor Green
