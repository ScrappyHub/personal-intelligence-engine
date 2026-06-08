param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Stamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
$FreezeRoot = Join-Path $RepoRoot ("proofs\freeze\pie_tier0_green_" + $Stamp)
$Enc = New-Object System.Text.UTF8Encoding($false)

function Write-Utf8NoBomLf {
  param([string]$Path,[string]$Text)
  $Dir = Split-Path -Parent $Path
  if(-not (Test-Path -LiteralPath $Dir -PathType Container)){
    New-Item -ItemType Directory -Force -Path $Dir | Out-Null
  }
  $Clean = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $Clean.EndsWith("`n")){ $Clean += "`n" }
  [System.IO.File]::WriteAllText($Path,$Clean,$Enc)
}

function Get-Sha256 {
  param([string]$Path)
  return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Parse-Gate {
  param([string]$Path)

  $tok=$null
  $err=$null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tok,[ref]$err)

  if(@($err).Count -gt 0){
    throw ("PARSE_FAIL: " + $Path + " :: " + $err[0].ToString())
  }
}

function Run-Checked {
  param(
    [string]$Name,
    [string]$Script
  )

  $Out = Join-Path $FreezeRoot ($Name + "_stdout.txt")
  $Err = Join-Path $FreezeRoot ($Name + "_stderr.txt")

  $Proc = Start-Process `
    -FilePath "powershell.exe" `
    -ArgumentList @(
      "-NoProfile",
      "-NonInteractive",
      "-ExecutionPolicy","Bypass",
      "-File",$Script,
      "-RepoRoot",$RepoRoot
    ) `
    -NoNewWindow `
    -PassThru `
    -RedirectStandardOutput $Out `
    -RedirectStandardError $Err

  $TimeoutSeconds = 180

  if(-not $Proc.WaitForExit($TimeoutSeconds * 1000)){
    try { $Proc.Kill() } catch { }
    throw ("PIE_FULL_GREEN_TIMEOUT: " + $Name)
  }

  $Proc.Refresh()

  $ExitCodeText = [string]$Proc.ExitCode
  if([string]::IsNullOrWhiteSpace($ExitCodeText)){ $ExitCodeText = "0" }
  $ExitCode = [int]$ExitCodeText

  $Receipt = [ordered]@{
    schema = "pie.full_green.child_receipt.v1"
    name = $Name
    script = $Script
    exit_code = $ExitCode
    stdout = $Out
    stderr = $Err
    stdout_sha256 = $(if(Test-Path -LiteralPath $Out -PathType Leaf){ Get-Sha256 $Out } else { "" })
    stderr_sha256 = $(if(Test-Path -LiteralPath $Err -PathType Leaf){ Get-Sha256 $Err } else { "" })
    created_utc = [DateTime]::UtcNow.ToString("o")
  }

  $Line = ($Receipt | ConvertTo-Json -Depth 12 -Compress) + "`n"
  [System.IO.File]::AppendAllText((Join-Path $FreezeRoot "child_receipts.ndjson"),$Line,$Enc)

  if($ExitCode -ne 0){
    throw ("PIE_FULL_GREEN_CHILD_FAIL: " + $Name + " exit=" + [string]$ExitCode)
  }
}

New-Item -ItemType Directory -Force -Path $FreezeRoot | Out-Null

$ScriptsToParse = @(
  "scripts\pie_context_build_v1.ps1",
  "scripts\pie_memory_resolve_v1.ps1",
  "scripts\pie_plan_v1.ps1",
  "scripts\pie_exec_v1.ps1",
  "scripts\pie_exec_policy_v1.ps1",
  "scripts\pie_repo_link_v1.ps1",
  "scripts\pie_repo_scan_v1.ps1",
  "scripts\pie_agent_send_v1.ps1",
  "scripts\pie_ollama_ensure_v1.ps1",
  "scripts\selftest_pie_context_v1.ps1",
  "scripts\selftest_pie_memory_resolve_v1.ps1",
  "scripts\selftest_pie_plan_v1.ps1",
  "scripts\selftest_pie_exec_v1.ps1",
  "scripts\selftest_pie_exec_policy_v1.ps1",
  "scripts\selftest_pie_exec_policy_boundary_v1.ps1",
  "scripts\pie_state_snapshot_v1.ps1",
  "scripts\pie_state_diff_v1.ps1",
  "scripts\pie_exec_with_snapshot_v1.ps1",
  "scripts\selftest_pie_exec_snapshot_v1.ps1",
  "scripts\pie_execution_replay_v1.ps1",
  "scripts\selftest_pie_execution_replay_v1.ps1",
  "scripts\pie_reason_trace_v1.ps1",
  "scripts\selftest_pie_reason_trace_v1.ps1",
  "scripts\pie_capability_v1.ps1",
  "scripts\selftest_pie_capability_v1.ps1",
  "scripts\pie_state_snapshot_v1.ps1",
  "scripts\pie_state_diff_v1.ps1",
  "scripts\pie_exec_with_snapshot_v1.ps1",
  "scripts\selftest_pie_exec_snapshot_v1.ps1"
  "scripts\pie_cognition_convergence_v1.ps1",
  "scripts\selftest_pie_cognition_convergence_v1.ps1"
  "scripts\pie_intent_record_v1.ps1",
  "scripts\pie_intent_query_v1.ps1",
  "scripts\selftest_pie_intent_v1.ps1",
  "scripts\pie_intent_resume_v1.ps1",
  "scripts\selftest_pie_intent_resume_v1.ps1"
  "scripts\pie_goal_lineage_v1.ps1",
  "scripts\selftest_pie_goal_lineage_v1.ps1"
  "scripts\pie_repo_template_record_v1.ps1",
  "scripts\pie_repo_template_query_v1.ps1",
  "scripts\pie_repo_plan_template_v1.ps1",
  "scripts\selftest_pie_repo_template_v1.ps1"
  "scripts\pie_multi_repo_route_v1.ps1",
  "scripts\selftest_pie_multi_repo_route_v1.ps1"
  "scripts\pie_cross_repo_graph_record_v1.ps1",
  "scripts\pie_cross_repo_graph_query_v1.ps1",
  "scripts\pie_cross_repo_route_v1.ps1",
  "scripts\selftest_pie_cross_repo_graph_v1.ps1"
  "scripts\pie_cross_repo_exec_plan_v1.ps1",
  "scripts\selftest_pie_cross_repo_exec_plan_v1.ps1"
  "scripts\pie_cross_repo_execute_v1.ps1",
  "scripts\selftest_pie_cross_repo_execute_v1.ps1"
  "scripts\pie_cross_repo_replay_aggregate_v1.ps1",
  "scripts\selftest_pie_cross_repo_replay_aggregate_v1.ps1"
  "scripts\pie_cross_repo_regression_replay_v1.ps1",
  "scripts\selftest_pie_cross_repo_regression_replay_v1.ps1"
  "scripts\selftest_pie_cross_repo_regression_negative_v1.ps1"
  "scripts\pie_cross_repo_baseline_promote_v1.ps1",
  "scripts\selftest_pie_cross_repo_baseline_promote_v1.ps1"
  "scripts\pie_cross_repo_baseline_enforce_v1.ps1",
  "scripts\selftest_pie_cross_repo_baseline_enforce_v1.ps1"
  "scripts\pie_cross_repo_baseline_revoke_v1.ps1",
  "scripts\selftest_pie_cross_repo_baseline_revoke_v1.ps1"
  "scripts\pie_cross_repo_baseline_replace_v1.ps1",
  "scripts\selftest_pie_cross_repo_baseline_replace_v1.ps1"
)

$ParseLines = New-Object System.Collections.Generic.List[string]

foreach($Rel in $ScriptsToParse){
  $Full = Join-Path $RepoRoot $Rel
  if(-not (Test-Path -LiteralPath $Full -PathType Leaf)){
    throw ("PIE_FULL_GREEN_SCRIPT_MISSING: " + $Full)
  }

  Parse-Gate -Path $Full
  [void]$ParseLines.Add($Rel + " sha256=" + (Get-Sha256 $Full))
}

Write-Utf8NoBomLf -Path (Join-Path $FreezeRoot "parse_gate_sha256s.txt") -Text ($ParseLines.ToArray() -join "`n")

$Selftests = @(
  @{ name="context"; script="scripts\selftest_pie_context_v1.ps1" },
  @{ name="memory_resolve"; script="scripts\selftest_pie_memory_resolve_v1.ps1" },
  @{ name="plan"; script="scripts\selftest_pie_plan_v1.ps1" },
  @{ name="exec"; script="scripts\selftest_pie_exec_v1.ps1" },
  @{ name="exec_policy"; script="scripts\selftest_pie_exec_policy_v1.ps1" },
  @{ name="exec_policy_boundary"; script="scripts\selftest_pie_exec_policy_boundary_v1.ps1" },
  @{ name="exec_snapshot"; script="scripts\selftest_pie_exec_snapshot_v1.ps1" },
  @{ name="execution_replay"; script="scripts\selftest_pie_execution_replay_v1.ps1" },
  @{ name="reason_trace"; script="scripts\selftest_pie_reason_trace_v1.ps1" },
  @{ name="capability"; script="scripts\selftest_pie_capability_v1.ps1" },
  @{ name="exec_snapshot"; script="scripts\selftest_pie_exec_snapshot_v1.ps1" }
  @{ name="cognition_convergence"; script="scripts\selftest_pie_cognition_convergence_v1.ps1" }
  @{ name="intent"; script="scripts\selftest_pie_intent_v1.ps1" }
  @{ name="intent_resume"; script="scripts\selftest_pie_intent_resume_v1.ps1" }
  @{ name="goal_lineage"; script="scripts\selftest_pie_goal_lineage_v1.ps1" }
  @{ name="repo_template"; script="scripts\selftest_pie_repo_template_v1.ps1" }
  @{ name="multi_repo_route"; script="scripts\selftest_pie_multi_repo_route_v1.ps1" }
  @{ name="cross_repo_graph"; script="scripts\selftest_pie_cross_repo_graph_v1.ps1" }
  @{ name="cross_repo_exec_plan"; script="scripts\selftest_pie_cross_repo_exec_plan_v1.ps1" }
  @{ name="cross_repo_execute"; script="scripts\selftest_pie_cross_repo_execute_v1.ps1" }
  @{ name="cross_repo_replay_aggregate"; script="scripts\selftest_pie_cross_repo_replay_aggregate_v1.ps1" }
  @{ name="cross_repo_regression_replay"; script="scripts\selftest_pie_cross_repo_regression_replay_v1.ps1" }
  @{ name="cross_repo_regression_negative"; script="scripts\selftest_pie_cross_repo_regression_negative_v1.ps1" }
  @{ name="cross_repo_baseline_promote"; script="scripts\selftest_pie_cross_repo_baseline_promote_v1.ps1" }
  @{ name="cross_repo_baseline_enforce"; script="scripts\selftest_pie_cross_repo_baseline_enforce_v1.ps1" }
  @{ name="cross_repo_baseline_revoke"; script="scripts\selftest_pie_cross_repo_baseline_revoke_v1.ps1" }
  @{ name="cross_repo_baseline_replace"; script="scripts\selftest_pie_cross_repo_baseline_replace_v1.ps1" }
)

foreach($T in $Selftests){
  Run-Checked -Name $T.name -Script (Join-Path $RepoRoot $T.script)
}

$Summary = [ordered]@{
  schema = "pie.tier0.full_green.summary.v1"
  status = "PIE_TIER0_FULL_GREEN_OK"
  repo_root = $RepoRoot
  freeze_root = $FreezeRoot
  parse_gate_count = @($ScriptsToParse).Count
  selftest_count = @($Selftests).Count
  child_receipts = Join-Path $FreezeRoot "child_receipts.ndjson"
  parse_gate_sha256s = Join-Path $FreezeRoot "parse_gate_sha256s.txt"
  created_utc = [DateTime]::UtcNow.ToString("o")
}

Write-Utf8NoBomLf -Path (Join-Path $FreezeRoot "FREEZE_SUMMARY.json") -Text ($Summary | ConvertTo-Json -Depth 12)

$AllFiles = @(Get-ChildItem -LiteralPath $FreezeRoot -File -Recurse | Sort-Object FullName)
$HashLines = New-Object System.Collections.Generic.List[string]

foreach($File in $AllFiles){
  if($File.Name -eq "sha256sums.txt"){ continue }
  $Rel = $File.FullName.Substring($FreezeRoot.Length).TrimStart("\")
  [void]$HashLines.Add((Get-Sha256 $File.FullName) + "  " + $Rel)
}

Write-Utf8NoBomLf -Path (Join-Path $FreezeRoot "sha256sums.txt") -Text ($HashLines.ToArray() -join "`n")

Write-Host "PIE_TIER0_FULL_GREEN_OK" -ForegroundColor Green
Write-Host ("freeze: " + $FreezeRoot)


























