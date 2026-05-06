param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$false)][string]$Mode = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$PolicyPath = Join-Path $RepoRoot "memory\policy.json"
$Enc = New-Object System.Text.UTF8Encoding($false)

if(-not (Test-Path -LiteralPath $PolicyPath -PathType Leaf)){
  throw ("PIE_MEMORY_POLICY_MISSING: " + $PolicyPath)
}

$Policy = Get-Content -LiteralPath $PolicyPath -Raw | ConvertFrom-Json

if([string]::IsNullOrWhiteSpace($Mode)){
  Write-Host ("PIE_MEMORY_POLICY_MODE: " + $Policy.mode) -ForegroundColor Green
  return
}

$Allowed = @($Policy.allowed_modes)
if($Allowed -notcontains $Mode){
  throw ("PIE_MEMORY_POLICY_MODE_INVALID: " + $Mode)
}

$Policy.mode = $Mode
$Json = $Policy | ConvertTo-Json -Depth 12
[System.IO.File]::WriteAllText($PolicyPath, ($Json.Replace("`r`n","`n") + "`n"), $Enc)

Write-Host ("PIE_MEMORY_POLICY_SET_OK: " + $Mode) -ForegroundColor Green