param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Certification for deterministic conversation compaction (release-blocker B6 foundation).
# check1  over-budget history drops oldest turns, keeps newest, retains pinned facts, records drops.
# check2  nothing is silent: a compaction marker + dropped-hash list are present.
# check3  deterministic: identical input -> identical output.
# check4  pinned facts survive even at a tiny budget.
# Emits SELFTEST_PIE_COMPACTION_V1_GREEN.

function Die([string]$m){ throw ("SELFTEST_COMPACTION_FAIL: " + $m) }

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $RepoRoot "scripts\_lib_pie_compaction_v1.ps1")

# Build 10 synthetic turns with distinct, findable content.
$Turns = @(1..10 | ForEach-Object {
  [pscustomobject]@{ turn_sha256 = ("hash{0:D2}" -f $_); message = ("MSG_" + $_); response = ("RESP_" + $_) }
})
$Pinned = @("user prefers PowerShell 5.1", "project root is C:\dev\pie")

Write-Host "PIE_COMPACTION_SELFTEST_START" -ForegroundColor DarkCyan

# check1/check2: budget that fits only the last few turns.
$r = PIE_CompactContext -Turns $Turns -MaxChars 200 -PinnedFacts $Pinned
if($r.dropped_count -le 0){ Die "expected some turns to be dropped under a tight budget" }
if($r.kept_count -le 0){ Die "expected at least one recent turn to survive" }
if($r.rendered -notmatch 'MSG_10'){ Die "most recent turn was not kept" }
if($r.rendered -match 'MSG_1\b'){ Die "oldest turn should have been dropped" }
foreach($p in $Pinned){ if($r.rendered -notmatch [regex]::Escape($p)){ Die ("pinned fact missing: " + $p) } }
if($r.rendered -notmatch 'earlier turn\(s\) compacted'){ Die "no compaction marker (silent drop)" }
if(@($r.dropped_turn_sha256).Count -ne $r.dropped_count){ Die "dropped hash list count mismatch" }
if($r.dropped_turn_sha256[0] -ne "hash01"){ Die "dropped list should start at the oldest turn" }
Write-Host ("  check1_2_drop_keep_record: OK (kept=" + $r.kept_count + " dropped=" + $r.dropped_count + ")") -ForegroundColor Green

# check3: determinism.
$r2 = PIE_CompactContext -Turns $Turns -MaxChars 200 -PinnedFacts $Pinned
if($r2.rendered -ne $r.rendered){ Die "compaction not deterministic (rendered differs)" }
if((@($r2.dropped_turn_sha256) -join ",") -ne (@($r.dropped_turn_sha256) -join ",")){ Die "compaction not deterministic (dropped set differs)" }
Write-Host "  check3_deterministic: OK" -ForegroundColor Green

# check4: pinned facts survive a tiny budget (even if all turns drop).
$r3 = PIE_CompactContext -Turns $Turns -MaxChars 20 -PinnedFacts $Pinned
foreach($p in $Pinned){ if($r3.rendered -notmatch [regex]::Escape($p)){ Die ("pinned fact dropped at tiny budget: " + $p) } }
Write-Host ("  check4_pinned_survive_tiny_budget: OK (dropped=" + $r3.dropped_count + ")") -ForegroundColor Green

$rcptDir = Join-Path $RepoRoot "runs\compaction_selftest"
if(-not (Test-Path -LiteralPath $rcptDir -PathType Container)){ New-Item -ItemType Directory -Path $rcptDir -Force | Out-Null }
$enc = New-Object System.Text.UTF8Encoding($false)
$stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss_fff")
$receipt = [ordered]@{ schema="pie.compaction.selftest.receipt.v1"; generated_utc=(Get-Date).ToUniversalTime().ToString("o"); checks=4; green=$true }
[System.IO.File]::WriteAllText((Join-Path $rcptDir ($stamp + ".json")), ($receipt | ConvertTo-Json -Depth 5), $enc)

Write-Host "SELFTEST_PIE_COMPACTION_V1_GREEN" -ForegroundColor Green
