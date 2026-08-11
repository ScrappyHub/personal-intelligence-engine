param(
  [Parameter(Mandatory=$true)][string]$Model,
  [Parameter(Mandatory=$false)][string]$Message = "",
  [Parameter(Mandatory=$false)][string]$MessagePath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if(-not [string]::IsNullOrWhiteSpace($MessagePath)){

  if(-not (Test-Path -LiteralPath $MessagePath -PathType Leaf)){
    throw ("PIE_OLLAMA_MESSAGE_PATH_NOT_FOUND: " + $MessagePath)
  }

  $Message = Get-Content -LiteralPath $MessagePath -Raw
}

if([string]::IsNullOrWhiteSpace($Message)){
  throw "PIE_OLLAMA_MESSAGE_REQUIRED"
}

. (Join-Path $PSScriptRoot "_lib_pie_persona_v1.ps1")
$System = PIE_PersonaSystem "Ollama"

$Prompt = $System + "`n`n" + $Message.Replace("\n","`n")

$Body = [ordered]@{
  model = $Model
  prompt = $Prompt
  stream = $false
}

$Json = $Body | ConvertTo-Json -Depth 20 -Compress
$Bytes = [System.Text.Encoding]::UTF8.GetBytes($Json)

# Loopback endpoint. Overridable for tests/negative cases via PIE_OLLAMA_URL; defaults to the
# standard local Ollama host. Additive: default behavior is unchanged when the env var is unset.
$Url = $env:PIE_OLLAMA_URL
if([string]::IsNullOrWhiteSpace($Url)){ $Url = "http://127.0.0.1:11434/api/generate" }

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

        try {
          $BodyText = $Reader.ReadToEnd()
        }
        finally {
          $Reader.Dispose()
        }

        if(-not [string]::IsNullOrWhiteSpace($BodyText)){
          $Detail = $Detail + " BODY=" + $BodyText
        }
      }
    }

  } catch { }

  throw ("PIE_OLLAMA_API_FAILED: " + $Detail)
}

if($null -eq $Resp){
  throw "PIE_OLLAMA_NULL_RESPONSE"
}

if(-not ($Resp.PSObject.Properties.Name -contains "response")){
  throw "PIE_OLLAMA_RESPONSE_FIELD_MISSING"
}

$ResponseText = [string]$Resp.response

if([string]::IsNullOrWhiteSpace($ResponseText)){
  throw "PIE_OLLAMA_EMPTY_RESPONSE"
}

Write-Output $ResponseText

