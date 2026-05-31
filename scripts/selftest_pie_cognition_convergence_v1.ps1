param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$GraphRoot = Join-Path $RepoRoot "memory\cognition_graph"
$GraphLog = Join-Path $GraphRoot "cognition_graph.ndjson"
$ConvPath = Join-Path $RepoRoot "memory\cognition_convergence\cognition_convergence.latest.json"
$Enc = New-Object System.Text.UTF8Encoding($false)

New-Item -ItemType Directory -Force -Path $GraphRoot | Out-Null

$Seed1 = [ordered]@{
  schema = "pie.cognition.graph.entry.v1"
  goal = "convergence selftest"
  sequence = @("repo.status","repo.diff")
  sequence_key = "repo.status -> repo.diff"
  outcome = "success"
  evidence = "seed convergence success 1"
  created_utc = [DateTime]::UtcNow.ToString("o")
}

$Seed2 = [ordered]@{
  schema = "pie.cognition.graph.entry.v1"
  goal = "convergence selftest"
  sequence = @("repo.status","repo.diff")
  sequence_key = "repo.status -> repo.diff"
  outcome = "success"
  evidence = "seed convergence success 2"
  created_utc = [DateTime]::UtcNow.ToString("o")
}

[System.IO.File]::AppendAllText($GraphLog,(($Seed1 | ConvertTo-Json -Depth 20 -Compress) + "`n"),$Enc)
[System.IO.File]::AppendAllText($GraphLog,(($Seed2 | ConvertTo-Json -Depth 20 -Compress) + "`n"),$Enc)

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cognition_convergence_v1.ps1") `
  -RepoRoot $RepoRoot | Out-Host

if($LASTEXITCODE -ne 0){
  throw "PIE_COG_CONVERGENCE_CHILD_FAIL"
}

if(-not (Test-Path -LiteralPath $ConvPath -PathType Leaf)){
  throw "PIE_COG_CONVERGENCE_OUTPUT_MISSING"
}

$Obj = Get-Content -LiteralPath $ConvPath -Raw | ConvertFrom-Json

if($Obj.promoted_count -lt 1){
  throw "PIE_COG_CONVERGENCE_EXPECT_PROMOTED"
}

$Hit = $false
foreach($P in @($Obj.promoted)){
  if([string]$P.sequence_key -eq "repo.status -> repo.diff"){
    $Hit = $true
  }
}

if(-not $Hit){
  throw "PIE_COG_CONVERGENCE_PROMOTED_SEQUENCE_MISSING"
}

Write-Host "PIE_COGNITION_CONVERGENCE_SELFTEST_OK" -ForegroundColor Green
