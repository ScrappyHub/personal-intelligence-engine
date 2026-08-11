param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$false)][ValidateRange(1,500)][int]$Limit = 200
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $RepoRoot "scripts\_lib_pie_agent_session_v1.ps1")
$RunsRoot = Join-Path $RepoRoot "runs"
$Items = New-Object System.Collections.Generic.List[object]
function Test-PieDevelopmentSessionId {
  param([Parameter(Mandatory=$true)][string]$Value)
  return $Value -match '(^|_)(selftest|smoke)(_|$)' -or $Value -match '^(stress_agent_|external_stress_|external_demo_|runtime_green($|_)|pie_drift_)'
}
if(Test-Path -LiteralPath $RunsRoot -PathType Container){
  foreach($Directory in @(Get-ChildItem -LiteralPath $RunsRoot -Directory | Sort-Object LastWriteTimeUtc -Descending)){
    $SessionId = $Directory.Name
    if($SessionId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$'){ continue }
    if(-not (Test-Path -LiteralPath (Join-Path $Directory.FullName "session_manifest.json") -PathType Leaf) -and `
       -not (Test-Path -LiteralPath (Join-Path $Directory.FullName "state\session.state.json") -PathType Leaf)){ continue }
    try {
      $Session = PIE_GetAgentSession -RepoRoot $RepoRoot -SessionId $SessionId
      [void]$Items.Add([ordered]@{
        id=$SessionId; status=$Session.status; integrity=$Session.integrity; project_repo=$Session.project_repo
        model=$Session.model; goal=$Session.goal; turns=@($Session.conversation_turns).Count
        updated_utc=$Directory.LastWriteTimeUtc.ToString("o"); error=""; test_only=(Test-PieDevelopmentSessionId -Value $SessionId)
      })
    }
    catch {
      $Code = [regex]::Match($_.Exception.Message,'^([A-Z0-9_]+)').Groups[1].Value
      $Busy = $Code -eq "PIE_AGENT_SESSION_BUSY"
      [void]$Items.Add([ordered]@{
        id=$SessionId; status=$(if($Busy){"busy"}else{"blocked"}); integrity=$(if($Busy){"busy"}else{"corrupt"}); project_repo=""; model=""; goal=""; turns=0
        updated_utc=$Directory.LastWriteTimeUtc.ToString("o"); error=$Code; test_only=(Test-PieDevelopmentSessionId -Value $SessionId)
      })
    }
    if($Items.Count -ge $Limit){ break }
  }
}
$Result = [ordered]@{schema="pie.session.index.v1";sessions=@($Items.ToArray())}
Write-Output ("PIE_AGENT_SESSIONS_JSON:" + ($Result | ConvertTo-Json -Depth 8 -Compress))
