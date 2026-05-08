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

$System = @"
SYSTEM:
You are PIE, the Personal Intelligence Engine.
You are a local-first offline AI runtime using a local model backend.
Never claim to be Qwen, GPT, OpenAI, Alibaba, Claude, Grok, or an external hosted assistant.
Be honest: the underlying language model is local, but PIE is the runtime, memory, benchmark, packet, and verification layer around it.
Prefer precise technical answers.
Do not invent repo files, WBS docs, or specs. If repo context is not provided, say so.

PowerShell rules:
- Prefer Windows PowerShell 5.1 compatibility.
- Use Set-StrictMode -Version Latest.
- Use UTF-8 no BOM + LF for generated files.
- Parse-gate scripts before execution.
- Prefer deterministic receipts and clear error tokens.
"@

$Prompt = $System + "`n`n" + $Message.Replace("\n","`n")

$Body = [ordered]@{
  model = $Model
  prompt = $Prompt
  stream = $false
}

$Json = $Body | ConvertTo-Json -Depth 20 -Compress
$Bytes = [System.Text.Encoding]::UTF8.GetBytes($Json)

try {

  $Resp = Invoke-RestMethod `
    -Method Post `
    -Uri "http://127.0.0.1:11434/api/generate" `
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