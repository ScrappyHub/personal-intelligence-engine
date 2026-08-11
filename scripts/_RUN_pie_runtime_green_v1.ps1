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
  "pie_agent_status_v1.ps1",
  "pie_agent_history_v1.ps1",
  "pie_agent_list_v1.ps1",
  "pie_haai_capture_v1.ps1",
  "pie_session_backup_v1.ps1",
  "pie_doctor_v1.ps1",
  "_lib_pie_agent_session_v1.ps1",
  "_lib_pie_response_grounding_v1.ps1",
  "pie_capability_list_v1.ps1",
  "pie_exec_policy_v1.ps1",
  "pie_exec_v1.ps1",
  "pie_exec_with_snapshot_v1.ps1",
  "selftest_pie_agent_workflow_v1.ps1",
  "selftest_pie_agent_session_contract_v1.ps1",
  "selftest_pie_chat_recall_v1.ps1",
  "selftest_pie_haai_adapter_v1.ps1",
  "selftest_pie_haai_project_v1.ps1",
  "selftest_pie_session_backup_v1.ps1",
  "selftest_pie_doctor_v1.ps1",
  "selftest_pie_drift_boundaries_v1.ps1",
  "selftest_pie_agent_timeout_retry_v1.ps1",
  "selftest_pie_context_repo_facts_v1.ps1",
  "selftest_pie_response_grounding_v1.ps1",
  "_lib_pie_memory_v1.ps1",
  "pie_memory_accept_v1.ps1",
  "pie_memory_resolve_v1.ps1",
  "pie_memory_query_v1.ps1",
  "pie_memory_forget_v1.ps1",
  "pie_context_build_v1.ps1",
  "selftest_pie_memory_resolve_v1.ps1",
  "selftest_pie_memory_negative_v1.ps1",
  "selftest_pie_memory_lifecycle_v1.ps1",
  "pie_models_v1.ps1",
  "pie_runtime_v1.ps1",
  "pie_integrations_v1.ps1",
  "pie_workbench_v1.ps1",
  "selftest_pie_workbench_v1.ps1",
  "selftest_pie_desktop_v1.ps1",
  "verify_pie_desktop_release_v1.ps1",
  "pie_hosted_build_v1.ps1",
  "selftest_pie_hosted_build_v1.ps1",
  "pie_package_v1.ps1",
  "selftest_pie_install_v1.ps1",
  "selftest_pie_integrations_v1.ps1",
  "selftest_pie_local_models_v1.ps1",
  "selftest_pie_model_registry_v1.ps1",
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

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\selftest_pie_doctor_v1.ps1") `
  -RepoRoot $RepoRoot | Out-Host
if($LASTEXITCODE -ne 0){ throw "PIE_DOCTOR_SELFTEST_FAIL" }

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\selftest_pie_local_models_v1.ps1") `
  -RepoRoot $RepoRoot | Out-Host
if($LASTEXITCODE -ne 0){ throw "PIE_LOCAL_MODELS_SELFTEST_FAIL" }

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\selftest_pie_model_registry_v1.ps1") `
  -RepoRoot $RepoRoot | Out-Host
if($LASTEXITCODE -ne 0){ throw "PIE_MODEL_REGISTRY_SELFTEST_FAIL" }

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\selftest_pie_integrations_v1.ps1") `
  -RepoRoot $RepoRoot | Out-Host
if($LASTEXITCODE -ne 0){ throw "PIE_INTEGRATIONS_SELFTEST_FAIL" }

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\selftest_pie_workbench_v1.ps1") `
  -RepoRoot $RepoRoot | Out-Host
if($LASTEXITCODE -ne 0){ throw "PIE_WORKBENCH_SELFTEST_FAIL" }

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\selftest_pie_desktop_v1.ps1") `
  -RepoRoot $RepoRoot | Out-Host
if($LASTEXITCODE -ne 0){ throw "PIE_DESKTOP_SELFTEST_FAIL" }

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\selftest_pie_hosted_build_v1.ps1") `
  -RepoRoot $RepoRoot | Out-Host
if($LASTEXITCODE -ne 0){ throw "PIE_HOSTED_BUILD_SELFTEST_FAIL" }

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\selftest_pie_install_v1.ps1") `
  -RepoRoot $RepoRoot | Out-Host
if($LASTEXITCODE -ne 0){ throw "PIE_INSTALL_SELFTEST_FAIL" }

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\selftest_pie_memory_resolve_v1.ps1") `
  -RepoRoot $RepoRoot | Out-Host
if($LASTEXITCODE -ne 0){ throw "PIE_MEMORY_RESOLVE_SELFTEST_FAIL" }

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\selftest_pie_memory_negative_v1.ps1") `
  -RepoRoot $RepoRoot | Out-Host
if($LASTEXITCODE -ne 0){ throw "PIE_MEMORY_NEGATIVE_SELFTEST_FAIL" }

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\selftest_pie_memory_lifecycle_v1.ps1") `
  -RepoRoot $RepoRoot | Out-Host
if($LASTEXITCODE -ne 0){ throw "PIE_MEMORY_LIFECYCLE_SELFTEST_FAIL" }

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\selftest_pie_agent_workflow_v1.ps1") `
  -RepoRoot $RepoRoot | Out-Host
if($LASTEXITCODE -ne 0){ throw "PIE_AGENT_WORKFLOW_SELFTEST_FAIL" }

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\selftest_pie_agent_session_contract_v1.ps1") `
  -RepoRoot $RepoRoot | Out-Host
if($LASTEXITCODE -ne 0){ throw "PIE_AGENT_SESSION_CONTRACT_SELFTEST_FAIL" }

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\selftest_pie_chat_recall_v1.ps1") `
  -RepoRoot $RepoRoot | Out-Host
if($LASTEXITCODE -ne 0){ throw "PIE_CHAT_RECALL_SELFTEST_FAIL" }

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\selftest_pie_session_backup_v1.ps1") `
  -RepoRoot $RepoRoot | Out-Host
if($LASTEXITCODE -ne 0){ throw "PIE_SESSION_BACKUP_SELFTEST_FAIL" }

$HaaiSelftestRepo = $(if(-not [string]::IsNullOrWhiteSpace($env:PIE_HAAI_REPO)){ $env:PIE_HAAI_REPO } else { "C:\dev\haai" })
if(Test-Path -LiteralPath (Join-Path $HaaiSelftestRepo "core\python\haai_core\cli.py") -PathType Leaf){
  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File (Join-Path $RepoRoot "scripts\selftest_pie_haai_adapter_v1.ps1") `
    -RepoRoot $RepoRoot -HaaiRepo $HaaiSelftestRepo | Out-Host
  if($LASTEXITCODE -ne 0){ throw "PIE_HAAI_ADAPTER_SELFTEST_FAIL" }
  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File (Join-Path $RepoRoot "scripts\selftest_pie_haai_project_v1.ps1") `
    -RepoRoot $RepoRoot -HaaiRepo $HaaiSelftestRepo | Out-Host
  if($LASTEXITCODE -ne 0){ throw "PIE_HAAI_PROJECT_SELFTEST_FAIL" }
} else {
  Write-Host "PIE_HAAI_ADAPTER_SELFTEST_SKIPPED_UNAVAILABLE" -ForegroundColor Yellow
}

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\selftest_pie_drift_boundaries_v1.ps1") `
  -RepoRoot $RepoRoot | Out-Host
if($LASTEXITCODE -ne 0){ throw "PIE_DRIFT_BOUNDARIES_SELFTEST_FAIL" }

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\selftest_pie_agent_timeout_retry_v1.ps1") `
  -RepoRoot $RepoRoot | Out-Host
if($LASTEXITCODE -ne 0){ throw "PIE_AGENT_TIMEOUT_RETRY_SELFTEST_FAIL" }

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\selftest_pie_context_repo_facts_v1.ps1") `
  -RepoRoot $RepoRoot | Out-Host
if($LASTEXITCODE -ne 0){ throw "PIE_CONTEXT_REPO_FACTS_SELFTEST_FAIL" }

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\selftest_pie_response_grounding_v1.ps1") `
  -RepoRoot $RepoRoot | Out-Host
if($LASTEXITCODE -ne 0){ throw "PIE_RESPONSE_GROUNDING_SELFTEST_FAIL" }

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Pie verify -RepoRoot $RepoRoot -TargetRepo $RepoRoot | Out-Host
if($LASTEXITCODE -ne 0){ throw "PIE_VERIFY_INIT_FAIL" }

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Pie detect -RepoRoot $RepoRoot -TargetRepo $RepoRoot | Out-Host
if($LASTEXITCODE -ne 0){ throw "PIE_DETECT_FAIL" }

$Readme = Join-Path $RepoRoot "README.md"
if(Test-Path -LiteralPath $Readme -PathType Leaf){
  $RuntimeSessionId = "runtime_green_" + (Get-Date -Format "yyyyMMdd_HHmmss_fff")

  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File (Join-Path $RepoRoot "scripts\pie_agent_start_v1.ps1") `
    -RepoRoot $RepoRoot `
    -SessionId $RuntimeSessionId `
    -Backend "mock" `
    -Model "runtime-green-mock" | Out-Host
  if($LASTEXITCODE -ne 0){ throw "PIE_AGENT_START_FAIL" }

  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Pie attach -RepoRoot $RepoRoot -SessionId $RuntimeSessionId -Path $Readme | Out-Host
  if($LASTEXITCODE -ne 0){ throw "PIE_ATTACH_FAIL" }

  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Pie ask -RepoRoot $RepoRoot -SessionId $RuntimeSessionId -Text "What file is attached? Answer briefly." | Out-Host
  if($LASTEXITCODE -ne 0){ throw "PIE_ASK_FAIL" }

  $AskPrompt = Get-ChildItem -LiteralPath (Join-Path $RepoRoot ("runs\" + $RuntimeSessionId + "\sent_prompts")) -File -Filter "prompt_*.txt" |
    Sort-Object LastWriteTimeUtc -Descending |
    Select-Object -First 1
  if($null -eq $AskPrompt){ throw "PIE_ASK_PROMPT_MISSING" }
  $AskPromptText = Get-Content -LiteralPath $AskPrompt.FullName -Raw
  if($AskPromptText -notmatch "PIE GOVERNED CONTEXT PACKET v2"){ throw "PIE_ASK_CONTEXT_NOT_INJECTED" }
  if($AskPromptText -notmatch "RESOLVED PERSONAL MEMORY:"){ throw "PIE_ASK_MEMORY_NOT_INJECTED" }

  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File (Join-Path $RepoRoot "scripts\pie_agent_stop_v1.ps1") `
    -RepoRoot $RepoRoot `
    -SessionId $RuntimeSessionId | Out-Host
  if($LASTEXITCODE -ne 0){ throw "PIE_AGENT_STOP_FAIL" }
}

$BenchRoot = Join-Path $RepoRoot "benchmarks\model_matrix"
if(Test-Path -LiteralPath $BenchRoot -PathType Container){
  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Pie score -RepoRoot $RepoRoot | Out-Host
  if($LASTEXITCODE -ne 0){ throw "PIE_SCORE_FAIL" }

  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Pie show -RepoRoot $RepoRoot -Scorecard | Out-Host
  if($LASTEXITCODE -ne 0){ throw "PIE_SHOW_FAIL" }
}

Write-Host "PIE_RUNTIME_GREEN_OK" -ForegroundColor Green
