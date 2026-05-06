param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$SessionId,
  [Parameter(Mandatory=$false)][string]$Backend = "ollama",
  [Parameter(Mandatory=$false)][string]$Model = "qwen2.5-coder:7b"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)
$enc = New-Object System.Text.UTF8Encoding($false)

New-Item -ItemType Directory -Force -Path $RunRoot | Out-Null

[System.IO.File]::WriteAllText((Join-Path $RunRoot "backend.txt"), ($Backend + "`n"), $enc)
[System.IO.File]::WriteAllText((Join-Path $RunRoot "model.txt"), ($Model + "`n"), $enc)

$history = Join-Path $RunRoot "history.jsonl"
if(-not (Test-Path -LiteralPath $history -PathType Leaf)){
  [System.IO.File]::WriteAllText($history, "", $enc)
}

Write-Host ("PIE_AGENT_START_OK: " + $SessionId) -ForegroundColor Green
Write-Host $RunRoot
