$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function PC_Die([string]$m){ throw $m }
function PC_WriteUtf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $t = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if (-not $t.EndsWith("`n")) { $t += "`n" }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}
function PC_ReadAllBytes([string]$Path){
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { PC_Die ("missing_file: " + $Path) }
  return [System.IO.File]::ReadAllBytes($Path)
}
function PC_Sha256HexBytes([byte[]]$b){
  if ($null -eq $b) { $b = @() }
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try { $h = $sha.ComputeHash([byte[]]$b) } finally { $sha.Dispose() }
  $sb = New-Object System.Text.StringBuilder
  foreach($x in $h){ [void]$sb.Append($x.ToString("x2")) }
  return $sb.ToString()
}
function PC_Sha256HexFile([string]$Path){ PC_Sha256HexBytes (PC_ReadAllBytes $Path) }

# Canonical JSON: sorted keys, no whitespace, stable escaping. IDictionary handled BEFORE IEnumerable.
function PC_EscJson([string]$s){
  if ($null -eq $s) { return "" }
  $sb = New-Object System.Text.StringBuilder
  for($i=0;$i -lt $s.Length;$i++){
    $c = [int][char]$s[$i]
    switch($c){
      34 { [void]$sb.Append("\u0022"); continue }
      92 { [void]$sb.Append("\u005c"); continue }
      8  { [void]$sb.Append("\u0008"); continue }
      9  { [void]$sb.Append("\u0009"); continue }
      10 { [void]$sb.Append("\u000a"); continue }
      12 { [void]$sb.Append("\u000c"); continue }
      13 { [void]$sb.Append("\u000d"); continue }
      default {
        if ($c -lt 32) { [void]$sb.Append(("\u{0}" -f $c.ToString("x4"))); continue }
        [void]$sb.Append([char]$c)
      }
    }
  }
  return $sb.ToString()
}
function PC_ToCanonJson($v){
  if ($null -eq $v) { return "null" }
  if ($v -is [bool]) { return (if($v){"true"}else{"false"}) }
  if ($v -is [int] -or $v -is [long] -or $v -is [double] -or $v -is [decimal]) { return ([string]$v).ToLowerInvariant() }
  if ($v -is [string]) { return ("`"" + (PC_EscJson $v) + "`"") }
  if ($v -is [System.Collections.IDictionary]) {
    $keys = @(@($v.Keys)) | Sort-Object
    $pairs = New-Object System.Collections.Generic.List[string]
    foreach($k in $keys){ $kk=[string]$k; [void]$pairs.Add(("`"" + (PC_EscJson $kk) + "`":" + (PC_ToCanonJson $v[$k]))) }
    return ("{" + ($pairs -join ",") + "}")
  }
  if ($v -is [System.Collections.IEnumerable] -and -not ($v -is [string])) {
    $items = New-Object System.Collections.Generic.List[string]
    foreach($it in $v){ [void]$items.Add((PC_ToCanonJson $it)) }
    return ("[" + ($items -join ",") + "]")
  }
  $ht=@{}; foreach($p in $v.PSObject.Properties){ $ht[$p.Name]=$p.Value }
  $keys2=@(@($ht.Keys)) | Sort-Object
  $pairs2=New-Object System.Collections.Generic.List[string]
  foreach($k2 in $keys2){ [void]$pairs2.Add(("`"" + (PC_EscJson ([string]$k2)) + "`":" + (PC_ToCanonJson $ht[$k2]))) }
  return ("{" + ($pairs2 -join ",") + "}")
}

# Returns relative paths (LF semantics irrelevant) excluding sha256sums.txt itself
function PC_ListRequiredFiles([string]$PacketRoot){
  $PacketRoot = (Resolve-Path -LiteralPath $PacketRoot).Path
  $all = Get-ChildItem -LiteralPath $PacketRoot -Recurse -File | ForEach-Object { $_.FullName }
  $rels = New-Object System.Collections.Generic.List[string]
  foreach($f in @(@($all))){
    $rel = $f.Substring($PacketRoot.Length).TrimStart("\") -replace "\\","/"
    if ($rel -ieq "sha256sums.txt") { continue }
    [void]$rels.Add($rel)
  }
  return @(@($rels.ToArray() | Sort-Object))
}
function PC_WriteSha256Sums([string]$PacketRoot){
  $PacketRoot = (Resolve-Path -LiteralPath $PacketRoot).Path
  $rels = PC_ListRequiredFiles $PacketRoot
  $lines = New-Object System.Collections.Generic.List[string]
  foreach($rel in $rels){
    $abs = Join-Path $PacketRoot ($rel -replace "/","\")
    $h = PC_Sha256HexFile $abs
    [void]$lines.Add(($h + "  " + $rel))
  }
  $out = Join-Path $PacketRoot "sha256sums.txt"
  PC_WriteUtf8NoBomLf $out (($lines.ToArray()) -join "`n")
  return $out
}
