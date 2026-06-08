param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$AuditPath,
  [Parameter(Mandatory=$true)][string]$SessionId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$AuditPath = (Resolve-Path -LiteralPath $AuditPath).Path
$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)
$OutRoot = Join-Path $RunRoot "cross_repo_baseline_governance_report"
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

function ShortSha {
  param([string]$Sha)

  if([string]::IsNullOrWhiteSpace($Sha)){
    return ""
  }

  if($Sha.Length -le 16){
    return $Sha
  }

  return $Sha.Substring(0,16)
}

$Audit = Get-Content -LiteralPath $AuditPath -Raw | ConvertFrom-Json

if($Audit.schema -ne "pie.cross.repo.baseline.lineage.audit.v1"){
  throw "PIE_BASELINE_GOVERNANCE_REPORT_AUDIT_SCHEMA_BAD"
}

New-Item -ItemType Directory -Force -Path $OutRoot | Out-Null

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
$MdPath = Join-Path $OutRoot ("baseline_governance_report_" + $Stamp + ".md")
$TxtPath = Join-Path $OutRoot ("baseline_governance_report_" + $Stamp + ".txt")
$LatestMd = Join-Path $OutRoot "latest_baseline_governance_report.md"
$LatestTxt = Join-Path $OutRoot "latest_baseline_governance_report.txt"
$ManifestPath = Join-Path $OutRoot ("baseline_governance_report_" + $Stamp + ".manifest.json")
$LatestManifest = Join-Path $OutRoot "latest_baseline_governance_report.manifest.json"

$Lines = New-Object System.Collections.Generic.List[string]

[void]$Lines.Add("# PIE Cross-Repo Baseline Governance Report")
[void]$Lines.Add("")
[void]$Lines.Add(("Generated UTC: " + [DateTime]::UtcNow.ToString("o")))
[void]$Lines.Add(("Session: " + $SessionId))
[void]$Lines.Add(("Root baseline: " + [string]$Audit.root_baseline_id))
[void]$Lines.Add(("Audit status: " + [string]$Audit.status))
[void]$Lines.Add(("Baseline count: " + [string]$Audit.baseline_count))
[void]$Lines.Add(("Lineage edge count: " + [string]$Audit.edge_count))
[void]$Lines.Add(("Audit artifact: " + $AuditPath))
[void]$Lines.Add(("Audit SHA-256: " + (Sha256File $AuditPath)))
[void]$Lines.Add("")

if(@($Audit.problems).Count -gt 0){
  [void]$Lines.Add("## Problems")
  [void]$Lines.Add("")
  foreach($Problem in @($Audit.problems)){
    [void]$Lines.Add(("- " + [string]$Problem))
  }
  [void]$Lines.Add("")
}
else {
  [void]$Lines.Add("## Problems")
  [void]$Lines.Add("")
  [void]$Lines.Add("No lineage problems were detected.")
  [void]$Lines.Add("")
}

[void]$Lines.Add("## Baselines")
[void]$Lines.Add("")

foreach($B in @($Audit.baselines | Sort-Object baseline_id)){
  [void]$Lines.Add(("### " + [string]$B.baseline_id))
  [void]$Lines.Add("")
  [void]$Lines.Add(("- Status: " + [string]$B.status))
  if(-not [string]::IsNullOrWhiteSpace([string]$B.reason_code)){
    [void]$Lines.Add(("- Reason code: " + [string]$B.reason_code))
  }
  [void]$Lines.Add(("- Aggregate SHA-256: " + [string]$B.aggregate_sha256))
  [void]$Lines.Add(("- Promotion SHA-256: " + [string]$B.promotion_sha256))
  if(-not [string]::IsNullOrWhiteSpace([string]$B.revocation_sha256)){
    [void]$Lines.Add(("- Revocation SHA-256: " + [string]$B.revocation_sha256))
  }
  if(-not [string]::IsNullOrWhiteSpace([string]$B.replacement_sha256)){
    [void]$Lines.Add(("- Replacement SHA-256: " + [string]$B.replacement_sha256))
  }
  [void]$Lines.Add("")
}

[void]$Lines.Add("## Lineage")
[void]$Lines.Add("")

if(@($Audit.edges).Count -eq 0){
  [void]$Lines.Add("No baseline replacement edges were found.")
}
else {
  foreach($E in @($Audit.edges)){
    [void]$Lines.Add(("- " + [string]$E.from + " → " + [string]$E.to + " (" + [string]$E.type + ")"))
    [void]$Lines.Add(("  - Old revoked: " + [string]$E.old_revoked))
    [void]$Lines.Add(("  - Old aggregate: " + (ShortSha ([string]$E.old_aggregate_sha256))))
    [void]$Lines.Add(("  - New aggregate: " + (ShortSha ([string]$E.new_aggregate_sha256))))
  }
}
[void]$Lines.Add("")

[void]$Lines.Add("## Governance Decision")
[void]$Lines.Add("")

if([string]$Audit.status -eq "ok"){
  [void]$Lines.Add("This baseline family is audit-clean. The recorded lineage is internally consistent, hashes match, and the replacement chain can be explained without inspecting raw JSON.")
}
else {
  [void]$Lines.Add("This baseline family needs review. Inspect the Problems section and raw audit artifact before trusting the active baseline.")
}
[void]$Lines.Add("")

$Markdown = ($Lines.ToArray() -join "`n")

$Txt = $Markdown
$Txt = $Txt -replace '^# ',''
$Txt = $Txt -replace '^## ',''
$Txt = $Txt -replace '^### ',''
$Txt = $Txt -replace '\*\*',''

Write-Utf8NoBomLf -Path $MdPath -Text $Markdown
Write-Utf8NoBomLf -Path $TxtPath -Text $Txt
Write-Utf8NoBomLf -Path $LatestMd -Text $Markdown
Write-Utf8NoBomLf -Path $LatestTxt -Text $Txt

$Manifest = [ordered]@{
  schema = "pie.cross.repo.baseline.governance.report.v1"
  session_id = $SessionId
  audit = $AuditPath
  audit_sha256 = Sha256File $AuditPath
  markdown = $MdPath
  markdown_sha256 = Sha256File $MdPath
  text = $TxtPath
  text_sha256 = Sha256File $TxtPath
  latest_markdown = $LatestMd
  latest_text = $LatestTxt
  root_baseline_id = [string]$Audit.root_baseline_id
  audit_status = [string]$Audit.status
  baseline_count = [int]$Audit.baseline_count
  edge_count = [int]$Audit.edge_count
  created_utc = [DateTime]::UtcNow.ToString("o")
}

$ManifestJson = $Manifest | ConvertTo-Json -Depth 50
Write-Utf8NoBomLf -Path $ManifestPath -Text $ManifestJson
Write-Utf8NoBomLf -Path $LatestManifest -Text $ManifestJson

Write-Host ("PIE_CROSS_REPO_BASELINE_GOVERNANCE_REPORT_OK: " + $MdPath) -ForegroundColor Green
Write-Host ("audit_status: " + [string]$Audit.status)
Write-Host ("baseline_count: " + [string]$Audit.baseline_count)
Write-Host ("edge_count: " + [string]$Audit.edge_count)
