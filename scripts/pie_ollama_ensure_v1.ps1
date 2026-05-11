param(
  [Parameter(Mandatory=$false)][int]$TimeoutSeconds = 30
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Ollama = (Get-Command ollama -ErrorAction Stop).Source

function Test-OllamaApi {
  try {
    $Resp = Invoke-WebRequest `
      -Uri "http://127.0.0.1:11434/api/tags" `
      -Method Get `
      -UseBasicParsing `
      -TimeoutSec 2

    return ($Resp.StatusCode -eq 200)
  }
  catch {
    return $false
  }
}

if(Test-OllamaApi){
  Write-Host "PIE_OLLAMA_READY" -ForegroundColor Green
  return
}

$LogRoot = Join-Path $env:LOCALAPPDATA "PIE\ollama"
New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$OutLog = Join-Path $LogRoot ("ollama_stdout_" + $Stamp + ".log")
$ErrLog = Join-Path $LogRoot ("ollama_stderr_" + $Stamp + ".log")

$Proc = Start-Process `
  -FilePath $Ollama `
  -ArgumentList @("serve") `
  -WindowStyle Hidden `
  -PassThru `
  -RedirectStandardOutput $OutLog `
  -RedirectStandardError $ErrLog

$Deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)

while([DateTime]::UtcNow -lt $Deadline){
  Start-Sleep -Milliseconds 500

  if(Test-OllamaApi){
    Write-Host "PIE_OLLAMA_STARTED_SILENT" -ForegroundColor Green
    Write-Host ("pid: " + $Proc.Id)
    Write-Host ("stdout: " + $OutLog)
    Write-Host ("stderr: " + $ErrLog)
    return
  }
}

throw ("PIE_OLLAMA_START_TIMEOUT stdout=" + $OutLog + " stderr=" + $ErrLog)
