param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$false)][string]$OllamaModel = "",
  [Parameter(Mandatory=$false)][string]$LlamaCppModel = "",
  [Parameter(Mandatory=$false)][string]$OnnxModelDir = "",
  [switch]$IncludeTier0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Consolidated engine verification / stress entrypoint. Aggregates:
#   1. Parse-gate of every engine-path script (fail-closed on any parse error).
#   2. Persona alignment check (all backends share engine\PIE_PERSONA.v1.txt; identity guard present).
#   3. Frozen Tier-0 green pipeline (optional -IncludeTier0) to prove the default stub path is intact.
#   4. The three engine certification trios (ollama, llama.cpp, onnx).
# Writes an aggregate receipt to runs\engine_verify\<ts>.json (+ latest.json). Emits
# PIE_ENGINE_VERIFY_ALL_V1_GREEN only when every executed check passed and no positive check
# regressed. Positive checks are INCONCLUSIVE (not failures) when their backend/model is absent.
#
# Authored, not yet executed on Windows. Run:
#   .\scripts\_RUN_pie_engine_verify_all_v1.ps1 -RepoRoot . -IncludeTier0 `
#     -OllamaModel <sealed+pulled> -LlamaCppModel <sealed+served> -OnnxModelDir <real onnx export>

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Scripts  = Join-Path $RepoRoot "scripts"
$results  = New-Object System.Collections.Generic.List[object]
function Add-Result([string]$id,[string]$status,[string]$detail){
  $results.Add([ordered]@{ id=$id; status=$status; detail=$detail })
  $color = switch($status){ "pass"{"Green"} "fail"{"Red"} "inconclusive"{"Yellow"} default{"Gray"} }
  Write-Host ("  [" + $status.ToUpperInvariant() + "] " + $id + $(if($detail){" :: " + $detail}else{""})) -ForegroundColor $color
}

# Run a child powershell.exe with stderr merged and the terminating-error preference relaxed, so a
# child that writes to stderr or exits non-zero (expected for negative checks) is recorded via
# $LASTEXITCODE instead of crashing this aggregator with a NativeCommandError.
function Invoke-Child([string]$file,[string[]]$childArgs){
  $prev = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $o = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $file @childArgs 2>&1 | Out-String)
  }
  finally { $ErrorActionPreference = $prev }
  return $o
}

Write-Host "PIE_ENGINE_VERIFY_ALL_START" -ForegroundColor DarkCyan

# --- 1. Parse-gate every engine-path script. ---
$gateTargets = @(
  "pie_run_v1.ps1",
  "pie_backend_ollama_cmd_v1.ps1",
  "pie_backend_llamacpp_cmd_v1.ps1",
  "pie_backend_onnx_cmd_v1.ps1",
  "_lib_pie_persona_v1.ps1",
  "_selftest_pie_engine_ollama_v1.ps1",
  "_selftest_pie_engine_llamacpp_v1.ps1",
  "_selftest_pie_engine_onnx_v1.ps1",
  "_lib_pie_migrations_v1.ps1",
  "_selftest_pie_migrations_v1.ps1",
  "_lib_pie_atomic_v1.ps1",
  "_selftest_pie_atomic_write_v1.ps1",
  "_lib_pie_txn_v1.ps1",
  "_selftest_pie_txn_v1.ps1",
  "_lib_pie_compaction_v1.ps1",
  "_selftest_pie_compaction_v1.ps1"
)
$gateOk = $true
foreach($t in $gateTargets){
  $p = Join-Path $Scripts $t
  if(-not (Test-Path -LiteralPath $p -PathType Leaf)){ Add-Result ("parse:" + $t) "fail" "missing"; $gateOk = $false; continue }
  $tokens = $null
  $perrs  = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($p,[ref]$tokens,[ref]$perrs)
  if($perrs -and $perrs.Count -gt 0){ Add-Result ("parse:" + $t) "fail" ($perrs[0].Message); $gateOk = $false }
  else { Add-Result ("parse:" + $t) "pass" "" }
}

# --- 2. Persona alignment. ---
$persona = Join-Path $RepoRoot "engine\PIE_PERSONA.v1.txt"
if(-not (Test-Path -LiteralPath $persona -PathType Leaf)){
  Add-Result "persona:file" "fail" "engine\PIE_PERSONA.v1.txt missing"
}
else {
  $ptext = Get-Content -LiteralPath $persona -Raw
  if($ptext -match 'Never claim to be' -and $ptext -match 'Do only what the user asked' -and $ptext -match 'identically whether PIE is self-hosted'){
    Add-Result "persona:contract" "pass" "identity + minimalism + parity present"
  } else {
    Add-Result "persona:contract" "fail" "persona missing an identity/minimalism/parity clause"
  }
  $allShared = $true
  foreach($w in @("pie_backend_ollama_cmd_v1.ps1","pie_backend_llamacpp_cmd_v1.ps1","pie_backend_onnx_cmd_v1.ps1")){
    $wt = Get-Content -LiteralPath (Join-Path $Scripts $w) -Raw
    if($wt -notmatch 'PIE_PersonaSystem'){ $allShared = $false; Add-Result ("persona:shared:" + $w) "fail" "does not use PIE_PersonaSystem" }
  }
  if($allShared){ Add-Result "persona:shared" "pass" "all backends load the shared persona" }

  # Interactive chat/ask path must carry the same identity + minimalism + parity pillars.
  $ctxBuilder = Join-Path $Scripts "pie_context_build_v1.ps1"
  if(-not (Test-Path -LiteralPath $ctxBuilder -PathType Leaf)){
    Add-Result "persona:interactive" "fail" "pie_context_build_v1.ps1 missing"
  }
  else {
    $ctext = Get-Content -LiteralPath $ctxBuilder -Raw
    if($ctext -match 'Never claim to be' -and $ctext -match 'Do only what the user asked' -and $ctext -match 'identically whether PIE is self-hosted'){
      Add-Result "persona:interactive" "pass" "chat/ask ROLE carries identity + minimalism + parity"
    } else {
      Add-Result "persona:interactive" "fail" "chat/ask ROLE is missing an identity/minimalism/parity pillar"
    }
  }

  # Hosted gateway contract must require persona/behavior parity with local.
  $hostedContract = Join-Path $RepoRoot "workbench\contracts\PIE_HOSTED_GATEWAY.v1.json"
  if(-not (Test-Path -LiteralPath $hostedContract -PathType Leaf)){
    Add-Result "persona:hosted" "fail" "PIE_HOSTED_GATEWAY.v1.json missing"
  }
  else {
    try { $hc = Get-Content -LiteralPath $hostedContract -Raw | ConvertFrom-Json } catch { $hc = $null }
    $hasControl = $null -ne $hc -and ($hc.required_controls -contains "persona_parity")
    $hasBlock   = $null -ne $hc -and ($hc.PSObject.Properties.Name -contains "persona_parity") -and ($hc.persona_parity.persona_source -eq "engine/PIE_PERSONA.v1.txt")
    if($hasControl -and $hasBlock){
      Add-Result "persona:hosted" "pass" "hosted contract requires persona_parity from the shared persona"
    } else {
      Add-Result "persona:hosted" "fail" "hosted contract is missing the persona_parity requirement"
    }
  }
}

# --- 3. Frozen Tier-0 default path (optional). ---
if($IncludeTier0){
  $tier0 = Join-Path $Scripts "_RUN_pie_tier0_full_green_v1.ps1"
  if(Test-Path -LiteralPath $tier0 -PathType Leaf){
    $out = Invoke-Child $tier0 @("-RepoRoot",$RepoRoot)
    if($LASTEXITCODE -eq 0 -and $out -match 'PIE_TIER0_FULL_GREEN_V1_OK'){ Add-Result "tier0" "pass" "default stub path intact" }
    else { Add-Result "tier0" "fail" "tier0 did not report FULL_GREEN" }
  } else { Add-Result "tier0" "fail" "runner missing" }
} else {
  Add-Result "tier0" "inconclusive" "skipped (pass -IncludeTier0 to run)"
}

# --- 4. Engine certification trios. ---
function Run-Trio([string]$id,[string]$script,[string[]]$extraArgs,[string]$greenToken){
  $p = Join-Path $Scripts $script
  if(-not (Test-Path -LiteralPath $p -PathType Leaf)){ Add-Result $id "fail" "missing"; return }
  $callArgs = @("-RepoRoot",$RepoRoot) + $extraArgs
  $out = Invoke-Child $p $callArgs
  if($LASTEXITCODE -ne 0){
    $lastLine = @($out -split "`n") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Last 1
    Add-Result $id "fail" ([string]$lastLine).Trim()
    return
  }
  if($out -match [regex]::Escape($greenToken)){ Add-Result $id "pass" "green (incl. real generation)" }
  elseif($out -match 'INCONCLUSIVE'){ Add-Result $id "inconclusive" "neg+binding ok; positive not run (no backend/model)" }
  else { Add-Result $id "fail" "no green token, no inconclusive marker" }
}

$ollamaArgs = @(); if($OllamaModel){ $ollamaArgs = @("-ModelId",$OllamaModel) }
Run-Trio "engine:ollama" "_selftest_pie_engine_ollama_v1.ps1" $ollamaArgs "SELFTEST_PIE_ENGINE_OLLAMA_V1_GREEN"

$llamaArgs = @(); if($LlamaCppModel){ $llamaArgs = @("-ModelId",$LlamaCppModel) }
Run-Trio "engine:llamacpp" "_selftest_pie_engine_llamacpp_v1.ps1" $llamaArgs "SELFTEST_PIE_ENGINE_LLAMACPP_V1_GREEN"

$onnxArgs = @(); if($OnnxModelDir){ $onnxArgs = @("-ModelDir",$OnnxModelDir) }
Run-Trio "engine:onnx" "_selftest_pie_engine_onnx_v1.ps1" $onnxArgs "SELFTEST_PIE_ENGINE_ONNX_V1_GREEN"

# --- 5. State layer (release-blocker B1/B2 foundation): schema version guard + atomic writes. ---
Run-Trio "state:migrations" "_selftest_pie_migrations_v1.ps1" @() "SELFTEST_PIE_MIGRATIONS_V1_GREEN"
Run-Trio "state:atomic_write" "_selftest_pie_atomic_write_v1.ps1" @() "SELFTEST_PIE_ATOMIC_WRITE_V1_GREEN"
Run-Trio "state:transaction" "_selftest_pie_txn_v1.ps1" @() "SELFTEST_PIE_TXN_V1_GREEN"
Run-Trio "context:compaction" "_selftest_pie_compaction_v1.ps1" @() "SELFTEST_PIE_COMPACTION_V1_GREEN"

# --- Aggregate + receipt. ---
$fail = @($results | Where-Object { $_.status -eq "fail" }).Count
$pass = @($results | Where-Object { $_.status -eq "pass" }).Count
$inc  = @($results | Where-Object { $_.status -eq "inconclusive" }).Count

$stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss_fff")
$outDir = Join-Path $RepoRoot "runs\engine_verify"
if(-not (Test-Path -LiteralPath $outDir -PathType Container)){ New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
$receipt = [ordered]@{
  schema        = "pie.engine.verify.report.v1"
  generated_utc = (Get-Date).ToUniversalTime().ToString("o")
  repo_root     = $RepoRoot
  totals        = [ordered]@{ pass=$pass; fail=$fail; inconclusive=$inc }
  green         = ($fail -eq 0)
  checks        = $results
}
$enc = New-Object System.Text.UTF8Encoding($false)
$json = ($receipt | ConvertTo-Json -Depth 8)
[System.IO.File]::WriteAllText((Join-Path $outDir ($stamp + ".json")), $json, $enc)
[System.IO.File]::WriteAllText((Join-Path $outDir "latest.json"), $json, $enc)

Write-Host ("SUMMARY pass=" + $pass + " fail=" + $fail + " inconclusive=" + $inc) -ForegroundColor Cyan
if($fail -eq 0){
  Write-Host "PIE_ENGINE_VERIFY_ALL_V1_GREEN" -ForegroundColor Green
} else {
  throw ("PIE_ENGINE_VERIFY_ALL_V1_FAIL: " + $fail + " check(s) failed; see runs\engine_verify\latest.json")
}
