param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$false)][int]$Iterations = 25
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$Message){
  throw $Message
}

function Ensure-Dir([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Container)){
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir){
    Ensure-Dir $dir
  }
  $enc = New-Object System.Text.UTF8Encoding($false)
  $t = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $t.EndsWith("`n")){
    $t += "`n"
  }
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$sealRoot = Join-Path $RepoRoot "proofs\runs\pie_runtime_seal_v1"
Ensure-Dir $sealRoot

Write-Host "PIE_RUNTIME_SEAL_V1_START" -ForegroundColor DarkCyan

& (Join-Path $RepoRoot "scripts\_selftest_pie_agent_offline_v1.ps1") `
  -RepoRoot $RepoRoot | Out-Host

& (Join-Path $RepoRoot "scripts\_selftest_pie_agent_external_v1.ps1") `
  -RepoRoot $RepoRoot | Out-Host

& (Join-Path $RepoRoot "scripts\_RUN_pie_agent_stress_v1.ps1") `
  -RepoRoot $RepoRoot `
  -Iterations $Iterations | Out-Host

& (Join-Path $RepoRoot "scripts\_RUN_pie_agent_external_stress_v1.ps1") `
  -RepoRoot $RepoRoot `
  -Iterations $Iterations | Out-Host

$receipt = @(
  "{"
  '"schema":"pie.runtime.seal.receipt.v1",'
  '"status":"GREEN",'
  '"token":"PIE_RUNTIME_SEAL_V1_GREEN",'
  ('"utc":"' + [DateTime]::UtcNow.ToString("o") + '",')
  ('"iterations":' + $Iterations)
  "}"
) -join ""

Write-Utf8NoBomLf (Join-Path $sealRoot "runtime_seal_receipt.json") $receipt

Write-Host "PIE_RUNTIME_SEAL_V1_GREEN" -ForegroundColor Green