param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }
function Read-Utf8NoBom([string]$Path){
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Die ("MISSING_FILE: " + $Path) }
  $enc = New-Object System.Text.UTF8Encoding($false)
  return [System.IO.File]::ReadAllText($Path,$enc)
}
function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $t = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if (-not $t.EndsWith("`n")) { $t += "`n" }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}
function Parse-GateText([string]$Text){ [void][ScriptBlock]::Create($Text) }

$RepoRoot = $RepoRoot.TrimEnd("\")
$LibPath  = Join-Path $RepoRoot "scripts\_lib_neverlost_v1.ps1"
if (-not (Test-Path -LiteralPath $LibPath -PathType Leaf)) { Die ("MISSING_LIB: " + $LibPath) }

$bak = $LibPath + ".bak_" + (Get-Date -Format "yyyyMMdd_HHmmss")
Copy-Item -LiteralPath $LibPath -Destination $bak -Force | Out-Null

$txt = Read-Utf8NoBom $LibPath

# Anchors (NO brace guessing):
$startAnchor = [regex]'(?m)^\s*function\s+NL_ToCanonJson\s*\('
$endAnchor   = [regex]'(?m)^\s*function\s+NL_LoadTrustBundle\s*\('

$m1 = $startAnchor.Match($txt)
if (-not $m1.Success) { Die ("PATCH_FAIL: start anchor not found: function NL_ToCanonJson( in " + $LibPath) }

$m2 = $endAnchor.Match($txt, $m1.Index)
if (-not $m2.Success) { Die ("PATCH_FAIL: end anchor not found: function NL_LoadTrustBundle( after NL_ToCanonJson in " + $LibPath) }

$pre  = $txt.Substring(0, $m1.Index)
$post = $txt.Substring($m2.Index)

# Ensure NL_EscJsonString exists somewhere BEFORE NL_ToCanonJson
$hasEsc = [regex]::IsMatch($pre, '(?m)^\s*function\s+NL_EscJsonString\s*\(') -or [regex]::IsMatch($post, '(?m)^\s*function\s+NL_EscJsonString\s*\(')
if (-not $hasEsc) {
  $escFn = @"
function NL_EscJsonString([string]`$s){
  if (`$null -eq `$s) { return "" }
  `$sb = New-Object System.Text.StringBuilder
  for(`$i=0; `$i -lt `$s.Length; `$i++){
    `$c = [int][char]`$s[`$i]
    switch(`$c){
      34 { [void]`$sb.Append('\u0022'); continue }  # "
      92 { [void]`$sb.Append('\u005c'); continue }  # \
      8  { [void]`$sb.Append('\u0008'); continue }
      9  { [void]`$sb.Append('\u0009'); continue }
      10 { [void]`$sb.Append('\u000a'); continue }
      12 { [void]`$sb.Append('\u000c'); continue }
      13 { [void]`$sb.Append('\u000d'); continue }
      default {
        if (`$c -lt 32) { [void]`$sb.Append(('\u{0}' -f `$c.ToString('x4'))); continue }
        [void]`$sb.Append([char]`$c)
      }
    }
  }
  return `$sb.ToString()
}
"@
  # Put it at end of $pre so it is definitely before NL_ToCanonJson
  $pre = $pre.TrimEnd() + "`n`n" + $escFn + "`n"
}

# Replacement block (safe ordering: IDictionary before IEnumerable)
$newBlock = @"
function NL_ToCanonJson(`$v){
  if (`$null -eq `$v) { return 'null' }
  if (`$v -is [bool]) { return (if(`$v){'true'}else{'false'}) }
  if (`$v -is [int] -or `$v -is [long] -or `$v -is [double] -or `$v -is [decimal]) {
    return ([string]`$v).ToLowerInvariant()
  }
  if (`$v -is [string]) { return ('"' + (NL_EscJsonString `$v) + '"') }

  # IDictionary MUST serialize as object (sorted keys) — do NOT treat as IEnumerable
  if (`$v -is [System.Collections.IDictionary]) {
    `$keys = @(@(`$v.Keys)) | Sort-Object
    `$pairs = New-Object System.Collections.Generic.List[string]
    foreach(`$k in `$keys){
      `$kk = [string]`$k
      [void]`$pairs.Add(('"' + (NL_EscJsonString `$kk) + '":' + (NL_ToCanonJson `$v[`$k])))
    }
    return ('{' + (`$pairs -join ',') + '}')
  }

  # Arrays / lists
  if (`$v -is [System.Collections.IEnumerable] -and -not (`$v -is [string])) {
    `$items = New-Object System.Collections.Generic.List[string]
    foreach(`$it in `$v){ [void]`$items.Add((NL_ToCanonJson `$it)) }
    return ('[' + (`$items -join ',') + ']')
  }

  # PSCustomObject / other objects -> sorted properties
  `$ht = @{}
  foreach(`$p in `$v.PSObject.Properties){ `$ht[`$p.Name] = `$p.Value }
  `$keys2 = @(@(`$ht.Keys)) | Sort-Object
  `$pairs2 = New-Object System.Collections.Generic.List[string]
  foreach(`$k2 in `$keys2){
    [void]`$pairs2.Add(('"' + (NL_EscJsonString ([string]`$k2)) + '":' + (NL_ToCanonJson `$ht[`$k2])))
  }
  return ('{' + (`$pairs2 -join ',') + '}')
}

"@

$txt2 = $pre + $newBlock + $post

# Parse-gate before write
Parse-GateText $txt2

Write-Utf8NoBomLf $LibPath $txt2
Parse-GateText (Read-Utf8NoBom $LibPath)

# Sanity: count occurrences of NL_ToCanonJson definitions
$cnt = ([regex]::Matches($txt2, '(?m)^\s*function\s+NL_ToCanonJson\s*\(')).Count
if ($cnt -ne 1) { Die ("PATCH_FAIL: expected exactly 1 NL_ToCanonJson definition after patch; got " + $cnt) }

Write-Host ("PATCH_OK: replaced NL_ToCanonJson section. backup=" + $bak) -ForegroundColor Green
