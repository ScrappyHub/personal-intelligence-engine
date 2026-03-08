param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
function Die([string]$m){ throw $m }
function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $t = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if (-not $t.EndsWith("`n")) { $t += "`n" }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}
function Read-Utf8NoBom([string]$Path){ if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("MISSING_FILE: " + $Path) }; $enc=New-Object System.Text.UTF8Encoding($false); return [System.IO.File]::ReadAllText($Path,$enc) }
function Parse-GateText([string]$Text){ [void][ScriptBlock]::Create($Text) }

$RepoRoot = $RepoRoot.TrimEnd("\")
$WbsDir = Join-Path $RepoRoot "docs\wbs"
if (-not (Test-Path -LiteralPath $WbsDir -PathType Container)) { New-Item -ItemType Directory -Force -Path $WbsDir | Out-Null }
$WbsPath = Join-Path $WbsDir "PIE_WBS_PROGRESS_LEDGER_v1.md"
$md = New-Object System.Collections.Generic.List[string]
[void]$md.Add("# PIE — WBS + Progress Ledger (Standalone Tier-0) — v1")
[void]$md.Add("")
[void]$md.Add("**Purpose:** PIE must stand alone (Tier-0). No ecosystem integrations required until PIE proves deterministic offline truth, repeatable runs, and sealed transport artifacts.")
[void]$md.Add("")
[void]$md.Add("## Rules (non-negotiable)")
[void]$md.Add("- Deterministic bytes: UTF-8 no BOM + LF. Canonical JSON when used.")
[void]$md.Add("- Every script change is parse-gated before execution.")
[void]$md.Add("- No guessing: every completed step must have a proof artifact path recorded here.")
[void]$md.Add("- Standalone first: no BridgeKit/Echo/NFL/Watchtower dependencies for Tier-0.")
[void]$md.Add("")
[void]$md.Add("## Current focus gate: PIE-0")
[void]$md.Add("**PIE-0 = seal -> build signed run packet -> require-sig verify passes**")
[void]$md.Add("")
[void]$md.Add("### Required proof artifacts for PIE-0 (must exist to mark DONE)")
[void]$md.Add("- [ ] Transcript: `proofs\\runs\\pie0\\smoke_transcript.txt` (capture of console output)")
[void]$md.Add("- [ ] Packet dir: `packets\\outbox\\<packet_id>\\` (actual produced folder)")
[void]$md.Add("- [ ] Signature file exists: `packets\\outbox\\<packet_id>\\signatures\\sig_envelope.sig`")
[void]$md.Add("- [ ] Verifier transcript: `proofs\\runs\\pie0\\verify_transcript.txt`")
[void]$md.Add("- [ ] Hash snapshot: `proofs\\runs\\pie0\\packet_hashes.txt` (sha256 of key files)")
[void]$md.Add("")
[void]$md.Add("## Work Breakdown Structure (WBS)")
[void]$md.Add("")
[void]$md.Add("### A. Repo determinism + evidence hygiene")
[void]$md.Add("- [ ] A1 Create `proofs\\runs\\` structure for PIE")
[void]$md.Add("- [ ] A2 Add `docs\\wbs\\` and keep this ledger updated per change")
[void]$md.Add("- [ ] A3 Add `docs\\wbs\\CHANGELOG.md` entries with links to proof artifacts")
[void]$md.Add("")
[void]$md.Add("### B. Run lifecycle (offline)")
[void]$md.Add("- [ ] B1 `scripts\\pie_run_seal_v1.ps1` creates/updates a run deterministically")
[void]$md.Add("  - Proof: `proofs\\runs\\b1\\seal_transcript.txt`")
[void]$md.Add("- [ ] B2 Run id determinism rules documented (what changes it, what does not)")
[void]$md.Add("  - Proof: `docs\\SPEC_RUN_ID.md`")
[void]$md.Add("")
[void]$md.Add("### C. Packet build (Option A transport shape, standalone)")
[void]$md.Add("- [ ] C1 Builder emits OK line with packet_id+run_id+dir")
[void]$md.Add("  - Proof: `proofs\\runs\\c1\\build_transcript.txt`")
[void]$md.Add("- [ ] C2 Packet directory contains required files (manifest/sha256sums/packet_id/signatures/payload)")
[void]$md.Add("  - Proof: `proofs\\runs\\c2\\packet_tree.txt`")
[void]$md.Add("")
[void]$md.Add("### D. Signing reliability (PS5.1 native stderr hardening)")
[void]$md.Add("- [ ] D1 Signer does **not** throw on ssh-keygen stderr when ExitCode=0")
[void]$md.Add("  - Proof: `proofs\\runs\\d1\\sign_transcript.txt`")
[void]$md.Add("- [ ] D2 Signer gates on process ExitCode and captures stdout+stderr deterministically")
[void]$md.Add("  - Proof: patch transcript + signer diff")
[void]$md.Add("")
[void]$md.Add("### E. Verify (RequireSig)")
[void]$md.Add("- [ ] E1 `scripts\\packet_verify_v1.ps1 -RequireSig` passes on produced packet")
[void]$md.Add("  - Proof: `proofs\\runs\\e1\\verify_transcript.txt`")
[void]$md.Add("")
[void]$md.Add("### F. Selftests + golden vectors (standalone)")
[void]$md.Add("- [ ] F1 Add `scripts\\selftest_pie_transport_v1.ps1` that builds+verifies a minimal packet")
[void]$md.Add("- [ ] F2 Add `test_vectors\\pie\\transport_v1\\` with golden expected PacketId + sha256sums")
[void]$md.Add("")
[void]$md.Add("## Progress Notes (append-only)")
[void]$md.Add("- 2026-02-18: signer instability due to PS5.1 native stderr (`Signing file ...`) turning into terminating error under `$ErrorActionPreference=Stop`. Fix: Start-Process redirect + ExitCode gate.")

$mdText = (($md.ToArray()) -join "`n") + "`n"
Write-Utf8NoBomLf $WbsPath $mdText
Write-Host ("WROTE: " + $WbsPath) -ForegroundColor Green

$sp = Join-Path $RepoRoot "scripts\pie_run_packet_sign_v1.ps1"
if (-not (Test-Path -LiteralPath $sp -PathType Leaf)) { Die ("MISSING_SIGNER: " + $sp) }
$bak = $sp + ".bak_" + (Get-Date -Format "yyyyMMdd_HHmmss")
Copy-Item -LiteralPath $sp -Destination $bak -Force | Out-Null
$raw = Read-Utf8NoBom $sp
$txt = $raw.Replace("`r`n","`n").Replace("`r","`n")
$sent = "# --- PIE_PATCH_SIGNER_SSHKEYGEN_STARTPROCESS_V1 ---"
if ($txt -like ("*" + $sent + "*")) { Write-Host ("OK: signer already Start-Process patched (backup=" + $bak + ")") -ForegroundColor Yellow; return }
$ls = $txt -split "`n"

# Find the ssh-keygen sign line (accept with or without 2>&1)
$idx = -1
for($i=0;$i -lt $ls.Length;$i++){
  $ln = $ls[$i]
  if ($ln -match '(?i)^\s*\$signOut\s*=\s*&\s*\$ssh\b.*\b-Y\b.*\bsign\b.*$') { $idx=$i; break }
}
if ($idx -lt 0) {
  $sn=@(); $sn += "patch_fail: could not find `$signOut = & `$ssh -Y sign ... line."; $sn += ("backup=" + $bak); $sn += "DIAG: candidate lines:"
  for($j=0;$j -lt $ls.Length;$j++){ $l2=$ls[$j]; if($l2 -match "(?i)\bsignOut\b|\bssh\b|\b-Y\b|\bsign\b|2>&1|LASTEXITCODE"){ $sn += ("L" + ($j+1) + ": " + $l2.TrimEnd()) } }
  Die (($sn -join "`n"))
}

# Remove immediate follow-on LASTEXITCODE/signOut gate lines after idx (bounded)
$rmStart = $idx
$rmEnd   = $idx
$max = [Math]::Min($ls.Length-1, $idx + 20)
for($k=$idx+1; $k -le $max; $k++){
  $t = $ls[$k].Trim()
  if ($t -match '(?i)^\s*if\s*\(\s*\$LASTEXITCODE\s*-ne\s*0\s*\)' -or
      $t -match '(?i)^\s*\$o\s*=\s*@\(@\(\$signOut\)\)' -or
      $t -match '(?i)ssh-keygen\s*-Y\s*sign\s*failed' -or
      $t -match '(?i)ssh_keygen_sign_failed' -or
      $t -match '(?i)^\s*\}\s*$' ) { $rmEnd = $k; continue }
  if ($rmEnd -gt $idx) { break }
}

# Indent from original signOut line
$indent = ""
$im = [regex]::Match($ls[$idx], '^(?<i>\s*)\$signOut\b')
if ($im.Success) { $indent = $im.Groups["i"].Value }

# Replacement block: Start-Process with redirected stdout/stderr and ExitCode gate
$new = New-Object System.Collections.Generic.List[string]
[void]$new.Add($indent + $sent)
[void]$new.Add($indent + '$tmpOut = $envPath + ".sshkeygen.out.txt"')
[void]$new.Add($indent + '$tmpErr = $envPath + ".sshkeygen.err.txt"')
[void]$new.Add($indent + 'if (Test-Path -LiteralPath $tmpOut -PathType Leaf) { Remove-Item -LiteralPath $tmpOut -Force -ErrorAction SilentlyContinue }')
[void]$new.Add($indent + 'if (Test-Path -LiteralPath $tmpErr -PathType Leaf) { Remove-Item -LiteralPath $tmpErr -Force -ErrorAction SilentlyContinue }')
[void]$new.Add($indent + '$args = @("-Y","sign","-f",$key,"-n",$Namespace,"-I",$Principal,$envPath)' )
[void]$new.Add($indent + '$proc = Start-Process -FilePath $ssh -ArgumentList $args -NoNewWindow -Wait -PassThru -RedirectStandardOutput $tmpOut -RedirectStandardError $tmpErr' )
[void]$new.Add($indent + '$signOut = @()' )
[void]$new.Add($indent + 'if (Test-Path -LiteralPath $tmpOut -PathType Leaf) { $signOut += @(@((Get-Content -LiteralPath $tmpOut -Encoding UTF8))) }' )
[void]$new.Add($indent + 'if (Test-Path -LiteralPath $tmpErr -PathType Leaf) { $signOut += @(@((Get-Content -LiteralPath $tmpErr -Encoding UTF8))) }' )
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
