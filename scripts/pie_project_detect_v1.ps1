param(
  [Parameter(Mandatory=$true)][string]$TargetRepo
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$TargetRepo = (Resolve-Path -LiteralPath $TargetRepo).Path
$Signals = New-Object System.Collections.Generic.List[string]

function HasFile([string]$Name){
  return (Test-Path -LiteralPath (Join-Path $TargetRepo $Name) -PathType Leaf)
}

function HasDir([string]$Name){
  return (Test-Path -LiteralPath (Join-Path $TargetRepo $Name) -PathType Container)
}

if(HasDir ".git"){ [void]$Signals.Add("git") }
if(HasFile "package.json"){ [void]$Signals.Add("node") }
if(HasFile "pyproject.toml" -or HasFile "requirements.txt"){ [void]$Signals.Add("python") }
if(HasFile "Cargo.toml"){ [void]$Signals.Add("rust") }
if(HasFile "pom.xml" -or HasFile "build.gradle"){ [void]$Signals.Add("java") }
if(HasFile "Dockerfile" -or HasFile "docker-compose.yml"){ [void]$Signals.Add("docker") }

$PsFiles = @(Get-ChildItem -LiteralPath $TargetRepo -Recurse -File -Filter "*.ps1" -ErrorAction SilentlyContinue)
if(@($PsFiles).Count -gt 0){ [void]$Signals.Add("powershell") }

$Detected = @($Signals.ToArray()) | Sort-Object -Unique

Write-Host ("PIE_PROJECT_DETECT_OK: " + $TargetRepo) -ForegroundColor Green
Write-Host ("signals: " + (($Detected) -join ","))

$Out = Join-Path $TargetRepo ".pie\project_detect.v1.json"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Out) | Out-Null

$Obj = [ordered]@{
  schema = "pie.project.detect.v1"
  repo = $TargetRepo
  signals = @($Detected)
  generated_utc = [DateTime]::UtcNow.ToString("o")
}

$Json = $Obj | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText($Out,($Json.Replace("`r`n","`n") + "`n"),(New-Object System.Text.UTF8Encoding($false)))
