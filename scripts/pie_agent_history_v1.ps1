param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$SessionId,
  [Parameter(Mandatory=$false)][ValidateRange(1,1000)][int]$Limit = 200
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $RepoRoot "scripts\_lib_pie_agent_session_v1.ps1")
$Session = PIE_GetAgentSession -RepoRoot $RepoRoot -SessionId $SessionId
$Turns = @($Session.conversation_turns | Select-Object -Last $Limit | ForEach-Object {
  [ordered]@{
    turn_index = [int](PIE_GetSessionProperty -Object $_ -Name "turn_index")
    ts = [string](PIE_GetSessionProperty -Object $_ -Name "ts")
    message = [string](PIE_GetSessionProperty -Object $_ -Name "message")
    response = [string](PIE_GetSessionProperty -Object $_ -Name "response")
    grounding_correction_count = [int](PIE_GetSessionProperty -Object $_ -Name "grounding_correction_count")
  }
})
$Result = [ordered]@{
  schema = "pie.conversation.history.v1"
  session_id = $Session.session_id
  binding_sha256 = $Session.binding_sha256
  project_repo = $Session.project_repo
  model = $Session.model
  status = $Session.status
  integrity = $Session.integrity
  total_turns = @($Session.conversation_turns).Count
  turns = $Turns
}
Write-Output ("PIE_AGENT_HISTORY_JSON:" + ($Result | ConvertTo-Json -Depth 8 -Compress))
