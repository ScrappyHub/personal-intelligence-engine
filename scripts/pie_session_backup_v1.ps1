param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][ValidateSet("export","verify","restore")][string]$Action,
  [Parameter(Mandatory=$false)][string]$SessionId = "",
  [Parameter(Mandatory=$false)][string]$ArchivePath = "",
  [Parameter(Mandatory=$false)][string]$OutputDirectory = "",
  [Parameter(Mandatory=$false)][Security.SecureString]$Passphrase,
  [Parameter(Mandatory=$false)][switch]$PassphraseStdin
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $RepoRoot "scripts\_lib_pie_agent_session_v1.ps1")
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$Enc = New-Object System.Text.UTF8Encoding($false)
$MaxFiles = 10000
$MaxBytes = [int64]2147483648
$MaxFileBytes = [int64]1073741824
$ReceiptRoot = Join-Path $RepoRoot "runs\session_backups\receipts"
$CryptoHelper = Join-Path $RepoRoot "scripts\pie_backup_crypto_v1.js"
if(-not (Test-Path -LiteralPath $CryptoHelper -PathType Leaf)){ throw "PIE_SESSION_BACKUP_CRYPTO_HELPER_MISSING" }

function Get-BackupPassphrase {
  param([Parameter(Mandatory=$true)][bool]$Confirm)
  if($PassphraseStdin){
    $Value = [Console]::In.ReadLine()
    if($null -eq $Value){ throw "PIE_SESSION_BACKUP_PASSPHRASE_REQUIRED" }
    return $Value
  }
  if($null -ne $Passphrase){
    $Pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Passphrase)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($Pointer) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($Pointer) }
  }
  $First = Read-Host "Backup passphrase (14+ characters)" -AsSecureString
  $Pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($First)
  try { $FirstText = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($Pointer) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($Pointer) }
  if($Confirm){
    $Second = Read-Host "Confirm backup passphrase" -AsSecureString
    $Pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Second)
    try { $SecondText = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($Pointer) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($Pointer) }
    if($FirstText -cne $SecondText){ $FirstText=$null;$SecondText=$null;throw "PIE_SESSION_BACKUP_PASSPHRASE_CONFIRMATION_MISMATCH" }
    $SecondText = $null
  }
  return $FirstText
}

function Invoke-BackupCrypto {
  param([ValidateSet("encrypt","decrypt")][string]$Mode,[string]$InputPath,[string]$OutputPath,[string]$Secret)
  $Node = Get-Command node -ErrorAction SilentlyContinue
  if($null -eq $Node){ throw "PIE_SESSION_BACKUP_NODE_REQUIRED" }
  if($Secret.Contains("`r") -or $Secret.Contains("`n")){ throw "PIE_SESSION_BACKUP_PASSPHRASE_NEWLINE_INVALID" }
  $Start = New-Object Diagnostics.ProcessStartInfo
  $Start.FileName = $Node.Source
  $Start.Arguments = ('"{0}" {1} "{2}" "{3}"' -f $CryptoHelper,$Mode,$InputPath,$OutputPath)
  $Start.WorkingDirectory = $RepoRoot
  $Start.UseShellExecute = $false
  $Start.CreateNoWindow = $true
  $Start.RedirectStandardInput = $true
  $Start.RedirectStandardOutput = $true
  $Start.RedirectStandardError = $true
  $Process = New-Object Diagnostics.Process
  $Process.StartInfo = $Start
  try {
    if(-not $Process.Start()){ throw "PIE_SESSION_BACKUP_CRYPTO_START_FAILED" }
    $Process.StandardInput.WriteLine($Secret)
    $Process.StandardInput.Dispose()
    $Stdout = $Process.StandardOutput.ReadToEnd()
    $Stderr = $Process.StandardError.ReadToEnd()
    $Process.WaitForExit()
    if($Process.ExitCode -ne 0){ throw ($(if([string]::IsNullOrWhiteSpace($Stderr)){"PIE_SESSION_BACKUP_CRYPTO_FAILED"}else{$Stderr.Trim()})) }
    try { return ($Stdout | ConvertFrom-Json) } catch { throw "PIE_SESSION_BACKUP_CRYPTO_OUTPUT_INVALID" }
  }
  finally { $Process.Dispose() }
}

function Get-FileSha256 {
  param([Parameter(Mandatory=$true)][string]$Path)
  $Stream = [IO.File]::OpenRead($Path)
  $Hasher = [Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($Hasher.ComputeHash($Stream))).Replace("-","").ToLowerInvariant() }
  finally { $Hasher.Dispose(); $Stream.Dispose() }
}

function Write-BackupReceipt {
  param([string]$Event,[string]$Status,[string]$Id,[string]$Session,[string]$Archive,[string]$Detail)
  if(-not (Test-Path -LiteralPath $ReceiptRoot -PathType Container)){ New-Item -ItemType Directory -Force -Path $ReceiptRoot | Out-Null }
  $Receipt = [ordered]@{schema="pie.session.backup.receipt.v1";event=$Event;status=$Status;backup_id=$Id;session_id=$Session;archive=$Archive;detail=$Detail;created_utc=[DateTime]::UtcNow.ToString("o")}
  $Path = Join-Path $ReceiptRoot ("session_backup_" + [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss_fff") + ".json")
  [IO.File]::WriteAllText($Path,(($Receipt | ConvertTo-Json -Depth 8) + "`n"),$Enc)
  return $Path
}

function Assert-RelativePath {
  param([Parameter(Mandatory=$true)][string]$Relative)
  if([string]::IsNullOrWhiteSpace($Relative) -or $Relative.Contains("\") -or $Relative.StartsWith("/") -or $Relative.Contains(":") -or $Relative -match '(^|/)\.\.(/|$)' -or $Relative -match '(^|/)\.(/|$)'){
    throw ("PIE_SESSION_BACKUP_PATH_INVALID: " + $Relative)
  }
}

function Get-BackupId {
  param([object]$Manifest)
  $Lines = New-Object System.Collections.Generic.List[string]
  foreach($Value in @("pie.session.backup.v1",[string]$Manifest.session_id,[string]$Manifest.binding_sha256,[string]$Manifest.project_identity_sha256,[string]$Manifest.model_identity_sha256,[string]$Manifest.conversation_tail_sha256,[string]$Manifest.turn_count)){
    [void]$Lines.Add(([string]$Value).Replace("`r`n","`n").Replace("`r","`n"))
  }
  foreach($File in @($Manifest.files | Sort-Object path)){
    [void]$Lines.Add(([string]$File.path + "`t" + [string]$File.bytes + "`t" + [string]$File.sha256))
  }
  return PIE_Sha256Text -Text ($Lines.ToArray() -join "`n")
}

function Expand-VerifiedBackup {
  param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)][string]$Secret)
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ throw ("PIE_SESSION_BACKUP_ARCHIVE_NOT_FOUND: " + $Path) }
  $ResolvedArchive = (Resolve-Path -LiteralPath $Path).Path
  $Stage = Join-Path $RepoRoot ("runs\session_backups\.verify_" + [Guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Force -Path $Stage | Out-Null
  $PlainArchive = Join-Path $Stage "payload.zip"
  $Archive = $null
  $Succeeded = $false
  try {
    $null = Invoke-BackupCrypto -Mode decrypt -InputPath $ResolvedArchive -OutputPath $PlainArchive -Secret $Secret
    $Archive = [IO.Compression.ZipFile]::OpenRead($PlainArchive)
    $Entries = @($Archive.Entries | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Name) })
    if($Entries.Count -lt 2 -or $Entries.Count -gt ($MaxFiles + 1)){ throw "PIE_SESSION_BACKUP_FILE_COUNT_INVALID" }
    $Seen = @{}
    $Total = [int64]0
    foreach($Entry in $Entries){
      $Name = $Entry.FullName.Replace("\","/")
      Assert-RelativePath -Relative $Name
      $Key = $Name.ToLowerInvariant()
      if($Seen.ContainsKey($Key)){ throw ("PIE_SESSION_BACKUP_DUPLICATE_ENTRY: " + $Name) }
      $Seen[$Key] = $true
      if([int64]$Entry.Length -gt $MaxFileBytes){ throw ("PIE_SESSION_BACKUP_FILE_TOO_LARGE: " + $Name) }
      $Total += [int64]$Entry.Length
      if($Total -gt $MaxBytes){ throw "PIE_SESSION_BACKUP_EXPANDED_SIZE_LIMIT" }
      if($Name -ne "PIE_SESSION_BACKUP.json" -and -not $Name.StartsWith("session/")){ throw ("PIE_SESSION_BACKUP_ENTRY_OUTSIDE_PAYLOAD: " + $Name) }
      $Destination = Join-Path $Stage $Name.Replace("/","\")
      $DestinationFull = [IO.Path]::GetFullPath($Destination)
      if(-not $DestinationFull.StartsWith(([IO.Path]::GetFullPath($Stage) + [IO.Path]::DirectorySeparatorChar),[StringComparison]::OrdinalIgnoreCase)){ throw ("PIE_SESSION_BACKUP_PATH_ESCAPE: " + $Name) }
      $Parent = Split-Path -Parent $DestinationFull
      if(-not (Test-Path -LiteralPath $Parent -PathType Container)){ New-Item -ItemType Directory -Force -Path $Parent | Out-Null }
      $Input = $Entry.Open()
      $Output = [IO.File]::Open($DestinationFull,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
      try { $Input.CopyTo($Output) } finally { $Output.Dispose(); $Input.Dispose() }
    }
    $ManifestPath = Join-Path $Stage "PIE_SESSION_BACKUP.json"
    try { $Manifest = PIE_ReadUtf8Text -Path $ManifestPath | ConvertFrom-Json }
    catch { throw ("PIE_SESSION_BACKUP_MANIFEST_INVALID: " + $_.Exception.Message) }
    if([string]$Manifest.schema -ne "pie.session.backup.v1"){ throw "PIE_SESSION_BACKUP_SCHEMA_BAD" }
    if([string]$Manifest.session_id -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$'){ throw "PIE_SESSION_BACKUP_SESSION_ID_INVALID" }
    if([string]$Manifest.binding_sha256 -notmatch '^[0-9a-f]{64}$' -or [string]$Manifest.backup_id -notmatch '^[0-9a-f]{64}$'){ throw "PIE_SESSION_BACKUP_HASH_FIELD_INVALID" }
    $Expected = @($Manifest.files)
    if($Expected.Count -lt 7 -or $Expected.Count -gt $MaxFiles){ throw "PIE_SESSION_BACKUP_MANIFEST_FILE_COUNT_INVALID" }
    $ExpectedNames = @{}
    foreach($File in $Expected){
      $Relative = [string]$File.path
      Assert-RelativePath -Relative $Relative
      $Key = $Relative.ToLowerInvariant()
      if($ExpectedNames.ContainsKey($Key)){ throw ("PIE_SESSION_BACKUP_MANIFEST_DUPLICATE: " + $Relative) }
      $ExpectedNames[$Key] = $true
      $PayloadPath = Join-Path $Stage ("session\" + $Relative.Replace("/","\"))
      if(-not (Test-Path -LiteralPath $PayloadPath -PathType Leaf)){ throw ("PIE_SESSION_BACKUP_FILE_MISSING: " + $Relative) }
      $Item = Get-Item -LiteralPath $PayloadPath
      if([int64]$File.bytes -ne [int64]$Item.Length){ throw ("PIE_SESSION_BACKUP_SIZE_MISMATCH: " + $Relative) }
      if([string]$File.sha256 -ne (Get-FileSha256 -Path $PayloadPath)){ throw ("PIE_SESSION_BACKUP_HASH_MISMATCH: " + $Relative) }
    }
    $PayloadEntries = @($Entries | Where-Object { $_.FullName.Replace("\","/").StartsWith("session/") } | ForEach-Object { $_.FullName.Replace("\","/").Substring(8).ToLowerInvariant() })
    if($PayloadEntries.Count -ne $ExpectedNames.Count){ throw "PIE_SESSION_BACKUP_UNMANIFESTED_FILE" }
    foreach($Name in $PayloadEntries){ if(-not $ExpectedNames.ContainsKey($Name)){ throw ("PIE_SESSION_BACKUP_UNMANIFESTED_FILE: " + $Name) } }
    $ComputedId = Get-BackupId -Manifest $Manifest
    if($ComputedId -ne [string]$Manifest.backup_id){ throw "PIE_SESSION_BACKUP_ID_MISMATCH" }
    $Succeeded = $true
    return [pscustomobject]@{stage=$Stage;manifest=$Manifest;archive=$ResolvedArchive}
  }
  catch { throw }
  finally {
    if($null -ne $Archive){ $Archive.Dispose() }
    if(-not $Succeeded -and (Test-Path -LiteralPath $Stage -PathType Container)){ Remove-Item -LiteralPath $Stage -Recurse -Force }
  }
}

$Secret = Get-BackupPassphrase -Confirm:($Action -eq "export")
if($Secret.Length -lt 14 -or $Secret.Length -gt 1024){ $Secret=$null;throw "PIE_SESSION_BACKUP_PASSPHRASE_LENGTH_INVALID" }

if($Action -eq "export"){
  if([string]::IsNullOrWhiteSpace($SessionId)){ throw "PIE_SESSION_BACKUP_SESSION_ID_REQUIRED" }
  $RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)
  $Lock = PIE_AcquireSessionLock -RunRoot $RunRoot
  try {
    $Session = PIE_GetAgentSession -RepoRoot $RepoRoot -SessionId $SessionId -RequireIntegrity -OperationLockHeld
    if(Test-Path -LiteralPath (Join-Path $RunRoot "state\pending-transition.json") -PathType Leaf){ throw "PIE_SESSION_BACKUP_TRANSITION_PENDING" }
    if([string]::IsNullOrWhiteSpace($OutputDirectory)){ $OutputDirectory = Join-Path $RepoRoot "backups" }
    $OutputFull = [IO.Path]::GetFullPath($OutputDirectory)
    $RunFull = [IO.Path]::GetFullPath($RunRoot)
    if($OutputFull.StartsWith($RunFull + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){ throw "PIE_SESSION_BACKUP_OUTPUT_INSIDE_SESSION" }
    New-Item -ItemType Directory -Force -Path $OutputFull | Out-Null
    $Files = @(
      Get-ChildItem -LiteralPath $RunRoot -Recurse -File | Where-Object {
        $Relative = $_.FullName.Substring($RunRoot.Length).TrimStart("\").Replace("\","/")
        $Relative -notin @("state/session-operation.lock","state/transition-recovery.lock") -and $_.Name -notlike "*.pie-tmp-*"
      } | Sort-Object FullName
    )
    if($Files.Count -lt 7 -or $Files.Count -gt $MaxFiles){ throw "PIE_SESSION_BACKUP_FILE_COUNT_INVALID" }
    $Total = [int64]0
    $ManifestFiles = New-Object System.Collections.Generic.List[object]
    foreach($File in $Files){
      if(($File.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){ throw ("PIE_SESSION_BACKUP_LINK_NOT_ALLOWED: " + $File.FullName) }
      if([int64]$File.Length -gt $MaxFileBytes){ throw ("PIE_SESSION_BACKUP_FILE_TOO_LARGE: " + $File.FullName) }
      $Total += [int64]$File.Length
      if($Total -gt $MaxBytes){ throw "PIE_SESSION_BACKUP_EXPANDED_SIZE_LIMIT" }
      $Relative = $File.FullName.Substring($RunRoot.Length).TrimStart("\").Replace("\","/")
      Assert-RelativePath -Relative $Relative
      [void]$ManifestFiles.Add([ordered]@{path=$Relative;bytes=[int64]$File.Length;sha256=(Get-FileSha256 -Path $File.FullName)})
    }
    $Turns = @($Session.conversation_turns)
    $Tail = $(if($Turns.Count){[string]$Turns[-1].turn_sha256}else{""})
    $Manifest = [ordered]@{
      schema="pie.session.backup.v1";session_id=$SessionId;binding_sha256=[string]$Session.binding_sha256
      project_identity_sha256=[string]$Session.project_identity_sha256;model_identity_sha256=[string]$Session.model_identity_sha256
      conversation_tail_sha256=$Tail;turn_count=$Turns.Count;created_utc=[DateTime]::UtcNow.ToString("o");files=@($ManifestFiles.ToArray())
    }
    # Hash the same JSON object shape that an independent verifier reads back.
    $ManifestForHash = ($Manifest | ConvertTo-Json -Depth 12 -Compress) | ConvertFrom-Json
    $Manifest.backup_id = Get-BackupId -Manifest $ManifestForHash
    $ArchiveName = "pie-session-" + $SessionId + "-" + $Manifest.backup_id.Substring(0,12) + ".piebak"
    $Destination = Join-Path $OutputFull $ArchiveName
    if(Test-Path -LiteralPath $Destination -PathType Leaf){
      $Existing = Expand-VerifiedBackup -Path $Destination -Secret $Secret
      try {
        if([string]$Existing.manifest.backup_id -ne [string]$Manifest.backup_id){ throw ("PIE_SESSION_BACKUP_ARCHIVE_COLLISION: " + $Destination) }
      }
      finally { if(Test-Path -LiteralPath $Existing.stage -PathType Container){ Remove-Item -LiteralPath $Existing.stage -Recurse -Force } }
      $Receipt = Write-BackupReceipt -Event "export" -Status "already_verified" -Id $Manifest.backup_id -Session $SessionId -Archive $Destination -Detail ("files=" + $Files.Count)
      Write-Host ("PIE_SESSION_BACKUP_EXPORT_ALREADY_VERIFIED: " + $Destination) -ForegroundColor Green
      Write-Host ("backup_id: " + $Manifest.backup_id)
      Write-Host ("receipt: " + $Receipt)
      return
    }
    $Stage = Join-Path $OutputFull (".pie_session_export_" + [Guid]::NewGuid().ToString("N"))
    try {
      $StageContent = Join-Path $Stage "content"
      $StageSession = Join-Path $StageContent "session"
      New-Item -ItemType Directory -Force -Path $StageSession | Out-Null
      foreach($File in $Files){
        $Relative = $File.FullName.Substring($RunRoot.Length).TrimStart("\")
        $Target = Join-Path $StageSession $Relative
        $Parent = Split-Path -Parent $Target
        if(-not (Test-Path -LiteralPath $Parent -PathType Container)){ New-Item -ItemType Directory -Force -Path $Parent | Out-Null }
        Copy-Item -LiteralPath $File.FullName -Destination $Target
      }
      [IO.File]::WriteAllText((Join-Path $StageContent "PIE_SESSION_BACKUP.json"),(($Manifest | ConvertTo-Json -Depth 12) + "`n"),$Enc)
      $PlainArchive = Join-Path $Stage "payload.zip"
      Compress-Archive -Path (Join-Path $StageContent "*") -DestinationPath $PlainArchive -CompressionLevel Optimal
      # Crash-atomic export: encrypt to a temp path, verify it decrypts + matches, then atomically
      # promote to the final .piebak. A crash never leaves a partial or unverifiable archive at the
      # destination path (either the complete verified backup exists there, or nothing does).
      $TempOut = Join-Path $Stage "archive.piebak.partial"
      $null = Invoke-BackupCrypto -Mode encrypt -InputPath $PlainArchive -OutputPath $TempOut -Secret $Secret
      if($env:PIE_FAULT_AFTER_BACKUP_ENCRYPT -eq "1"){ throw "PIE_FAULT_INJECTED_AFTER_BACKUP_ENCRYPT" }
      $SelfCheck = Expand-VerifiedBackup -Path $TempOut -Secret $Secret
      try {
        if([string]$SelfCheck.manifest.backup_id -ne [string]$Manifest.backup_id){ throw ("PIE_SESSION_BACKUP_SELFVERIFY_MISMATCH: " + [string]$Manifest.backup_id) }
      }
      finally { if(Test-Path -LiteralPath $SelfCheck.stage -PathType Container){ Remove-Item -LiteralPath $SelfCheck.stage -Recurse -Force } }
      [System.IO.File]::Move($TempOut, $Destination)
    }
    finally { if(Test-Path -LiteralPath $Stage -PathType Container){ Remove-Item -LiteralPath $Stage -Recurse -Force } }
    $Receipt = Write-BackupReceipt -Event "export" -Status "verified" -Id $Manifest.backup_id -Session $SessionId -Archive $Destination -Detail ("files=" + $Files.Count)
    Write-Host ("PIE_SESSION_BACKUP_EXPORT_OK: " + $Destination) -ForegroundColor Green
    Write-Host ("backup_id: " + $Manifest.backup_id)
    Write-Host ("receipt: " + $Receipt)
  }
  finally { $Lock.Dispose() }
  return
}

if([string]::IsNullOrWhiteSpace($ArchivePath)){ throw "PIE_SESSION_BACKUP_ARCHIVE_REQUIRED" }
$Verified = Expand-VerifiedBackup -Path $ArchivePath -Secret $Secret
try {
  $Manifest = $Verified.manifest
  if($Action -eq "verify"){
    $Receipt = Write-BackupReceipt -Event "verify" -Status "verified" -Id ([string]$Manifest.backup_id) -Session ([string]$Manifest.session_id) -Archive $Verified.archive -Detail ("files=" + @($Manifest.files).Count)
    Write-Host ("PIE_SESSION_BACKUP_VERIFY_OK: " + [string]$Manifest.backup_id) -ForegroundColor Green
    Write-Host ("session: " + [string]$Manifest.session_id)
    Write-Host ("receipt: " + $Receipt)
    return
  }
  $RestoreSessionId = [string]$Manifest.session_id
  $Destination = Join-Path $RepoRoot ("runs\" + $RestoreSessionId)
  if(Test-Path -LiteralPath $Destination){ throw ("PIE_SESSION_RESTORE_COLLISION: " + $RestoreSessionId) }
  $Payload = Join-Path $Verified.stage "session"
  Move-Item -LiteralPath $Payload -Destination $Destination
  $Moved = $true
  try {
    $Session = PIE_GetAgentSession -RepoRoot $RepoRoot -SessionId $RestoreSessionId -RequireIntegrity
    $Turns = @($Session.conversation_turns)
    $Tail = $(if($Turns.Count){[string]$Turns[-1].turn_sha256}else{""})
    if([string]$Session.binding_sha256 -ne [string]$Manifest.binding_sha256 -or $Turns.Count -ne [int]$Manifest.turn_count -or $Tail -ne [string]$Manifest.conversation_tail_sha256){ throw "PIE_SESSION_RESTORE_SESSION_MISMATCH" }
    $Receipt = Write-BackupReceipt -Event "restore" -Status "verified" -Id ([string]$Manifest.backup_id) -Session $RestoreSessionId -Archive $Verified.archive -Detail ("files=" + @($Manifest.files).Count)
    Write-Host ("PIE_SESSION_RESTORE_OK: " + $RestoreSessionId) -ForegroundColor Green
    Write-Host ("backup_id: " + [string]$Manifest.backup_id)
    Write-Host ("receipt: " + $Receipt)
  }
  catch {
    if($Moved -and (Test-Path -LiteralPath $Destination -PathType Container)){ Remove-Item -LiteralPath $Destination -Recurse -Force }
    throw
  }
}
finally { if(Test-Path -LiteralPath $Verified.stage -PathType Container){ Remove-Item -LiteralPath $Verified.stage -Recurse -Force } }
