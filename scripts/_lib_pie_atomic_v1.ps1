Set-StrictMode -Version Latest

# PIE atomic state-write primitives (release-blocker B2 foundation).
# Prevents torn/partial state files on crash, disk-full, permission-loss, or power-loss by writing
# to a temp file in the SAME directory (same volume), flushing to disk, then atomically replacing
# the target. On any failure the original file is left intact and no temp residue remains.
# Adoption is incremental: existing writers (NL_WriteUtf8NoBomLf, ledger/receipt appends) can be
# routed through PIE_WriteFileAtomic as each state path is hardened and re-verified.

function PIE_WriteFileAtomic([string]$Path,[string]$Text){
  if([string]::IsNullOrWhiteSpace($Path)){ throw "PIE_ATOMIC_WRITE_PATH_REQUIRED" }

  $dir = Split-Path -Parent $Path
  if([string]::IsNullOrWhiteSpace($dir)){ $dir = "." }
  if(-not (Test-Path -LiteralPath $dir -PathType Container)){
    try { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    catch { throw ("PIE_ATOMIC_WRITE_DIR_FAILED: " + $dir + " :: " + $_.Exception.Message) }
  }

  # Canonical text discipline: UTF-8 no BOM, LF, trailing newline (matches NL_WriteUtf8NoBomLf).
  $t = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  $enc = New-Object System.Text.UTF8Encoding($false)
  $bytes = $enc.GetBytes($t)

  $tmp = Join-Path $dir (".pie_atomic_" + [guid]::NewGuid().ToString('n') + ".tmp")
  try {
    $fs = [System.IO.File]::Open($tmp,[System.IO.FileMode]::CreateNew,[System.IO.FileAccess]::Write,[System.IO.FileShare]::None)
    try {
      $fs.Write($bytes,0,$bytes.Length)
      $fs.Flush($true)   # force OS buffers to disk before the rename (power-loss resilience)
    }
    finally { $fs.Dispose() }

    if(Test-Path -LiteralPath $Path -PathType Leaf){
      # Atomic same-volume replace. File.Replace requires a real backup path (a $null/empty backup
      # throws "path is not of a legal form" under PowerShell's string binding), so use a temp
      # backup and delete it afterwards. The replace itself stays atomic.
      $bak = Join-Path $dir (".pie_atomic_bak_" + [guid]::NewGuid().ToString('n') + ".tmp")
      try {
        [System.IO.File]::Replace($tmp,$Path,$bak)
      }
      finally {
        if(Test-Path -LiteralPath $bak -PathType Leaf){ Remove-Item -LiteralPath $bak -Force -ErrorAction SilentlyContinue }
      }
    } else {
      [System.IO.File]::Move($tmp,$Path)
    }
  }
  catch {
    if(Test-Path -LiteralPath $tmp -PathType Leaf){
      try { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue } catch { }
    }
    throw ("PIE_ATOMIC_WRITE_FAILED: " + $Path + " :: " + $_.Exception.Message)
  }
}

# Safe NDJSON read: returns @{ lines=[...]; torn=<bool> }. A non-newline-terminated final line
# indicates an interrupted append (torn tail) and is reported rather than silently accepted.
function PIE_ReadNdjsonSafe([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ return [pscustomobject]@{ lines=@(); torn=$false } }
  $enc = New-Object System.Text.UTF8Encoding($false)
  $raw = [System.IO.File]::ReadAllText($Path,$enc)
  if([string]::IsNullOrEmpty($raw)){ return [pscustomobject]@{ lines=@(); torn=$false } }
  $torn = -not $raw.EndsWith("`n")
  $lines = @($raw -split "`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  return [pscustomobject]@{ lines=$lines; torn=$torn }
}
