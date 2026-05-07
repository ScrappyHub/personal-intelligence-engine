param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Pie = Join-Path $RepoRoot "pie.ps1"

if(-not (Test-Path -LiteralPath $Pie -PathType Leaf)){
  throw "PIE_CLI_MISSING"
}

$RequiredScripts = @(
  "pie_attach_v1.ps1",
  "pie_ask_v1.ps1",
  "pie_agent_send_v1.ps1",
  "pie_agent_start_v1.ps1",
  "pie_agent_stop_v1.ps1",
  "pie_vision_ollama_v1.ps1",
  "pie_vision_correct_v1.ps1",
  "pie_project_detect_v1.ps1",
  "pie_benchmark_score_v1.ps1",
  "pie_show_results_v1.ps1",
  "pie_verify_init_v1.ps1"
)

foreach($ScriptName in $RequiredScripts){
  $ScriptPath = Join-Path $RepoRoot ("scripts\" + $ScriptName)

  if(-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)){
    throw ("PIE_RUNTIME_SCRIPT_MISSING: " + $ScriptName)
  }

  $tok = $null
  $err = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($ScriptPath,[ref]$tok,[ref]$err)

  if(@($err).Count -gt 0){
    throw ("PIE_RUNTIME_PARSE_FAIL: " + $ScriptName + " :: " + $err[0].ToString())
  }
}

$tok2 = $null
$err2 = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($Pie,[ref]$tok2,[ref]$err2)

if(@($err2).Count -gt 0){
  throw ("PIE_CLI_PARSE_FAIL: " + $err2[0].ToString())
}

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Pie help -RepoRoot $RepoRoot | Out-Host
if($LASTEXITCODE -ne 0){ throw "PIE_HELP_FAIL" }

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Pie memory -RepoRoot $RepoRoot | Out-Host
if($LASTEXITCODE -ne 0){ throw "PIE_MEMORY_HELP_FAIL" }

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Pie verify -RepoRoot $RepoRoot -TargetRepo $RepoRoot | Out-Host
if($LASTEXITCODE -ne 0){ throw "PIE_VERIFY_INIT_FAIL" }

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Pie detect -RepoRoot $RepoRoot -TargetRepo $RepoRoot | Out-Host
if($LASTEXITCODE -ne 0){ throw "PIE_DETECT_FAIL" }

$Readme = Join-Path $RepoRoot "README.md"
if(Test-Path -LiteralPath $Readme -PathType Leaf){
  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Pie attach -RepoRoot $RepoRoot -SessionId "runtime_green" -Path $Readme | Out-Host
  if($LASTEXITCODE -ne 0){ throw "PIE_ATTACH_FAIL" }

  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Pie ask -RepoRoot $RepoRoot -SessionId "runtime_green" -Text "What file is attached? Answer briefly." | Out-Host
  if($LASTEXITCODE -ne 0){ throw "PIE_ASK_FAIL" }
}

$BenchRoot = Join-Path $RepoRoot "benchmarks\model_matrix"
if(Test-Path -LiteralPath $BenchRoot -PathType Container){
  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Pie score -RepoRoot $RepoRoot | Out-Host
  if($LASTEXITCODE -ne 0){ throw "PIE_SCORE_FAIL" }

  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Pie show -RepoRoot $RepoRoot -Scorecard | Out-Host
  if($LASTEXITCODE -ne 0){ throw "PIE_SHOW_FAIL" }
}

Write-Host "PIE_RUNTIME_GREEN_OK" -ForegroundColor Green
