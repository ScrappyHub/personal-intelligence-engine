param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$false)][string]$Model = "qwen2.5-coder:7b",
  [Parameter(Mandatory=$false)][int]$Iterations = 2,
  [Parameter(Mandatory=$false)][switch]$PullMissing
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
  $Dir = Split-Path -Parent $Path
  if($Dir){
    Ensure-Dir $Dir
  }

  $Clean = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $Clean.EndsWith("`n")){
    $Clean += "`n"
  }

  $Enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path,$Clean,$Enc)
}

function Get-SafeName([string]$Value){
  return ($Value -replace '[^a-zA-Z0-9._-]','_')
}

function Get-TrialPrompt([object]$Trial){
  $TrialId = [string]$Trial.trial_id

  if($Trial.PSObject.Properties.Name -contains "prompt"){
    $PromptValue = [string]$Trial.prompt
    if(-not [string]::IsNullOrWhiteSpace($PromptValue)){
      return $PromptValue
    }
  }

  if($TrialId -eq "ps_strictmode_scalar_count_v1"){
    return "In Windows PowerShell 5.1 with Set-StrictMode -Version Latest, explain why scalar .Count is risky and show the safe @(@(...)).Count pattern."
  }

  if($TrialId -eq "packet_optionA_manifest_rule_v1"){
    return "Summarize Packet Constitution v1 Option A: explain why manifest.json MUST NOT contain packet_id and how packet_id.txt is computed from SHA-256."
  }

  return ("Answer this PIE benchmark trial precisely: " + $TrialId)
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

if($Iterations -lt 1){
  Die "PIE_MODEL_MATRIX_ITERATIONS_MUST_BE_GE_1"
}

$TrialsPath = Join-Path $RepoRoot "benchmarks\workbench_trials_v1\trials.jsonl"
if(-not (Test-Path -LiteralPath $TrialsPath -PathType Leaf)){
  Die ("PIE_MODEL_MATRIX_TRIALS_MISSING: " + $TrialsPath)
}

$BackendScript = Join-Path $RepoRoot "scripts\pie_backend_ollama_cmd_v1.ps1"
if(-not (Test-Path -LiteralPath $BackendScript -PathType Leaf)){
  Die ("PIE_MODEL_MATRIX_BACKEND_MISSING: " + $BackendScript)
}

if($PullMissing){
  Write-Host ("PIE_MODEL_MATRIX_PULL_START: " + $Model) -ForegroundColor Cyan
  & ollama pull $Model
  if($LASTEXITCODE -ne 0){
    Die ("PIE_MODEL_MATRIX_PULL_FAIL: " + $Model)
  }
  Write-Host ("PIE_MODEL_MATRIX_PULL_OK: " + $Model) -ForegroundColor Green
}

$Stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss_fff")
$BenchmarkRoot = Join-Path $RepoRoot ("benchmarks\model_matrix\" + $Stamp)
$ModelDir = Join-Path $BenchmarkRoot (Get-SafeName $Model)
$PromptDir = Join-Path $ModelDir "prompts"
Ensure-Dir $PromptDir

$Trials = New-Object System.Collections.Generic.List[object]
foreach($Line in @(Get-Content -LiteralPath $TrialsPath)){
  if([string]::IsNullOrWhiteSpace($Line)){
    continue
  }
  [void]$Trials.Add(($Line | ConvertFrom-Json -ErrorAction Stop))
}

if(@($Trials).Count -lt 1){
  Die "PIE_MODEL_MATRIX_NO_TRIALS"
}

$Total = 0
$Ok = 0
$Fail = 0

Write-Host "PIE_MODEL_MATRIX_STRESS_START" -ForegroundColor Cyan
Write-Host ("benchmark_root: " + $BenchmarkRoot)
Write-Host ("model: " + $Model)
Write-Host ("iterations: " + [string]$Iterations)

for($Iteration = 1; $Iteration -le $Iterations; $Iteration++){
  foreach($Trial in @($Trials)){
    $Total++
    $TrialId = [string]$Trial.trial_id
    $BaseName = $TrialId + "_iter" + $Iteration
    $PromptPath = Join-Path $PromptDir ($BaseName + ".prompt.txt")
    $StdoutPath = Join-Path $PromptDir ($BaseName + ".stdout.txt")
    $StderrPath = Join-Path $PromptDir ($BaseName + ".stderr.txt")
    $ResultPath = Join-Path $ModelDir ($BaseName + ".txt")
    $PromptText = Get-TrialPrompt -Trial $Trial

    Write-Utf8NoBomLf $PromptPath $PromptText

    $Started = Get-Date
    $ExitCode = 1
    $StdoutText = ""
    $StderrText = ""

    try {
      $Output = @(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $BackendScript -Model $Model -MessagePath $PromptPath 2> $StderrPath)
      $ExitCode = $LASTEXITCODE
      $StdoutText = ($Output -join "`n")
      Write-Utf8NoBomLf $StdoutPath $StdoutText
      if(Test-Path -LiteralPath $StderrPath -PathType Leaf){
        $StderrText = Get-Content -LiteralPath $StderrPath -Raw
      }
    }
    catch {
      $ExitCode = 1
      $StderrText = $_.Exception.Message
      Write-Utf8NoBomLf $StderrPath $StderrText
      Write-Utf8NoBomLf $StdoutPath $StdoutText
    }

    $ElapsedMs = [int](((Get-Date) - $Started).TotalMilliseconds)
    $Passed = ($ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($StdoutText))

    if($Passed){
      foreach($Needle in @($Trial.must_include)){
        if($StdoutText.IndexOf([string]$Needle,[System.StringComparison]::OrdinalIgnoreCase) -lt 0){
          $Passed = $false
        }
      }
    }

    if($Passed){
      $Ok++
    }
    else {
      $Fail++
    }

    $Result = @(
      "schema: pie.model_matrix.result.v1",
      ("model: " + $Model),
      ("trial_id: " + $TrialId),
      ("iteration: " + [string]$Iteration),
      ("exit_code: " + [string]$ExitCode),
      ("passed: " + $(if($Passed){ "true" } else { "false" })),
      ("elapsed_ms: " + [string]$ElapsedMs),
      ("prompt_path: " + $PromptPath),
      ("stdout_path: " + $StdoutPath),
      ("stderr_path: " + $StderrPath),
      "",
      "response:",
      $StdoutText.Trim(),
      "",
      "stderr:",
      $StderrText.Trim()
    )

    Write-Utf8NoBomLf $ResultPath (($Result -join "`n") + "`n")
  }
}

$Summary = @(
  "schema: pie.model_matrix.summary.v1",
  ("model: " + $Model),
  ("total: " + [string]$Total),
  ("ok: " + [string]$Ok),
  ("fail: " + [string]$Fail),
  ("created_utc: " + [DateTime]::UtcNow.ToString("o"))
)
Write-Utf8NoBomLf (Join-Path $ModelDir "summary.txt") (($Summary -join "`n") + "`n")

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_benchmark_score_v1.ps1") `
  -RepoRoot $RepoRoot `
  -BenchmarkRoot $BenchmarkRoot | Out-Host

if($Fail -ne 0){
  Die ("PIE_MODEL_MATRIX_STRESS_FAIL ok=" + $Ok + " fail=" + $Fail + " root=" + $BenchmarkRoot)
}

Write-Host ("PIE_MODEL_MATRIX_STRESS_OK: " + $BenchmarkRoot) -ForegroundColor Green
