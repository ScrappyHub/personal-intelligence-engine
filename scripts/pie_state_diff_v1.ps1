param(
  [Parameter(Mandatory=$true)][string]$BeforeSnapshot,
  [Parameter(Mandatory=$true)][string]$AfterSnapshot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$BeforeSnapshot = (Resolve-Path -LiteralPath $BeforeSnapshot).Path
$AfterSnapshot = (Resolve-Path -LiteralPath $AfterSnapshot).Path
$Enc = New-Object System.Text.UTF8Encoding($false)

function Load-Inventory {
  param([string]$SnapshotPath)

  $S = Get-Content -LiteralPath $SnapshotPath -Raw | ConvertFrom-Json
  $InvPath = [string]$S.inventory

  if(-not (Test-Path -LiteralPath $InvPath -PathType Leaf)){
    throw ("PIE_DIFF_INVENTORY_MISSING: " + $InvPath)
  }

  $Map = @{}

  foreach($Line in @(Get-Content -LiteralPath $InvPath)){
    if([string]::IsNullOrWhiteSpace($Line)){ continue }
    $Obj = $Line | ConvertFrom-Json
    $Map[[string]$Obj.rel] = $Obj
  }

  return @{
    snapshot = $S
    map = $Map
  }
}

function Write-Utf8NoBomLf {
  param([string]$Path,[string]$Text)
  $Dir = Split-Path -Parent $Path
  if(-not (Test-Path -LiteralPath $Dir -PathType Container)){ New-Item -ItemType Directory -Force -Path $Dir | Out-Null }
  $Clean = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $Clean.EndsWith("`n")){ $Clean += "`n" }
  [System.IO.File]::WriteAllText($Path,$Clean,$Enc)
}

$B = Load-Inventory -SnapshotPath $BeforeSnapshot
$A = Load-Inventory -SnapshotPath $AfterSnapshot

$BeforeMap = $B.map
$AfterMap = $A.map

$Added = New-Object System.Collections.Generic.List[string]
$Removed = New-Object System.Collections.Generic.List[string]
$Changed = New-Object System.Collections.Generic.List[string]

foreach($Key in @($AfterMap.Keys | Sort-Object)){
  if(-not $BeforeMap.ContainsKey($Key)){
    [void]$Added.Add($Key)
  }
  elseif([string]$BeforeMap[$Key].sha256 -ne [string]$AfterMap[$Key].sha256){
    [void]$Changed.Add($Key)
  }
}

foreach($Key in @($BeforeMap.Keys | Sort-Object)){
  if(-not $AfterMap.ContainsKey($Key)){
    [void]$Removed.Add($Key)
  }
}

$OutDir = Split-Path -Parent $AfterSnapshot
$DiffPath = Join-Path $OutDir "diff_from_previous.json"

$Diff = [ordered]@{
  schema = "pie.state.diff.v1"
  before_snapshot = $BeforeSnapshot
  after_snapshot = $AfterSnapshot
  added = $Added.ToArray()
  removed = $Removed.ToArray()
  changed = $Changed.ToArray()
  added_count = @($Added.ToArray()).Count
  removed_count = @($Removed.ToArray()).Count
  changed_count = @($Changed.ToArray()).Count
  created_utc = [DateTime]::UtcNow.ToString("o")
}

Write-Utf8NoBomLf -Path $DiffPath -Text ($Diff | ConvertTo-Json -Depth 20)

Write-Host ("PIE_STATE_DIFF_OK: " + $DiffPath) -ForegroundColor Green
