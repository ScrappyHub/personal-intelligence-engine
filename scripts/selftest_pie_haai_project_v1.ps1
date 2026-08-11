param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$false)][string]$HaaiRepo = "C:\dev\haai"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$HaaiRepo = (Resolve-Path -LiteralPath $HaaiRepo).Path
$SessionId = "pie_haai_project_selftest"
$OtherSessionId = "pie_haai_project_other_selftest"
$TestRoot = Join-Path $RepoRoot "runs\pie_haai_project_fixture"
$MemoryRoot = Join-Path $TestRoot "memory"
$PolicyPath = Join-Path $TestRoot "policy.json"
foreach($Path in @($TestRoot,(Join-Path $RepoRoot ("runs\" + $SessionId)),(Join-Path $RepoRoot ("runs\" + $OtherSessionId)))){ if(Test-Path -LiteralPath $Path -PathType Container){ Remove-Item -LiteralPath $Path -Recurse -Force } }
New-Item -ItemType Directory -Force -Path $TestRoot | Out-Null
$Enc = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText($PolicyPath,'{"schema":"pie.memory.policy.v1","mode":"auto_accept","allowed_modes":["ask","auto_accept","manual_only","off"],"default_lane":"active","repo_memory_enabled":true,"project_memory_enabled":true,"coding_memory_enabled":true}', $Enc)

function Get-HaaiCanonicalSnapshot {
  $Roots = @((Join-Path $HaaiRepo "docs\canonical"),(Join-Path $HaaiRepo "core\python\haai_core"))
  return (@($Roots | ForEach-Object { Get-ChildItem -LiteralPath $_ -Recurse -File } | Sort-Object FullName | ForEach-Object {
    $_.FullName.Substring($HaaiRepo.Length).Replace('\','/') + ":" + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
  }) -join "`n")
}
$Before = Get-HaaiCanonicalSnapshot

& (Join-Path $RepoRoot "scripts\pie_agent_start_v1.ps1") -RepoRoot $RepoRoot -SessionId $SessionId -Backend mock -Model "haai-project-mock" -ProjectRepo $HaaiRepo -Goal "inspect HAAI without crossing boundaries" | Out-Null
& (Join-Path $RepoRoot "scripts\pie_agent_start_v1.ps1") -RepoRoot $RepoRoot -SessionId $OtherSessionId -Backend mock -Model "haai-project-mock" -ProjectRepo $RepoRoot -Goal "separate PIE project" | Out-Null
& (Join-Path $RepoRoot "scripts\pie_memory_accept_v1.ps1") -RepoRoot $RepoRoot -Text "HAAI_ONLY_MEMORY_MARKER" -Lane project -Project haai -ProjectRepo $HaaiRepo -MemoryRoot $MemoryRoot -PolicyPath $PolicyPath -Yes | Out-Null
& (Join-Path $RepoRoot "scripts\pie_memory_accept_v1.ps1") -RepoRoot $RepoRoot -Text "PIE_ONLY_MEMORY_MARKER" -Lane project -Project pie -ProjectRepo $RepoRoot -MemoryRoot $MemoryRoot -PolicyPath $PolicyPath -Yes | Out-Null

& (Join-Path $RepoRoot "scripts\pie_memory_resolve_v1.ps1") -RepoRoot $RepoRoot -SessionId $SessionId -Query "memory marker" -MemoryRoot $MemoryRoot -PolicyPath $PolicyPath | Out-Null
$ResolvedPath = Get-ChildItem -LiteralPath (Join-Path $RepoRoot ("runs\" + $SessionId + "\memory_resolve")) -File -Filter "memory_resolution_*.md" | Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty FullName
if([string]::IsNullOrWhiteSpace($ResolvedPath)){ throw "PIE_HAAI_PROJECT_MEMORY_RESOLUTION_MISSING" }
$Resolved = Get-Content -LiteralPath $ResolvedPath -Raw
if($Resolved -notmatch "HAAI_ONLY_MEMORY_MARKER" -or $Resolved -match "PIE_ONLY_MEMORY_MARKER"){ throw "PIE_HAAI_PROJECT_MEMORY_SCOPE_BAD" }

& (Join-Path $RepoRoot "scripts\pie_context_build_v1.ps1") -RepoRoot $RepoRoot -SessionId $SessionId -UserMessage "What is HAAI?" -MemoryRoot $MemoryRoot | Out-Null
$PromptPath = Get-ChildItem -LiteralPath (Join-Path $RepoRoot ("runs\" + $SessionId + "\context_packets")) -File -Filter "context_prompt_*.txt" | Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty FullName
if([string]::IsNullOrWhiteSpace($PromptPath)){ throw "PIE_HAAI_PROJECT_CONTEXT_MISSING" }
$Prompt = Get-Content -LiteralPath $PromptPath -Raw
foreach($Marker in @($HaaiRepo,"Hash Access Artificial Interface","AI evidence","capture and verification instrument","HAAI_ONLY_MEMORY_MARKER")){
  if($Prompt -notmatch [regex]::Escape($Marker)){ throw ("PIE_HAAI_PROJECT_CONTEXT_MISSING: " + $Marker) }
}
if($Prompt -match "PIE_ONLY_MEMORY_MARKER"){ throw "PIE_HAAI_PROJECT_CONTEXT_MEMORY_LEAK" }

& (Join-Path $RepoRoot "scripts\pie_exec_with_snapshot_v1.ps1") -RepoRoot $RepoRoot -SessionId $SessionId -Command "Get-ChildItem -Name" -WorkingDirectory $HaaiRepo -AutoConfirmAllowed | Out-Null
$ReceiptPath = Join-Path $RepoRoot ("runs\" + $SessionId + "\execution\execution_receipts.ndjson")
$ExecReceipt = Get-Content -LiteralPath $ReceiptPath | Select-Object -Last 1 | ConvertFrom-Json
if($null -eq $ExecReceipt -or [int]$ExecReceipt.exit_code -ne 0 -or [string]$ExecReceipt.working_directory -ine $HaaiRepo){ throw "PIE_HAAI_PROJECT_READ_EXECUTION_BAD" }

$After = Get-HaaiCanonicalSnapshot
if($After -ne $Before){ throw "PIE_HAAI_PROJECT_CANONICAL_STATE_MUTATED" }
Write-Host "PIE_HAAI_PROJECT_SELFTEST_OK" -ForegroundColor Green
