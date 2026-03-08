param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
function Die([string]$m){ throw $m }
function Read-Utf8NoBom([string]$Path){ if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("MISSING_FILE: " + $Path) }; $enc=New-Object System.Text.UTF8Encoding($false); return [System.IO.File]::ReadAllText($Path,$enc) }
function Write-Utf8NoBomLf([string]$Path,[string]$Text){ $dir=Split-Path -Parent $Path; if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){ New-Item -ItemType Directory -Force -Path $dir | Out-Null }; $t=$Text.Replace("`r`n","`n").Replace("`r","`n"); if(-not $t.EndsWith("`n")){ $t += "`n" }; $enc=New-Object System.Text.UTF8Encoding($false); [System.IO.File]::WriteAllText($Path,$t,$enc) }
function Parse-GateText([string]$Text){ [void][ScriptBlock]::Create($Text) }

$RepoRoot = $RepoRoot.TrimEnd("\")

# ===============================
# 1) WRITE: docs/wbs/PIE_WBS_PROGRESS_LEDGER_v1.md
# ===============================
$wbsDir = Join-Path $RepoRoot "docs\wbs"
if (-not (Test-Path -LiteralPath $wbsDir -PathType Container)) { New-Item -ItemType Directory -Force -Path $wbsDir | Out-Null }
$wbsPath = Join-Path $wbsDir "PIE_WBS_PROGRESS_LEDGER_v1.md"
$md = New-Object System.Collections.Generic.List[string]
[void]$md.Add('# PIE WBS + Progress Ledger (Tier-0 Standalone) v1')
[void]$md.Add('')
[void]$md.Add('WHAT THIS PROJECT IS TO SPEC')
[void]$md.Add('- PIE is a Tier-0 Standalone offline-first personal AI engine runtime.')
[void]$md.Add('- It must stand alone (no ecosystem integrations required) until proven and built.')
[void]$md.Add('- It produces deterministic run export packets: seal -> build -> sign -> verify -> receipts.')
[void]$md.Add('- Transport: Packet Constitution v1 Option A (manifest without packet_id; packet_id.txt derived; sha256sums last; verify non-mutating).' )
[void]$md.Add('')
[void]$md.Add('Progress snapshot (2026-02-21)' )
[void]$md.Add('- Spec completeness: ~35%' )
[void]$md.Add('- Standalone instrument readiness: ~20%' )
[void]$md.Add('- Current state: structurally formed, not yet end-to-end green due to signing + runner quoting failures.' )
[void]$md.Add('')
[void]$md.Add('WBS Domains (A-H) with required proofs' )
[void]$md.Add('')
[void]$md.Add('### A) Repo determinism + hygiene' )
[void]$md.Add('- [ ] A1 Deterministic rule enforced: write-to-file + parse-gate + powershell.exe -File only' )
[void]$md.Add('  - Proof: scripts/_scratch runners + this ledger committed' )
[void]$md.Add('- [ ] A2 UTF-8 no BOM + LF invariant verified for generated artifacts' )
[void]$md.Add('  - Proof: proofs/audit/utf8_lf_check.txt' )
[void]$md.Add('')
[void]$md.Add('### B) Run model: seal -> build -> verify (standalone)' )
[void]$md.Add('- [ ] B1 Seal creates run folder deterministically (run_id rules documented)' )
[void]$md.Add('  - Proof: docs/SPEC_RUN_MODEL.md + proofs/runs/pie0/seal_transcript.txt' )
[void]$md.Add('- [ ] B2 Build emits packet_id + run_id + absolute packet path' )
[void]$md.Add('  - Proof: proofs/runs/pie0/build_transcript.txt' )
[void]$md.Add('- [ ] B3 Verify produces deterministic non-mutating verification transcript+receipt' )
[void]$md.Add('  - Proof: proofs/runs/pie0/verify_transcript.txt + proofs/runs/pie0/verify_receipt.json' )
[void]$md.Add('')
[void]$md.Add('### C) Signing reliability (NO REPEAT CHASE)' )
[void]$md.Add('- [ ] C1 signer uses non-terminating capture so stderr "Signing file ..." can never throw' )
[void]$md.Add('  - Proof: scripts/pie_run_packet_sign_v1.ps1 contains sentinel + sign transcript' )
[void]$md.Add('- [ ] C2 signer gates on ExitCode and includes stdout+stderr in failure message' )
[void]$md.Add('  - Proof: negative vector + transcript showing captured output' )
[void]$md.Add('')
[void]$md.Add('### D) Packet Constitution v1 Option A compliance' )
[void]$md.Add('- [ ] D1 PacketId = SHA-256(canonical manifest-without-id bytes) locked' )
[void]$md.Add('  - Proof: docs/PACKET_SPEC_PIE.md + test_vectors/**/expected_packet_id.txt' )
[void]$md.Add('- [ ] D2 sha256sums generated LAST; verifier never mutates packet' )
[void]$md.Add('  - Proof: verify transcript shows read-only behavior' )
[void]$md.Add('')
[void]$md.Add('### E) Offline spin-up impact goal (water waste reduction)' )
[void]$md.Add('- [ ] E1 Offline runtime plan documented (device reqs, pinned models, offline inference path)' )
[void]$md.Add('  - Proof: docs/SPEC_OFFLINE_RUNTIME.md' )
[void]$md.Add('- [ ] E2 "cloud avoided" metric defined (requests avoided, kWh proxy, time)' )
[void]$md.Add('  - Proof: docs/SPEC_IMPACT_METRICS.md' )
[void]$md.Add('')
[void]$md.Add('### F) Golden vectors + selftests' )
[void]$md.Add('- [ ] F1 Minimal packet vector committed with expected packet_id + sha256sums' )
[void]$md.Add('  - Proof: test_vectors/** + proofs/runs/pie0/golden_verify.txt' )
[void]$md.Add('- [ ] F2 Deterministic replay rules documented (only claim replay when pinned inputs/versions/env)' )
[void]$md.Add('  - Proof: docs/SPEC_REPLAY_STRENGTH.md' )
[void]$md.Add('')
[void]$md.Add('### G) Audit / evidence discipline' )
[void]$md.Add('- [ ] G1 Every repair has: patch script, backup path, transcript, and receipt line' )
[void]$md.Add('  - Proof: proofs/audit/patch_log.ndjson (append-only)' )
[void]$md.Add('')
[void]$md.Add('### H) Deferred ecosystem (Tier-2) - NOT REQUIRED YET' )
[void]$md.Add('- [ ] H1 NFL duplication (deferred)' )
[void]$md.Add('- [ ] H2 WatchTower verification (deferred)' )
[void]$md.Add('')
[void]$md.Add('Current blocker list' )
[void]$md.Add('- Runner parse failures caused by invalid C-style escaping sequences in generated PowerShell source.' )
[void]$md.Add('- Signer path must never allow ssh-keygen stderr to become a terminating error.' )
[void]$md.Add('')
$mdText = (($md.ToArray()) -join "`n") + "`n"
Write-Utf8NoBomLf $wbsPath $mdText
Write-Host ("WROTE_WBS_OK: " + $wbsPath) -ForegroundColor Green

# ===============================
# 2) PATCH: scripts/pie_run_packet_sign_v1.ps1 -> Start-Process capture
# ===============================
$sp = Join-Path $RepoRoot "scripts\pie_run_packet_sign_v1.ps1"
if (-not (Test-Path -LiteralPath $sp -PathType Leaf)) { Die ("MISSING_SIGNER: " + $sp) }
$bak2 = $sp + ".bak_" + (Get-Date -Format "yyyyMMdd_HHmmss")
Copy-Item -LiteralPath $sp -Destination $bak2 -Force | Out-Null
$txtS = Read-Utf8NoBom $sp
$sent = "# --- PIE_PATCH_SIGNER_SSHKEYGEN_STARTPROCESS_V1 ---"
if ($txtS -like ("*" + $sent + "*")) { Write-Host ("OK: signer already patched (backup=" + $bak2 + ")") -ForegroundColor Yellow; return }
$ls = $txtS -split "`n"
$idx = -1
for($i=0;$i -lt $ls.Length;$i++){
  if($ls[$i] -match '(?i)^\s*\$signOut\s*=\s*&\s*\$ssh\b.*\b-Y\b.*\bsign\b.*2>&1\s*$'){ $idx=$i; break }
}
if ($idx -lt 0) {
  $sn=@(); $sn+="patch_fail: could not find signOut ssh-keygen sign line."; $sn+=("backup=" + $bak2);
  for($j=0;$j -lt $ls.Length;$j++){ $l2=$ls[$j]; if($l2 -match "(?i)\bsignOut\b|\bssh\b|\b-Y\b|\bsign\b|2>&1|LASTEXITCODE"){ $sn+=("L"+($j+1)+": "+$l2.TrimEnd()) } }
  Die (($sn -join "`n"))
}
# remove the assignment line + any immediate LASTEXITCODE gates after it (next ~12 lines)
$rmStart = $idx
$rmEnd = $idx
$max = [Math]::Min($ls.Length-1, $idx + 12)
for($k=$idx+1; $k -le $max; $k++){
  $t = $ls[$k].Trim()
  if ($t -match '(?i)^\s*if\s*\(\s*\$LASTEXITCODE\s*-ne\s*0\s*\)' -or $t -match '(?i)ssh-keygen\s*-Y\s*sign\s*failed' -or $t -match '(?i)ssh_keygen_sign_failed' -or $t -match '(?i)^\s*\$o\s*=\s*@\(@\(\$signOut\)\)' -or $t -match '^\s*\}\s*$') { $rmEnd = $k; continue }
  if ($rmEnd -gt $idx) { break }
}
$indent = ""
$im = [regex]::Match($ls[$idx], '^(?<i>\s*)\$signOut\b')
if ($im.Success) { $indent = $im.Groups["i"].Value }
$new = New-Object System.Collections.Generic.List[string]
[void]$new.Add($indent + $sent)
[void]$new.Add($indent + '$tmpOut = $envPath + ".sshkeygen.out.txt"')
[void]$new.Add($indent + '$tmpErr = $envPath + ".sshkeygen.err.txt"')
[void]$new.Add($indent + 'if (Test-Path -LiteralPath $tmpOut -PathType Leaf) { Remove-Item -LiteralPath $tmpOut -Force -ErrorAction SilentlyContinue }')
[void]$new.Add($indent + 'if (Test-Path -LiteralPath $tmpErr -PathType Leaf) { Remove-Item -LiteralPath $tmpErr -Force -ErrorAction SilentlyContinue }')
[void]$new.Add($indent + '$args = @("-Y","sign","-f",$key,"-n",$Namespace,"-I",$Principal,$envPath)' )
[void]$new.Add($indent + '$proc = Start-Process -FilePath $ssh -ArgumentList $args -NoNewWindow -Wait -PassThru -RedirectStandardOutput $tmpOut -RedirectStandardError $tmpErr' )
[void]$new.Add($indent + '$signOut = @()' )
[void]$new.Add($indent + 'if (Test-Path -LiteralPath $tmpOut -PathType Leaf) { $signOut += @(@(Get-Content -LiteralPath $tmpOut -Encoding UTF8)) }' )
[void]$new.Add($indent + 'if (Test-Path -LiteralPath $tmpErr -PathType Leaf) { $signOut += @(@(Get-Content -LiteralPath $tmpErr -Encoding UTF8)) }' )
[void]$new.Add($indent + 'if ($proc.ExitCode -ne 0) {' )
[void]$new.Add($indent + '  $o = @(@($signOut)) -join "`n"' )
[void]$new.Add($indent + '  Die ("ssh-keygen -Y sign failed (exit=" + $proc.ExitCode + "): " + $o)' )
[void]$new.Add($indent + '}' )
$out = New-Object System.Collections.Generic.List[string]
for($i=0;$i -lt $ls.Length;$i++){
  if ($i -eq $rmStart) { foreach($nl in $new){ [void]$out.Add($nl) }; $i = $rmEnd; continue }
  [void]$out.Add($ls[$i])
}
$txtS2 = (($out.ToArray()) -join "`n") + "`n"
Parse-GateText $txtS2
Write-Utf8NoBomLf $sp $txtS2
Write-Host ("PATCH_OK: signer now uses Start-Process capture + ExitCode gate (backup=" + $bak2 + ")") -ForegroundColor Green
