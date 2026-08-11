param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$ApiBase,
  [Parameter(Mandatory=$false)][string]$OutputDirectory = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
if([string]::IsNullOrWhiteSpace($OutputDirectory)){ $OutputDirectory = Join-Path $RepoRoot "dist\hosted" }
$ApiUri = $null
if(-not [Uri]::TryCreate($ApiBase,[UriKind]::Absolute,[ref]$ApiUri) -or $ApiUri.Scheme -ne "https"){ throw "PIE_HOSTED_API_HTTPS_REQUIRED" }
$PublicRoot = Join-Path $RepoRoot "workbench\public"
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
$Enc = New-Object System.Text.UTF8Encoding($false)

if(Test-Path -LiteralPath $OutputDirectory -PathType Container){ Remove-Item -LiteralPath $OutputDirectory -Recurse -Force }
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
foreach($Name in @("styles.css","app.js","manifest.webmanifest","service-worker.js","sunset-horizon.png","pie-icon.png")){
  Copy-Item -LiteralPath (Join-Path $PublicRoot $Name) -Destination (Join-Path $OutputDirectory $Name)
}
$ManifestPath = Join-Path $OutputDirectory "manifest.webmanifest"
$Manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
$Manifest.start_url = "/?surface=hosted"
[IO.File]::WriteAllText($ManifestPath,(($Manifest | ConvertTo-Json -Depth 8) + "`n"),$Enc)

$Bootstrap = [ordered]@{ apiBase=$ApiUri.AbsoluteUri.TrimEnd('/'); surface="hosted" }
$Html = Get-Content -LiteralPath (Join-Path $PublicRoot "index.html") -Raw
$Html = $Html.Replace("__PIE_BOOTSTRAP_JSON__",($Bootstrap | ConvertTo-Json -Compress))
$Html = $Html.Replace("<style>__PIE_STYLES__</style>","")
$Html = $Html.Replace("<script>__PIE_APP_JS__</script>","")
$Html = $Html.Replace("/?surface=pwa","/?surface=hosted")
[IO.File]::WriteAllText((Join-Path $OutputDirectory "index.html"),$Html,$Enc)

$ConnectOrigin = $ApiUri.GetLeftPart([UriPartial]::Authority)
$Headers = @"
/*
  Cache-Control: public, max-age=0, must-revalidate
  Content-Security-Policy: default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self' $ConnectOrigin; frame-ancestors 'none'; base-uri 'none'; form-action 'self'
  Referrer-Policy: no-referrer
  X-Content-Type-Options: nosniff
  X-Frame-Options: DENY
"@
[IO.File]::WriteAllText((Join-Path $OutputDirectory "_headers"),($Headers.Trim() + "`n"),$Enc)
$Vercel = [ordered]@{ cleanUrls=$true; trailingSlash=$false; rewrites=@([ordered]@{ source="/(.*)"; destination="/index.html" }) }
[IO.File]::WriteAllText((Join-Path $OutputDirectory "vercel.json"),(($Vercel | ConvertTo-Json -Depth 8) + "`n"),$Enc)
Write-Host ("PIE_HOSTED_BUILD_OK: " + $OutputDirectory) -ForegroundColor Green
