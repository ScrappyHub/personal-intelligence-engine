param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Certification for the schema migration framework (release-blocker B1 foundation).
# Positive: a current-version object passes the guard and round-trips unchanged.
# Negative: unknown schema fails closed; a version newer than known fails closed (no downgrade);
#           a registered migration path is applied idempotently.
# Emits SELFTEST_PIE_MIGRATIONS_V1_GREEN on success.

function Die([string]$m){ throw ("SELFTEST_MIGRATIONS_FAIL: " + $m) }

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $RepoRoot "scripts\_lib_pie_migrations_v1.ps1")

$reg = PIE_LoadSchemaRegistry $RepoRoot
Write-Host "PIE_MIGRATIONS_SELFTEST_START" -ForegroundColor DarkCyan

# Positive: a known current schema passes.
$cur = PIE_CurrentSchemaVersion $reg "run_record.v1"
if($cur -ne 1){ Die "run_record current version expected 1" }
$obj = [pscustomobject]@{ schema = "run_record.v1"; run_id = "x" }
$out = PIE_MigrateObject $reg $obj
if($out.schema -ne "run_record.v1"){ Die "current object should round-trip unchanged" }
Write-Host "  check1_current_roundtrip: OK" -ForegroundColor Green

# Negative: unknown schema fails closed.
$threw = $false
try { [void](PIE_AssertKnownSchema $reg "pie.totally.unknown.v1") } catch { $threw = $true; if($_.Exception.Message -notmatch 'PIE_SCHEMA_UNKNOWN'){ Die ("wrong error: " + $_.Exception.Message) } }
if(-not $threw){ Die "unknown schema was accepted" }
Write-Host "  check2_unknown_fails_closed: OK" -ForegroundColor Green

# Negative: a version newer than known fails closed (refuse downgrade).
$threw = $false
try { [void](PIE_AssertKnownSchema $reg "run_record.v2") } catch { $threw = $true; if($_.Exception.Message -notmatch 'PIE_SCHEMA_VERSION_TOO_NEW'){ Die ("wrong error: " + $_.Exception.Message) } }
if(-not $threw){ Die "newer-than-known version was accepted" }
Write-Host "  check3_too_new_fails_closed: OK" -ForegroundColor Green

# Positive: a registered migration path is applied idempotently.
PIE_RegisterMigration "pie.selftest.demo" 1 2 { param($o) $o | Add-Member -NotePropertyName migrated -NotePropertyValue $true -Force; $o }
# Temporarily teach the guard about the demo schema by faking a registry entry.
$demoReg = [pscustomobject]@{ schemas = @([pscustomobject]@{ id="pie.selftest.demo.v2"; current=2 }) }
$demoObj = [pscustomobject]@{ schema = "pie.selftest.demo.v1" }
$demoOut = PIE_MigrateObject $demoReg $demoObj
if($demoOut.schema -ne "pie.selftest.demo.v2"){ Die "migration did not advance version" }
if(-not $demoOut.migrated){ Die "migration fn did not run" }
# Idempotent: running again at current is a no-op.
$demoOut2 = PIE_MigrateObject $demoReg $demoOut
if($demoOut2.schema -ne "pie.selftest.demo.v2"){ Die "second migration pass mutated version" }
Write-Host "  check4_migration_path_applied: OK" -ForegroundColor Green

# Receipt.
$stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss_fff")
$outDir = Join-Path $RepoRoot "runs\migrations_selftest"
if(-not (Test-Path -LiteralPath $outDir -PathType Container)){ New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
$enc = New-Object System.Text.UTF8Encoding($false)
$receipt = [ordered]@{ schema="pie.migrations.selftest.receipt.v1"; generated_utc=(Get-Date).ToUniversalTime().ToString("o"); checks=4; green=$true }
[System.IO.File]::WriteAllText((Join-Path $outDir ($stamp + ".json")), ($receipt | ConvertTo-Json -Depth 5), $enc)

Write-Host "SELFTEST_PIE_MIGRATIONS_V1_GREEN" -ForegroundColor Green
