param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$SessionId,
  [Parameter(Mandatory=$true)][string]$Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){
  throw ("PIE_ATTACH_SOURCE_NOT_FOUND: " + $Path)
}

$Source = (Resolve-Path -LiteralPath $Path).Path
$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)
$AttachRoot = Join-Path $RunRoot "attachments"

New-Item -ItemType Directory -Force -Path $AttachRoot | Out-Null

$Name = Split-Path -Leaf $Source
$Dest = Join-Path $AttachRoot $Name
Copy-Item -LiteralPath $Source -Destination $Dest -Force

$Hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Dest).Hash.ToLowerInvariant()
$MetaPath = Join-Path $AttachRoot "attachments.ndjson"
$EscDest = $Dest.Replace('\','\\')

$Line = '{"schema":"pie.attachment.v1","session_id":"' + $SessionId + '","path":"' + $EscDest + '","sha256":"' + $Hash + '","created_utc":"' + [DateTime]::UtcNow.ToString("o") + '"}' + "`n"
[System.IO.File]::AppendAllText($MetaPath,$Line,(New-Object System.Text.UTF8Encoding($false)))

Write-Host ("PIE_ATTACH_OK: " + $Dest) -ForegroundColor Green
Write-Host ("sha256: " + $Hash)
