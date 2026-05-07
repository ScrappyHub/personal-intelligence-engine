param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$SessionId,
  [Parameter(Mandatory=$false)][string]$Model = "llava:7b",
  [Parameter(Mandatory=$false)][string]$Prompt = "Describe the attached image clearly and concisely."
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
  throw ("PIE_VISION_NO_ATTACHMENTS: " + $SessionId)
}

$ImageExts = @(".png",".jpg",".jpeg",".webp",".bmp")
$Images = @(Get-ChildItem -LiteralPath $AttachRoot -File -ErrorAction SilentlyContinue |
  Where-Object { $ImageExts -contains ([System.IO.Path]::GetExtension($_.FullName).ToLowerInvariant()) } |
  Sort-Object LastWriteTime -Descending)

if(@($Images).Count -lt 1){
  throw ("PIE_VISION_NO_IMAGE_ATTACHMENT: " + $SessionId)
}

$Image = $Images[0].FullName
$Bytes = [System.IO.File]::ReadAllBytes($Image)
$ImageB64 = [Convert]::ToBase64String($Bytes)

$Body = [ordered]@{
  model = $Model
  prompt = $Prompt
  stream = $false
  images = @($ImageB64)
}

$BodyJson = $Body | ConvertTo-Json -Depth 10

try {
  $Resp = Invoke-RestMethod `
    -Method Post `
    -Uri "http://127.0.0.1:11434/api/generate" `
    -ContentType "application/json" `
    -Body $BodyJson
}
catch {
  throw ("PIE_VISION_OLLAMA_API_FAIL: " + $_.Exception.Message)
}

if($null -eq $Resp){
  throw "PIE_VISION_NULL_RESPONSE"
}

if([string]::IsNullOrWhiteSpace($Resp.response)){
  throw "PIE_VISION_EMPTY_RESPONSE"
}

$VisionRoot = Join-Path $RunRoot "vision"
$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$OutPath = Join-Path $VisionRoot ("vision_result_" + $Stamp + ".json")

$ImageHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Image).Hash.ToLowerInvariant()

$Obj = [ordered]@{
  schema = "pie.vision.result.v1"
  session_id = $SessionId
  backend = "ollama"
  model = $Model
  image_path = $Image
  image_sha256 = $ImageHash
  prompt = $Prompt
  response = [string]$Resp.response
  created_utc = [DateTime]::UtcNow.ToString("o")
}

$Json = $Obj | ConvertTo-Json -Depth 12
Write-Utf8NoBomLf -Path $OutPath -Text $Json

Write-Host ("PIE_VISION_OK: " + $OutPath) -ForegroundColor Green
Write-Host ([string]$Resp.response)
