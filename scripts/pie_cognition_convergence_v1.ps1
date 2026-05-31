param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$GraphLog = Join-Path $RepoRoot "memory\cognition_graph\cognition_graph.ndjson"
$OutRoot = Join-Path $RepoRoot "memory\cognition_convergence"
$OutPath = Join-Path $OutRoot "cognition_convergence.latest.json"
$Enc = New-Object System.Text.UTF8Encoding($false)

function Write-Utf8NoBomLf {
  param([string]$Path,[string]$Text)

  $Dir = Split-Path -Parent $Path

  if(-not (Test-Path -LiteralPath $Dir -PathType Container)){
    New-Item -ItemType Directory -Force -Path $Dir | Out-Null
  }

  $Clean = $Text.Replace("`r`n","`n").Replace("`r","`n")

  if(-not $Clean.EndsWith("`n")){
    $Clean += "`n"
  }

  [System.IO.File]::WriteAllText($Path,$Clean,$Enc)
}

$Stats = @{}

if(Test-Path -LiteralPath $GraphLog -PathType Leaf){

  foreach($Line in @(Get-Content -LiteralPath $GraphLog)){
    if([string]::IsNullOrWhiteSpace($Line)){ continue }

    $Obj = $Line | ConvertFrom-Json
    $Key = [string]$Obj.sequence_key

    if([string]::IsNullOrWhiteSpace($Key)){ continue }

    if(-not $Stats.ContainsKey($Key)){
      $Stats[$Key] = [ordered]@{
        sequence_key = $Key
        success = 0
        partial = 0
        failure = 0
        score = 0
        verdict = "unknown"
      }
    }

    if([string]$Obj.outcome -eq "success"){
      $Stats[$Key].success = [int]$Stats[$Key].success + 1
      $Stats[$Key].score = [int]$Stats[$Key].score + 10
    }
    elseif([string]$Obj.outcome -eq "partial"){
      $Stats[$Key].partial = [int]$Stats[$Key].partial + 1
      $Stats[$Key].score = [int]$Stats[$Key].score + 2
    }
    elseif([string]$Obj.outcome -eq "failure"){
      $Stats[$Key].failure = [int]$Stats[$Key].failure + 1
      $Stats[$Key].score = [int]$Stats[$Key].score - 8
    }
  }
}

$Rows = New-Object System.Collections.Generic.List[object]

foreach($Key in @($Stats.Keys | Sort-Object)){
  $S = $Stats[$Key]
  $Total = [int]$S.success + [int]$S.partial + [int]$S.failure

  $Verdict = "unstable"
  if([int]$S.success -ge 2 -and [int]$S.failure -eq 0){
    $Verdict = "convergent"
  }
  elseif([int]$S.failure -ge 1 -and [int]$S.score -lt 1){
    $Verdict = "suppressed"
  }
  elseif([int]$S.success -ge 1 -and [int]$S.score -gt 0){
    $Verdict = "promising"
  }

  $S.verdict = $Verdict

  [void]$Rows.Add([pscustomobject][ordered]@{
    sequence_key = [string]$S.sequence_key
    success = [int]$S.success
    partial = [int]$S.partial
    failure = [int]$S.failure
    total = $Total
    score = [int]$S.score
    verdict = $Verdict
  })
}

$Promoted = @($Rows.ToArray() | Where-Object { $_.verdict -eq "convergent" } | Sort-Object @{ Expression="score"; Descending=$true }, sequence_key)
$Suppressed = @($Rows.ToArray() | Where-Object { $_.verdict -eq "suppressed" } | Sort-Object sequence_key)

$Result = [ordered]@{
  schema = "pie.cognition.convergence.v1"
  source = $GraphLog
  sequence_count = @($Rows.ToArray()).Count
  promoted_count = @($Promoted).Count
  suppressed_count = @($Suppressed).Count
  rows = $Rows.ToArray()
  promoted = $Promoted
  suppressed = $Suppressed
  created_utc = [DateTime]::UtcNow.ToString("o")
}

Write-Utf8NoBomLf -Path $OutPath -Text ($Result | ConvertTo-Json -Depth 40)

Write-Host ("PIE_COGNITION_CONVERGENCE_OK: " + $OutPath) -ForegroundColor Green
