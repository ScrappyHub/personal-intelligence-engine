param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$SessionId,
  [Parameter(Mandatory=$true)][string]$Prompt,
  [Parameter(Mandatory=$false)][string]$Backend = "pending"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)
$ImageRoot = Join-Path $RunRoot "image_requests"

New-Item -ItemType Directory -Force -Path $ImageRoot | Out-Null

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$Out = Join-Path $ImageRoot ("image_request_" + $Stamp + ".json")

$Obj = [ordered]@{
  schema = "pie.image.request.v1"
  session_id = $SessionId
  backend = $Backend
  prompt = $Prompt
  status = "queued_backend_not_configured"
  created_utc = [DateTime]::UtcNow.ToString("o")
}

$Json = $Obj | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText($Out,($Json.Replace("`r`n","`n") + "`n"),(New-Object System.Text.UTF8Encoding($false)))

Write-Host ("PIE_IMAGE_REQUEST_OK: " + $Out) -ForegroundColor Green