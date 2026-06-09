param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$false)]
  [ValidateSet("latest_governance","trusted_baseline_lifecycle","full")]
  [string]$Mode = "latest_governance",
  [Parameter(Mandatory=$false)][int]$TimeoutSeconds = 480
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
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

function Sha256File {
  param([string]$Path)
  return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function RelPath {
  param([string]$Path)
  $Full = (Resolve-Path -LiteralPath $Path).Path
  if($Full.StartsWith($RepoRoot,[System.StringComparison]::OrdinalIgnoreCase)){
    return $Full.Substring($RepoRoot.Length).TrimStart('\','/')
  }
  return $Full
}

function Invoke-StepTimed {
  param(
    [Parameter(Mandatory=$true)][string]$Name,
    [Parameter(Mandatory=$true)][string]$Script,
    [Parameter(Mandatory=$true)][string]$Stdout,
    [Parameter(Mandatory=$true)][string]$Stderr,
    [Parameter(Mandatory=$true)][int]$TimeoutSeconds
  )

  if(-not (Test-Path -LiteralPath $Script -PathType Leaf)){
    throw ("PIE_GOVERNANCE_GREEN_SCRIPT_MISSING: " + $Script)
  }

  Write-Host ("PIE_GOVERNANCE_GREEN_STEP_START: " + $Name) -ForegroundColor Cyan

  $Args = @(
    "-NoProfile",
    "-NonInteractive",
    "-ExecutionPolicy", "Bypass",
    "-File", $Script,
    "-RepoRoot", $RepoRoot
  )

  $P = Start-Process -FilePath "powershell.exe" `
    -ArgumentList $Args `
    -NoNewWindow `
    -PassThru `
    -RedirectStandardOutput $Stdout `
    -RedirectStandardError $Stderr

  $Done = $P.WaitForExit($TimeoutSeconds * 1000)

  if(-not $Done){
    try { Stop-Process -Id $P.Id -Force -ErrorAction SilentlyContinue } catch {}
    Write-Host ("PIE_GOVERNANCE_GREEN_STEP_TIMEOUT: " + $Name) -ForegroundColor Red
    throw ("PIE_GOVERNANCE_GREEN_STEP_TIMEOUT: " + $Name)
  }

  # Required on Windows PowerShell: make sure process metadata is refreshed
  # after WaitForExit(timeout), otherwise ExitCode can appear blank/null.
  $P.WaitForExit()
  $P.Refresh()
  $ExitCode = $P.ExitCode

  if($null -eq $ExitCode){
    Write-Host ("PIE_GOVERNANCE_GREEN_STEP_EXITCODE_NULL: " + $Name) -ForegroundColor Red
    Write-Host ("stdout: " + $Stdout)
    Write-Host ("stderr: " + $Stderr)
    throw ("PIE_GOVERNANCE_GREEN_STEP_EXITCODE_NULL: " + $Name)
  }

  if([int]$ExitCode -ne 0){
    Write-Host ("PIE_GOVERNANCE_GREEN_STEP_FAIL: " + $Name + " exit=" + [string]$ExitCode) -ForegroundColor Red
    Write-Host ("stdout: " + $Stdout)
    Write-Host ("stderr: " + $Stderr)
    throw ("PIE_GOVERNANCE_GREEN_STEP_FAIL: " + $Name)
  }

  Write-Host ("PIE_GOVERNANCE_GREEN_STEP_OK: " + $Name) -ForegroundColor Green
}

if($Mode -eq "full"){
  Write-Host "PIE_GOVERNANCE_GREEN_DELEGATE_FULL_START" -ForegroundColor Cyan

  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File (Join-Path $RepoRoot "scripts\FULL_GREEN_RUNNER_PIE_TIER0_v1.ps1") `
    -RepoRoot $RepoRoot

  if($LASTEXITCODE -ne 0){
    throw "PIE_GOVERNANCE_GREEN_FULL_DELEGATE_FAIL"
  }

  Write-Host "PIE_GOVERNANCE_GREEN_DELEGATE_FULL_OK" -ForegroundColor Green
  exit 0
}

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
$FreezeRoot = Join-Path $RepoRoot ("proofs\freeze\pie_governance_green_" + $Stamp)
New-Item -ItemType Directory -Force -Path $FreezeRoot | Out-Null

$ScriptsToParse = @(
  "scripts\pie_cross_repo_graph_record_v1.ps1",
  "scripts\pie_multi_repo_route_v1.ps1",
  "scripts\pie_cross_repo_exec_plan_v1.ps1",
  "scripts\pie_cross_repo_execute_v1.ps1",
  "scripts\pie_cross_repo_replay_aggregate_v1.ps1",
  "scripts\pie_cross_repo_regression_replay_v1.ps1",
  "scripts\selftest_pie_cross_repo_regression_negative_v1.ps1",
  "scripts\pie_cross_repo_baseline_promote_v1.ps1",
  "scripts\pie_cross_repo_baseline_enforce_v1.ps1",
  "scripts\pie_cross_repo_baseline_revoke_v1.ps1",
  "scripts\pie_cross_repo_baseline_replace_v1.ps1",
  "scripts\pie_cross_repo_baseline_lineage_audit_v1.ps1",
  "scripts\pie_cross_repo_baseline_governance_report_v1.ps1",
  "scripts\selftest_pie_cross_repo_baseline_promote_v1.ps1",
  "scripts\selftest_pie_cross_repo_baseline_enforce_v1.ps1",
  "scripts\selftest_pie_cross_repo_baseline_revoke_v1.ps1",
  "scripts\selftest_pie_cross_repo_baseline_replace_v1.ps1",
  "scripts\selftest_pie_cross_repo_baseline_lineage_audit_v1.ps1",
  "scripts\selftest_pie_cross_repo_baseline_governance_report_v1.ps1"
)

$ParseRows = New-Object System.Collections.Generic.List[object]

foreach($Rel in $ScriptsToParse){
  $Full = Join-Path $RepoRoot $Rel

  if(-not (Test-Path -LiteralPath $Full -PathType Leaf)){
    throw ("PIE_GOVERNANCE_GREEN_PARSE_MISSING: " + $Rel)
  }

  $tok=$null
  $err=$null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Full,[ref]$tok,[ref]$err)

  if(@($err).Count -gt 0){
    throw ("PIE_GOVERNANCE_GREEN_PARSE_FAIL: " + $Rel + " :: " + $err[0].ToString())
  }

  [void]$ParseRows.Add([pscustomobject][ordered]@{
    path = $Rel
    sha256 = Sha256File $Full
  })
}

$ParseText = ($ParseRows.ToArray() | ForEach-Object { $_.sha256 + "  " + $_.path }) -join "`n"
Write-Utf8NoBomLf -Path (Join-Path $FreezeRoot "parse_gate_sha256s.txt") -Text $ParseText

if($Mode -eq "latest_governance"){
  $Selftests = @(
    @{ name="cross_repo_regression_negative"; script="scripts\selftest_pie_cross_repo_regression_negative_v1.ps1" },
    @{ name="cross_repo_baseline_enforce"; script="scripts\selftest_pie_cross_repo_baseline_enforce_v1.ps1" },
    @{ name="cross_repo_baseline_governance_report"; script="scripts\selftest_pie_cross_repo_baseline_governance_report_v1.ps1" }
  )
}
elseif($Mode -eq "trusted_baseline_lifecycle"){
  $Selftests = @(
    @{ name="cross_repo_regression_negative"; script="scripts\selftest_pie_cross_repo_regression_negative_v1.ps1" },
    @{ name="cross_repo_baseline_promote"; script="scripts\selftest_pie_cross_repo_baseline_promote_v1.ps1" },
    @{ name="cross_repo_baseline_enforce"; script="scripts\selftest_pie_cross_repo_baseline_enforce_v1.ps1" },
    @{ name="cross_repo_baseline_revoke"; script="scripts\selftest_pie_cross_repo_baseline_revoke_v1.ps1" },
    @{ name="cross_repo_baseline_replace"; script="scripts\selftest_pie_cross_repo_baseline_replace_v1.ps1" },
    @{ name="cross_repo_baseline_lineage_audit"; script="scripts\selftest_pie_cross_repo_baseline_lineage_audit_v1.ps1" },
    @{ name="cross_repo_baseline_governance_report"; script="scripts\selftest_pie_cross_repo_baseline_governance_report_v1.ps1" }
  )
}
else {
  throw ("PIE_GOVERNANCE_GREEN_MODE_UNHANDLED: " + $Mode)
}

$ReceiptRows = New-Object System.Collections.Generic.List[object]

foreach($T in $Selftests){
  $Name = [string]$T.name
  $ScriptRel = [string]$T.script
  $Script = Join-Path $RepoRoot $ScriptRel
  $Stdout = Join-Path $FreezeRoot ($Name + "_stdout.txt")
  $Stderr = Join-Path $FreezeRoot ($Name + "_stderr.txt")
  $Start = [DateTime]::UtcNow

  Invoke-StepTimed -Name $Name -Script $Script -Stdout $Stdout -Stderr $Stderr -TimeoutSeconds $TimeoutSeconds

  $End = [DateTime]::UtcNow
  [void]$ReceiptRows.Add([pscustomobject][ordered]@{
    name = $Name
    script = $ScriptRel
    stdout = RelPath $Stdout
    stdout_sha256 = Sha256File $Stdout
    stderr = RelPath $Stderr
    stderr_sha256 = Sha256File $Stderr
    started_utc = $Start.ToString("o")
    ended_utc = $End.ToString("o")
    duration_seconds = [Math]::Round(($End - $Start).TotalSeconds,3)
    status = "ok"
  })
}

$ReceiptText = ($ReceiptRows.ToArray() | ForEach-Object { $_ | ConvertTo-Json -Depth 20 -Compress }) -join "`n"
Write-Utf8NoBomLf -Path (Join-Path $FreezeRoot "child_receipts.ndjson") -Text $ReceiptText

$Summary = [ordered]@{
  schema = "pie.governance.green.freeze.summary.v1"
  mode = $Mode
  repo_root = $RepoRoot
  freeze_root = $FreezeRoot
  status = "ok"
  selftest_count = @($Selftests).Count
  timeout_seconds = $TimeoutSeconds
  created_utc = [DateTime]::UtcNow.ToString("o")
}

Write-Utf8NoBomLf -Path (Join-Path $FreezeRoot "FREEZE_SUMMARY.json") -Text ($Summary | ConvertTo-Json -Depth 20)

$Files = Get-ChildItem -LiteralPath $FreezeRoot -File |
  Where-Object { $_.Name -ne "sha256sums.txt" } |
  Sort-Object Name

$SumLines = New-Object System.Collections.Generic.List[string]
foreach($F in $Files){
  [void]$SumLines.Add((Sha256File $F.FullName) + "  " + $F.Name)
}

Write-Utf8NoBomLf -Path (Join-Path $FreezeRoot "sha256sums.txt") -Text ($SumLines.ToArray() -join "`n")

Write-Host "PIE_GOVERNANCE_GREEN_OK" -ForegroundColor Green
Write-Host ("mode: " + $Mode)
Write-Host ("freeze: " + $FreezeRoot)

