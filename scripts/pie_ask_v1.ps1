param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$SessionId,
  [Parameter(Mandatory=$true)][string]$Message
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)
$AttachRoot = Join-Path $RunRoot "attachments"

$Context = ""

if(Test-Path -LiteralPath $AttachRoot -PathType Container){
  $Files = @(Get-ChildItem -LiteralPath $AttachRoot -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne "attachments.ndjson" })

  if(@($Files).Count -gt 0){
    $Context += "ATTACHMENTS:`n"

    foreach($File in $Files){
      $Context += "- " + $File.FullName + "`n"

      $Ext = [System.IO.Path]::GetExtension($File.FullName).ToLowerInvariant()
      if($Ext -in @(".txt",".md",".json",".csv",".ps1",".py",".js",".ts",".html",".css",".xml",".yml",".yaml",".sql")){
        $Raw = Get-Content -LiteralPath $File.FullName -Raw -ErrorAction SilentlyContinue
        if($Raw.Length -gt 6000){ $Raw = $Raw.Substring(0,6000) }
        $Context += "CONTENT_BEGIN " + $File.Name + "`n" + $Raw + "`nCONTENT_END`n"
      } else {
        $Context += "NOTE: Binary or image file attached. If current backend cannot inspect pixels directly, say so clearly.`n"
      }
    }

    $Context += "`n"
  }
}

$Full = $Context + "USER:`n" + $Message

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_agent_send_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -Message $Full
