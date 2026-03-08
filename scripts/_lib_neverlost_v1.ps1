$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest


function NL_EscJsonString([string]$s){
  if ($null -eq $s) { return "" }
  $sb = New-Object System.Text.StringBuilder
  for($i=0; $i -lt $s.Length; $i++){
    $c = [int][char]$s[$i]
    switch($c){
      34 { [void]$sb.Append('\u0022'); continue }  # "
      92 { [void]$sb.Append('\u005c'); continue }  # \
      8  { [void]$sb.Append('\u0008'); continue }
      9  { [void]$sb.Append('\u0009'); continue }
      10 { [void]$sb.Append('\u000a'); continue }
      12 { [void]$sb.Append('\u000c'); continue }
      13 { [void]$sb.Append('\u000d'); continue }
      default {
        if ($c -lt 32) { [void]$sb.Append(('\u{0}' -f $c.ToString('x4'))); continue }
        [void]$sb.Append([char]$c)
      }
    }
  }
  return $sb.ToString()
}

function NL_Die([string]$m){ throw $m }
function NL_WriteUtf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $t = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if (-not $t.EndsWith("`n")) { $t += "`n" }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}
function NL_ReadUtf8([string]$Path){ if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ return $null } $enc=New-Object System.Text.UTF8Encoding($false); [System.IO.File]::ReadAllText($Path,$enc) }
function NL_Sha256HexBytes([byte[]]$b){ if($null -eq $b){$b=@()} $sha=[System.Security.Cryptography.SHA256]::Create(); try{$h=$sha.ComputeHash([byte[]]$b)} finally{$sha.Dispose()} $sb=New-Object System.Text.StringBuilder; foreach($x in $h){[void]$sb.Append($x.ToString("x2"))}; $sb.ToString() }
function NL_ToCanonJson($v){
  if ($null -eq $v) { return 'null' }
  if ($v -is [bool]) { return (if($v){'true'}else{'false'}) }
  if ($v -is [int] -or $v -is [long] -or $v -is [double] -or $v -is [decimal]) {
    return ([string]$v).ToLowerInvariant()
  }
  if ($v -is [string]) { return ('"' + (NL_EscJsonString $v) + '"') }

  # IDictionary MUST serialize as object (sorted keys) â€” do NOT treat as IEnumerable
  if ($v -is [System.Collections.IDictionary]) {
    $keys = @(@($v.Keys)) | Sort-Object
    $pairs = New-Object System.Collections.Generic.List[string]
    foreach($k in $keys){
      $kk = [string]$k
      [void]$pairs.Add(('"' + (NL_EscJsonString $kk) + '":' + (NL_ToCanonJson $v[$k])))
    }
    return ('{' + ($pairs -join ',') + '}')
  }

  # Arrays / lists
  if ($v -is [System.Collections.IEnumerable] -and -not ($v -is [string])) {
    $items = New-Object System.Collections.Generic.List[string]
    foreach($it in $v){ [void]$items.Add((NL_ToCanonJson $it)) }
    return ('[' + ($items -join ',') + ']')
  }

  # PSCustomObject / other objects -> sorted properties
  $ht = @{}
  foreach($p in $v.PSObject.Properties){ $ht[$p.Name] = $p.Value }
  $keys2 = @(@($ht.Keys)) | Sort-Object
  $pairs2 = New-Object System.Collections.Generic.List[string]
  foreach($k2 in $keys2){
    [void]$pairs2.Add(('"' + (NL_EscJsonString ([string]$k2)) + '":' + (NL_ToCanonJson $ht[$k2])))
  }
  return ('{' + ($pairs2 -join ',') + '}')
}
function NL_LoadTrustBundle([string]$RepoRoot){ $p=Join-Path $RepoRoot "proofs\trust\trust_bundle.json"; $t=NL_ReadUtf8 $p; if([string]::IsNullOrWhiteSpace($t)){ NL_Die ("missing_or_empty_trust_bundle: " + $p) } try{ $t | ConvertFrom-Json } catch { NL_Die ("trust_bundle_parse_failed: " + $_.Exception.Message) } }
function NL_AppendReceipt([string]$RepoRoot,[string]$kind,[string]$message,[hashtable]$extra){ $p=Join-Path $RepoRoot "proofs\receipts\neverlost.ndjson"; $evt=@{ ts=(Get-Date).ToUniversalTime().ToString("o"); kind=$kind; message=$message; extra=$extra }; $line=NL_ToCanonJson $evt; $enc=New-Object System.Text.UTF8Encoding($false); [System.IO.File]::AppendAllText($p, ($line + "`n"), $enc) }
function NL_MakeAllowedSigners([string]$RepoRoot){ $tb=NL_LoadTrustBundle $RepoRoot; $keys=@(@($tb.keys)); if($keys.Count -lt 1){ NL_Die "trust_bundle.json has no keys[]" } $lines=New-Object System.Collections.Generic.List[string]; foreach($k in $keys){ $principal=[string]$k.principal; $pubkey=[string]$k.pubkey; if([string]::IsNullOrWhiteSpace($principal)){ NL_Die "trust_bundle.json missing principal" } if([string]::IsNullOrWhiteSpace($pubkey)){ NL_Die "trust_bundle.json missing pubkey" } [void]$lines.Add(($principal + " " + $pubkey).Trim()) } $out=Join-Path $RepoRoot "proofs\trust\allowed_signers"; NL_WriteUtf8NoBomLf $out (($lines | Sort-Object) -join "`n"); NL_AppendReceipt $RepoRoot "allowed_signers" ("wrote " + $out) @{ line_count=$lines.Count }; $out }
