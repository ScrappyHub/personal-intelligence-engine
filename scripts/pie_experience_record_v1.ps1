param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$SessionId,
  [Parameter(Mandatory=$true)][string]$Goal,
  [Parameter(Mandatory=$true)][string]$Outcome,
  [Parameter(Mandatory=$false)][string]$ChainId = "",
  [Parameter(Mandatory=$false)][string]$FreezePath = "",
  [Parameter(Mandatory=$false)][string]$Notes = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)
$ExperienceRoot = Join-Path $RepoRoot "memory\experience"
$ExperienceLog = Join-Path $ExperienceRoot "experience.ndjson"
$Enc = New-Object System.Text.UTF8Encoding($false)

function Get-Sha256OrEmpty {
  param([AllowEmptyString()][string]$Path)

  if([string]::IsNullOrWhiteSpace($Path)){
    return ""
  }

  if(Test-Path -LiteralPath $Path -PathType Leaf){
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
  }
  if(Test-Path -LiteralPath $Path -PathType Container){
    $Lines = New-Object System.Collections.Generic.List[string]
    foreach($File in @(Get-ChildItem -LiteralPath $Path -File -Recurse | Sort-Object FullName)){
      [void]$Lines.Add(((Get-FileHash -Algorithm SHA256 -LiteralPath $File.FullName).Hash.ToLowerInvariant()) + "  " + $File.FullName.Substring($Path.Length).TrimStart("\"))
    }
    $Bytes = [System.Text.Encoding]::UTF8.GetBytes(($Lines.ToArray() -join "`n"))
    $Sha = [System.Security.Cryptography.SHA256]::Create()
    return ([BitConverter]::ToString($Sha.ComputeHash($Bytes)).Replace("-","").ToLowerInvariant())
  }
  return ""
}

if(-not (Test-Path -LiteralPath $RunRoot -PathType Container)){
  throw ("PIE_EXPERIENCE_SESSION_NOT_FOUND: " + $SessionId)
}

if($Outcome -notin @("success","failure","partial")){
  throw ("PIE_EXPERIENCE_BAD_OUTCOME: " + $Outcome)
}

New-Item -ItemType Directory -Force -Path $ExperienceRoot | Out-Null

$ReceiptPath = Join-Path $RunRoot "execution\execution_receipts.ndjson"
$ReplayPath = Join-Path $RunRoot "replay\latest_execution_replay.json"
$ReasonTrace = Join-Path $RunRoot "reason_traces\latest_reason_trace.json"

$Entry = [ordered]@{
  schema = "pie.experience.entry.v1"
  session_id = $SessionId
  goal = $Goal
  chain_id = $ChainId
  outcome = $Outcome
  notes = $Notes
  execution_receipts = $(if(Test-Path -LiteralPath $ReceiptPath -PathType Leaf){ $ReceiptPath } else { "" })
  execution_receipts_sha256 = Get-Sha256OrEmpty $ReceiptPath
  replay = $(if(Test-Path -LiteralPath $ReplayPath -PathType Leaf){ $ReplayPath } else { "" })
  replay_sha256 = Get-Sha256OrEmpty $ReplayPath
  reason_trace = $(if(Test-Path -LiteralPath $ReasonTrace -PathType Leaf){ $ReasonTrace } else { "" })
  reason_trace_sha256 = Get-Sha256OrEmpty $ReasonTrace
  freeze = $FreezePath
  freeze_hash = Get-Sha256OrEmpty $FreezePath
  created_utc = [DateTime]::UtcNow.ToString("o")
}

[System.IO.File]::AppendAllText($ExperienceLog,(($Entry | ConvertTo-Json -Depth 20 -Compress) + "`n"),$Enc)

Write-Host ("PIE_EXPERIENCE_RECORD_OK: " + $ExperienceLog) -ForegroundColor Green

