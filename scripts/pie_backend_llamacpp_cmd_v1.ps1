param(
  [Parameter(Mandatory=$true)][string]$Model,
  [Parameter(Mandatory=$false)][string]$Message = "",
  [Parameter(Mandatory=$false)][string]$MessagePath = "",
  [Parameter(Mandatory=$false)][int]$NPredict = 512
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Loopback llama.cpp server adapter (OpenAI-style /completion).
# Mirrors scripts\pie_backend_ollama_cmd_v1.ps1. Output-bytes only; the recording law
# (hashing, ledger, artifacts, sealed-model binding) is owned by scripts\pie_run_v1.ps1.

if(-not [string]::IsNullOrWhiteSpace($MessagePath)){
  if(-not (Test-Path -LiteralPath $MessagePath -PathType Leaf)){
    throw ("PIE_LLAMACPP_MESSAGE_PATH_NOT_FOUND: " + $MessagePath)
  }
  $Message = Get-Content -LiteralPath $MessagePath -Raw
}

if([string]::IsNullOrWhiteSpace($Message)){
  throw "PIE_LLAMACPP_MESSAGE_REQUIRED"
}

. (Join-Path $PSScriptRoot "_lib_pie_persona_v1.ps1")
$System = PIE_PersonaSystem "llama.cpp"

$Prompt = $System + "`n`n" + $Message.Replace("\n","`n")

$Url = $env:PIE_LLAMACPP_URL
if([string]::IsNullOrWhiteSpace($Url)){ $Url = "http://127.0.0.1:8080/completion" }

$Body = [ordered]@{
  prompt      = $Prompt
  n_predict   = $NPredict
  temperature = 0
  stream      = $false
}

$Json  = $Body | ConvertTo-Json -Depth 20 -Compress
$Bytes = [System.Text.Encoding]::UTF8.GetBytes($Json)

try {
  $Resp = Invoke-RestMethod `
    -Method Post `
    -Uri $Url `
    -ContentType "application/json; charset=utf-8" `
    -Body $Bytes
}
catch {
  $Detail = $_.Exception.Message
  try {
    if($null -ne $_.Exception.Response){
      $Stream = $_.Exception.Response.GetResponseStream()
      if($null -ne $Stream){
        $Reader = New-Object System.IO.StreamReader($Stream)
        try { $BodyText = $Reader.ReadToEnd() } finally { $Reader.Dispose() }
        if(-not [string]::IsNullOrWhiteSpace($BodyText)){ $Detail = $Detail + " BODY=" + $BodyText }
      }
    }
  } catch { }
  throw ("PIE_LLAMACPP_API_FAILED: " + $Detail)
}

if($null -eq $Resp){
  throw "PIE_LLAMACPP_NULL_RESPONSE"
}

if(-not ($Resp.PSObject.Properties.Name -contains "content")){
  throw "PIE_LLAMACPP_RESPONSE_FIELD_MISSING"
}

$ResponseText = [string]$Resp.content

if([string]::IsNullOrWhiteSpace($ResponseText)){
  throw "PIE_LLAMACPP_EMPTY_RESPONSE"
}

Write-Output $ResponseText
