param(
  [Parameter(Mandatory=$true)][string]$RequestPath,
  [Parameter(Mandatory=$true)][string]$ResponsePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$Message){
  throw $Message
}

function Ensure-Dir([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Container)){
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

function Read-Utf8NoBom([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){
    Die ("MISSING_FILE: " + $Path)
  }
  $enc = New-Object System.Text.UTF8Encoding($false)
  return [System.IO.File]::ReadAllText($Path,$enc)
}

function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir){
    Ensure-Dir $dir
  }
  $enc = New-Object System.Text.UTF8Encoding($false)
  $t = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $t.EndsWith("`n")){
    $t += "`n"
  }
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}

function Escape-JsonString([string]$Value){
  if($null -eq $Value){ return "" }
  $s = $Value
  $s = $s.Replace('\','\\')
  $s = $s.Replace('"','\"')
  $s = $s.Replace("`t","\t")
  $s = $s.Replace("`r","\r")
  $s = $s.Replace("`n","\n")
  return $s
}

function Invoke-HttpJson([string]$Url,[string]$JsonBody){
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($JsonBody)

  $req = [System.Net.HttpWebRequest]::Create($Url)
  $req.Method = "POST"
  $req.ContentType = "application/json"
  $req.ContentLength = $bytes.Length
  $req.Timeout = 600000
  $req.ReadWriteTimeout = 600000

  $stream = $req.GetRequestStream()
  try {
    $stream.Write($bytes,0,$bytes.Length)
  } finally {
    $stream.Dispose()
  }

  try {
    $resp = $req.GetResponse()
  } catch [System.Net.WebException] {
    if($_.Exception.Response){
      $sr = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
      try {
        $errBody = $sr.ReadToEnd()
      } finally {
        $sr.Dispose()
      }
      Die ("OLLAMA_HTTP_ERROR: " + $errBody)
    }
    throw
  }

  $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
  try {
    return $reader.ReadToEnd()
  } finally {
    $reader.Dispose()
    $resp.Dispose()
  }
}

function Get-JsonStringValue([object]$Obj,[string]$Key){
  $p = $Obj.PSObject.Properties[$Key]
  if($null -eq $p){
    Die ("JSON_KEY_NOT_FOUND: " + $Key)
  }
  return [string]$p.Value
}

$requestText = Read-Utf8NoBom $RequestPath
$requestObj  = $requestText | ConvertFrom-Json

$sessionId    = Get-JsonStringValue $requestObj "session_id"
$prompt       = Get-JsonStringValue $requestObj "prompt"

$model = [Environment]::GetEnvironmentVariable("PIE_OLLAMA_MODEL","Process")
if([string]::IsNullOrWhiteSpace($model)){
  $model = [Environment]::GetEnvironmentVariable("PIE_OLLAMA_MODEL","User")
}
if([string]::IsNullOrWhiteSpace($model)){
  $model = "gemma3"
}

$hostUrl = [Environment]::GetEnvironmentVariable("PIE_OLLAMA_HOST","Process")
if([string]::IsNullOrWhiteSpace($hostUrl)){
  $hostUrl = [Environment]::GetEnvironmentVariable("PIE_OLLAMA_HOST","User")
}
if([string]::IsNullOrWhiteSpace($hostUrl)){
  $hostUrl = "http://127.0.0.1:11434"
}

$systemPrompt = @(
  "You are PIE running fully offline."
  "Be concise, grounded, and deterministic."
  "Do not claim internet access."
  "Session: " + $sessionId
) -join " "

$body = @(
  "{"
  ('  "model":"' + (Escape-JsonString $model) + '",')
  ('  "prompt":"' + (Escape-JsonString $prompt) + '",')
  ('  "system":"' + (Escape-JsonString $systemPrompt) + '",')
  '  "stream":false'
  "}"
) -join "`n"

$url = $hostUrl.TrimEnd("/") + "/api/generate"
$responseJson = Invoke-HttpJson -Url $url -JsonBody $body
$responseObj  = $responseJson | ConvertFrom-Json

$outText = ""
if($responseObj.PSObject.Properties["response"]){
  $outText = [string]$responseObj.response
}

$outText = $outText.Trim()
if([string]::IsNullOrWhiteSpace($outText)){
  Die "OLLAMA_EMPTY_RESPONSE"
}

Write-Utf8NoBomLf $ResponsePath $outText
Write-Host ("PIE_OLLAMA_BACKEND_OK model=" + $model + " session=" + $sessionId) -ForegroundColor Green