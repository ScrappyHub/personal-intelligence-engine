param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$SessionId,
  [Parameter(Mandatory=$true)][string]$Text
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Utf8NoBomLf {
  param(
    [Parameter(Mandatory=$true)][string]$Path,
    [Parameter(Mandatory=$true)][string]$Text
  )

  $Enc = New-Object System.Text.UTF8Encoding($false)
  $Clean = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $Clean.EndsWith("`n")){ $Clean += "`n" }

  $Dir = Split-Path -Parent $Path
  if(-not (Test-Path -LiteralPath $Dir -PathType Container)){
    New-Item -ItemType Directory -Force -Path $Dir | Out-Null
  }

  [System.IO.File]::WriteAllText($Path,$Clean,$Enc)
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)
$AttachRoot = Join-Path $RunRoot "attachments"

if(-not (Test-Path -LiteralPath $AttachRoot -PathType Container)){
  throw ("PIE_VISION_CORRECT_NO_ATTACHMENTS: " + $SessionId)
}

$ImageExts = @(".png",".jpg",".jpeg",".webp",".bmp")
$Images = @(Get-ChildItem -LiteralPath $AttachRoot -File -ErrorAction SilentlyContinue |
  Where-Object { $ImageExts -contains ([System.IO.Path]::GetExtension($_.FullName).ToLowerInvariant()) } |
  Sort-Object LastWriteTime -Descending)

if(@($Images).Count -lt 1){
  throw ("PIE_VISION_CORRECT_NO_IMAGE_ATTACHMENT: " + $SessionId)
}

$Image = $Images[0].FullName
$ImageHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Image).Hash.ToLowerInvariant()

$VisionRoot = Join-Path $RunRoot "vision"
$CorrectionLog = Join-Path $VisionRoot "corrections.ndjson"

$SafeText = $Text.Replace("\","\\").Replace('"','\"').Replace("`r`n","\n").Replace("`n","\n")
$SafeImage = $Image.Replace("\","\\")

$Line = '{"schema":"pie.vision.correction.v1","session_id":"' + $SessionId + '","image_path":"' + $SafeImage + '","image_sha256":"' + $ImageHash + '","correction":"' + $SafeText + '","status":"user_corrected","created_utc":"' + [DateTime]::UtcNow.ToString("o") + '"}' + "`n"

$Dir = Split-Path -Parent $CorrectionLog
if(-not (Test-Path -LiteralPath $Dir -PathType Container)){
  New-Item -ItemType Directory -Force -Path $Dir | Out-Null
}

[System.IO.File]::AppendAllText($CorrectionLog,$Line,(New-Object System.Text.UTF8Encoding($false)))

Write-Host ("PIE_VISION_CORRECTION_OK: " + $ImageHash) -ForegroundColor Green
Write-Host ("correction_log: " + $CorrectionLog)
