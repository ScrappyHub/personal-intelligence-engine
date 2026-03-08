# PIE Tier-0 Lib v1
# PS5.1, StrictMode, UTF-8 no BOM + LF, NO exit
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
function Die([string]$m){ throw $m }
function Ensure-Dir([string]$p){ if($p -and -not (Test-Path -LiteralPath $p -PathType Container)){ New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function Write-Utf8NoBomLf([string]$Path,[string]$Text){ $dir=Split-Path -Parent $Path; if($dir){ Ensure-Dir $dir }; $t=$Text.Replace("`r`n","`n").Replace("`r","`n"); if(-not $t.EndsWith("`n")){ $t += "`n" }; $enc=New-Object System.Text.UTF8Encoding($false); [System.IO.File]::WriteAllText($Path,$t,$enc) }
function Read-Utf8NoBom([string]$Path){ if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("MISSING_FILE: " + $Path) }; $enc=New-Object System.Text.UTF8Encoding($false); return [System.IO.File]::ReadAllText($Path,$enc) }
function Read-Bytes([string]$Path){ if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("MISSING_FILE: " + $Path) }; return [System.IO.File]::ReadAllBytes($Path) }
function Sha256-Bytes([byte[]]$b){ $sha=[System.Security.Cryptography.SHA256]::Create(); try{ $h=$sha.ComputeHash($b) } finally { $sha.Dispose() }; return ([BitConverter]::ToString($h).Replace("-","").ToLowerInvariant()) }
function Sha256-File([string]$Path){ return (Sha256-Bytes (Read-Bytes $Path)) }
function CanonJson([object]$obj){
  # Deterministic canonical JSON: sort keys recursively, no whitespace
  function _Sort([object]$x){
    if($null -eq $x){ return $null }
    if($x -is [System.Collections.IDictionary]){
      $keys=@($x.Keys | ForEach-Object { [string]$_ } | Sort-Object)
      $o=[ordered]@{}
      foreach($k in $keys){ $o[$k]=_Sort $x[$k] }
      return $o
    }
    if(($x -is [System.Collections.IEnumerable]) -and -not ($x -is [string])){
      $arr=@()
      foreach($it in $x){ $arr += @(_Sort $it) }
      return ,$arr
    }
    return $x
  }
  $s = (_Sort $obj) | ConvertTo-Json -Depth 99 -Compress
  # Force LF and trailing LF for canonical bytes discipline when writing
  return $s.Replace("`r`n","`n").Replace("`r","`n")
}
function Write-CanonJsonFile([string]$Path,[object]$obj){ Write-Utf8NoBomLf $Path ((CanonJson $obj) + "`n") }
function Safe-RelPath([string]$p){
  # Disallow absolute paths, traversal, or backslashes in manifest relpaths
  if([string]::IsNullOrWhiteSpace($p)){ return $false }
  if($p -match '^[A-Za-z]:\\' ){ return $false }
  if($p.StartsWith("/") -or $p.StartsWith("\")){ return $false }
  if($p -match '\\'){ return $false }
  if($p -match '(^|/)\.\.(\/|$)' ){ return $false }
  return $true
}
