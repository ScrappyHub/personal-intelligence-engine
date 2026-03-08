param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
function Die([string]$m){ throw $m }
function Write-Utf8NoBomLf([string]$Path,[string]$Text){ $dir=Split-Path -Parent $Path; if($dir -and -not(Test-Path -LiteralPath $dir -PathType Container)){ New-Item -ItemType Directory -Force -Path $dir | Out-Null }; $t=$Text.Replace("`r`n","`n").Replace("`r","`n"); if(-not $t.EndsWith("`n")){ $t += "`n" }; $enc=New-Object System.Text.UTF8Encoding($false); [System.IO.File]::WriteAllText($Path,$t,$enc) }
function Read-Utf8NoBom([string]$Path){ if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("MISSING_FILE: " + $Path) }; $enc=New-Object System.Text.UTF8Encoding($false); return [System.IO.File]::ReadAllText($Path,$enc) }
function Parse-GateText([string]$Text){ [void][ScriptBlock]::Create($Text) }

$RepoRoot = $RepoRoot.TrimEnd("\")
$wbsDir = Join-Path $RepoRoot "docs\wbs"
if (-not (Test-Path -LiteralPath $wbsDir -PathType Container)) { New-Item -ItemType Directory -Force -Path $wbsDir | Out-Null }
$wbsPath = Join-Path $wbsDir "PIE_WBS_PROGRESS_LEDGER_v1.md"

# ---------------- WBS / Progress Ledger (Tier-0 standalone) ----------------
$md = New-Object System.Collections.Generic.List[string]
[void]$md.Add("# PIE WBS + Progress Ledger (Standalone Tier-0) v1")
[void]$md.Add("")
[void]$md.Add("Scope: PIE must stand alone. No ecosystem integrations required until proven.")
[void]$md.Add("Rule: Every checkbox requires a proof artifact path inside the repo so we never re-chase work.")
[void]$md.Add("")
[void]$md.Add("## A. Repo determinism + proof-of-work hygiene")
[void]$md.Add("- [ ] A1 Deterministic scripts: UTF-8 no BOM + LF; parse-gated runners committed")
[void]$md.Add("  - Proof: docs\wbs\PIE_WBS_PROGRESS_LEDGER_v1.md (this file)")
[void]$md.Add("- [ ] A2 Always-on transcripts for key actions (build/seal/verify/sign)")
[void]$md.Add("  - Proof: proofs\runs\pie0\ (stdout+stderr captures, hashes)")
[void]$md.Add("")
[void]$md.Add("## B. Run creation + sealing (standalone)")
[void]$md.Add("- [ ] B1 Seal script produces a run folder deterministically")
[void]$md.Add("  - Proof: proofs\runs\pie0\seal_transcript.txt")
[void]$md.Add("- [ ] B2 Run id determinism rules documented (what changes run_id vs content hash)")
[void]$md.Add("  - Proof: docs\SPEC_RUN_ID.md")
[void]$md.Add("")
[void]$md.Add("## C. Packet build (Option A) + verification (standalone)")
[void]$md.Add("- [ ] C1 Build produces packet folder with manifest.json + packet_id.txt + sha256sums.txt")
[void]$md.Add("  - Proof: proofs\runs\pie0\packet_build_transcript.txt")
[void]$md.Add("- [ ] C2 Verifier passes on-disk bytes (no mutation), emits deterministic verify receipt")
[void]$md.Add("  - Proof: proofs\runs\pie0\verify_transcript.txt")
[void]$md.Add("")
[void]$md.Add("## D. Signing reliability (no more signer chase)")
[void]$md.Add("- [ ] D1 Signer does not treat ssh-keygen stderr info as failure; gates only on exit code")
[void]$md.Add("  - Proof: proofs\runs\pie0\sign_stdout.txt and proofs\runs\pie0\sign_stderr.txt")
[void]$md.Add("- [ ] D2 End-to-end smoke: seal -> build -Sign -> verify -RequireSig succeeds")
[void]$md.Add("  - Proof: proofs\runs\pie0\smoke_transcript.txt")
[void]$md.Add("")
[void]$md.Add("## E. Offline AI runtime deliverable (Tier-0)")
[void]$md.Add("- [ ] E1 Minimal offline inference loop runs locally (no network required)")
[void]$md.Add("  - Proof: proofs\runs\pie0\offline_infer_transcript.txt")
[void]$md.Add("- [ ] E2 Repro instructions pinned (model file hashes, config hashes, deterministic args)")
[void]$md.Add("  - Proof: docs\OFFLINE_RUNBOOK.md")
[void]$md.Add("")
[void]$md.Add("## Current status (auto-notes)")
[void]$md.Add("- Signer already has LASTEXITCODE gating attempt(s), but stderr \"Signing file\" still bubbles up in outer capture paths.")
[void]$md.Add("- Next fix: signer must use Start-Process redirect to files + exit code gate; outer callers should parse OK lines without throwing on stderr noise.")

$mdText = (($md.ToArray()) -join "`n") + "`n"
Write-Utf8NoBomLf $wbsPath $mdText
Write-Host ("WROTE_WBS: " + $wbsPath) -ForegroundColor Green

# ---------------- Patch signer to Start-Process capture ----------------
$sp = Join-Path $RepoRoot "scripts\pie_run_packet_sign_v1.ps1"
if (-not (Test-Path -LiteralPath $sp -PathType Leaf)) { Die ("missing signer: " + $sp) }
$bak = $sp + ".bak_" + (Get-Date -Format "yyyyMMdd_HHmmss")
Copy-Item -LiteralPath $sp -Destination $bak -Force | Out-Null
$txt = Read-Utf8NoBom $sp
$sent = "# --- PIE_PATCH_SIGNER_SSHKEYGEN_STARTPROCESS_V1 ---"
if ($txt -like ("*" + $sent + "*")) { Write-Host ("OK: signer already Start-Process patched (backup=" + $bak + ")") -ForegroundColor Yellow; return }

$ls = $txt -split "`n"
$idx = -1
for($i=0;$i -lt $ls.Length;$i++){
  $ln = $ls[$i]
  if($ln -match '(?i)^\s*\$signOut\s*=\s*&\s*\$ssh\b.*\b-Y\b.*\bsign\b.*\s2>&1\s*$'){ $idx=$i; break }
}
if ($idx -lt 0) {
  $sn=@()
  $sn += "patch_fail: could not find `$signOut = & `$ssh -Y sign ... 2>&1 line."
  $sn += ("backup=" + $bak)
  $sn += "DIAG: candidate lines:"
  for($j=0;$j -lt $ls.Length;$j++){ $l2=$ls[$j]; if($l2 -match "(?i)\bsignOut\b|\bssh\b|\b-Y\b|\bsign\b|2>&1|LASTEXITCODE"){ $sn += ("L" + ($j+1) + ": " + $l2.TrimEnd()) } }
  Die (($sn -join "`n"))
}

# Remove the signOut line + immediate LASTEXITCODE gate blocks after it (window 16 lines)
$rmStart = $idx
$rmEnd = $idx
$max = [Math]::Min($ls.Length-1, $idx + 16)
for($k=$idx+1; $k -le $max; $k++){
  $t = $ls[$k].Trim()
  if ($t -match '(?i)^\s*if\s*\(\s*\$LASTEXITCODE\s*-ne\s*0\s*\)' -or $t -match '(?i)^\s*\$o\s*=\s*@\(@\(\$signOut\)\)' -or $t -match '(?i)ssh-keygen\s*-Y\s*sign\s*failed' -or $t -match '(?i)ssh_keygen_sign_failed' -or $t -match '(?i)^\s*\}' ) { $rmEnd = $k; continue }
  if ($rmEnd -gt $idx) { break }
}

# Indent from original signOut line
$indent = ""
$im = [regex]::Match($ls[$idx], '^(?<i>\s*)\$signOut\b')
if ($im.Success) { $indent = $im.Groups["i"].Value }

# Replacement: Start-Process with redirected stdout/stderr, ExitCode gate
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

# Splice lines
$out = New-Object System.Collections.Generic.List[string]
for($i=0;$i -lt $ls.Length;$i++){
  if ($i -eq $rmStart) { foreach($nl in $new){ [void]$out.Add($nl) }; $i = $rmEnd; continue }
  [void]$out.Add($ls[$i])
}
$txt2 = (($out.ToArray()) -join "`n") + "`n"
Parse-GateText $txt2
Write-Utf8NoBomLf $sp $txt2
Write-Host ("PATCH_OK: signer now uses Start-Process capture + ExitCode gate (backup=" + $bak + ")") -ForegroundColor Green
