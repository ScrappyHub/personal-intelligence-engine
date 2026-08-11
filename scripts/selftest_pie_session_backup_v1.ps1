param([Parameter(Mandatory=$true)][string]$RepoRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $RepoRoot "scripts\_lib_pie_agent_session_v1.ps1")
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$SessionId = "pie_session_backup_selftest"
$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)
$TestRoot = Join-Path $RepoRoot "runs\pie_session_backup_fixture"
$ProjectRoot = Join-Path $TestRoot "project"
$BackupRoot = Join-Path $TestRoot "backups"
$HoldingRoot = Join-Path $TestRoot "original_session"
$PassphraseText = "Sunset backup selftest 2026!"
$Passphrase = ConvertTo-SecureString -String $PassphraseText -AsPlainText -Force
foreach($Target in @($RunRoot,$TestRoot)){ if(Test-Path -LiteralPath $Target -PathType Container){ Remove-Item -LiteralPath $Target -Recurse -Force } }
New-Item -ItemType Directory -Force -Path $ProjectRoot,$BackupRoot | Out-Null
$Enc = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText((Join-Path $ProjectRoot "README.md"),"# Backup fixture`n",$Enc)

function Invoke-BackupChild {
  param([string[]]$Arguments)
  $Id = [Guid]::NewGuid().ToString("N")
  $Stdout = Join-Path $TestRoot ($Id + ".stdout.txt")
  $Stderr = Join-Path $TestRoot ($Id + ".stderr.txt")
  $All = @("-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass","-File",(Join-Path $RepoRoot "scripts\pie_session_backup_v1.ps1"),"-RepoRoot",$RepoRoot) + $Arguments + @("-PassphraseStdin")
  $Start = New-Object Diagnostics.ProcessStartInfo
  $Start.FileName = "powershell.exe"
  $Start.Arguments = (($All | ForEach-Object { '"' + ([string]$_).Replace('"','\"') + '"' }) -join " ")
  $Start.WorkingDirectory = $RepoRoot
  $Start.UseShellExecute = $false
  $Start.CreateNoWindow = $true
  $Start.RedirectStandardInput = $true
  $Start.RedirectStandardOutput = $true
  $Start.RedirectStandardError = $true
  $Process = New-Object Diagnostics.Process
  $Process.StartInfo = $Start
  try {
    [void]$Process.Start()
    $Process.StandardInput.WriteLine($PassphraseText)
    $Process.StandardInput.Dispose()
    $Output = $Process.StandardOutput.ReadToEnd() + $Process.StandardError.ReadToEnd()
    $Process.WaitForExit()
    return [pscustomobject]@{exit_code=$Process.ExitCode;output=$Output}
  }
  finally { $Process.Dispose() }
}

& (Join-Path $RepoRoot "scripts\pie_agent_start_v1.ps1") -RepoRoot $RepoRoot -SessionId $SessionId -Backend mock -Model "backup-mock" -ProjectRepo $ProjectRoot -Goal "prove verified backup restore" | Out-Null
& (Join-Path $RepoRoot "scripts\pie_agent_send_v1.ps1") -RepoRoot $RepoRoot -SessionId $SessionId -Message "remember the backup boundary" -ConversationMessage "remember the backup boundary" -TimeoutSeconds 30 -MaxAttempts 1 | Out-Null
& (Join-Path $RepoRoot "scripts\pie_agent_stop_v1.ps1") -RepoRoot $RepoRoot -SessionId $SessionId | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $RunRoot "custom") | Out-Null
[IO.File]::WriteAllText((Join-Path $RunRoot "custom\unicode.txt"),"sunset café recall`n",$Enc)

$Lock = PIE_AcquireSessionLock -RunRoot $RunRoot
try {
  $Locked = Invoke-BackupChild -Arguments @("-Action","export","-SessionId",$SessionId,"-OutputDirectory",$BackupRoot)
  if($Locked.exit_code -eq 0 -or $Locked.output -notmatch "PIE_AGENT_SESSION_BUSY"){ throw "PIE_SESSION_BACKUP_SELFTEST_LOCK_NOT_ENFORCED" }
}
finally { $Lock.Dispose() }

& (Join-Path $RepoRoot "scripts\pie_session_backup_v1.ps1") -RepoRoot $RepoRoot -Action export -SessionId $SessionId -OutputDirectory $BackupRoot -Passphrase $Passphrase | Out-Null
$Archive = Get-ChildItem -LiteralPath $BackupRoot -File -Filter "*.piebak" | Select-Object -First 1
if($null -eq $Archive){ throw "PIE_SESSION_BACKUP_SELFTEST_ARCHIVE_MISSING" }
& (Join-Path $RepoRoot "scripts\pie_session_backup_v1.ps1") -RepoRoot $RepoRoot -Action verify -ArchivePath $Archive.FullName -Passphrase $Passphrase | Out-Null
$EnvelopeText = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($Archive.FullName))
foreach($Leaked in @($SessionId,"remember the backup boundary","conversation.ndjson","PIE_SESSION_BACKUP.json")){ if($EnvelopeText.Contains($Leaked)){ throw ("PIE_SESSION_BACKUP_SELFTEST_PLAINTEXT_LEAK: " + $Leaked) } }

$Collision = Invoke-BackupChild -Arguments @("-Action","restore","-ArchivePath",$Archive.FullName)
if($Collision.exit_code -eq 0 -or $Collision.output -notmatch "PIE_SESSION_RESTORE_COLLISION"){ throw "PIE_SESSION_BACKUP_SELFTEST_COLLISION_NOT_BLOCKED" }

$WrongPassphraseText = "Definitely the wrong passphrase!"
$OriginalPassphraseText = $PassphraseText
$StagingBefore = @(Get-ChildItem -LiteralPath (Join-Path $RepoRoot "runs\session_backups") -Directory -Filter ".verify_*" -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
$PassphraseText = $WrongPassphraseText
$WrongPassword = Invoke-BackupChild -Arguments @("-Action","verify","-ArchivePath",$Archive.FullName)
$PassphraseText = $OriginalPassphraseText
if($WrongPassword.exit_code -eq 0 -or $WrongPassword.output -notmatch "PIE_SESSION_BACKUP_DECRYPT_AUTH_FAILED"){ throw "PIE_SESSION_BACKUP_SELFTEST_WRONG_PASSWORD_NOT_BLOCKED" }

$CorruptArchive = Join-Path $BackupRoot "corrupt.piebak"
Copy-Item -LiteralPath $Archive.FullName -Destination $CorruptArchive
$CorruptBytes = [IO.File]::ReadAllBytes($CorruptArchive)
$CorruptBytes[[Math]::Floor($CorruptBytes.Length / 2)] = $CorruptBytes[[Math]::Floor($CorruptBytes.Length / 2)] -bxor 1
[IO.File]::WriteAllBytes($CorruptArchive,$CorruptBytes)
$Corrupt = Invoke-BackupChild -Arguments @("-Action","verify","-ArchivePath",$CorruptArchive)
if($Corrupt.exit_code -eq 0 -or $Corrupt.output -notmatch "PIE_SESSION_BACKUP_DECRYPT_AUTH_FAILED"){ throw "PIE_SESSION_BACKUP_SELFTEST_CORRUPTION_NOT_BLOCKED" }
$StagingAfter = @(Get-ChildItem -LiteralPath (Join-Path $RepoRoot "runs\session_backups") -Directory -Filter ".verify_*" -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
if(@($StagingAfter | Where-Object { $_ -notin $StagingBefore }).Count -ne 0){ throw "PIE_SESSION_BACKUP_SELFTEST_DECRYPT_PLAINTEXT_REMAINS" }

$TraversalZip = Join-Path $BackupRoot "traversal.zip"
$TraversalArchive = Join-Path $BackupRoot "traversal.piebak"
$Zip = [IO.Compression.ZipFile]::Open($TraversalZip,[IO.Compression.ZipArchiveMode]::Create)
try {
  foreach($Name in @("PIE_SESSION_BACKUP.json","../escaped.txt")){
    $Entry = $Zip.CreateEntry($Name)
    $Writer = New-Object IO.StreamWriter($Entry.Open(),$Enc)
    try { $Writer.Write("{}") } finally { $Writer.Dispose() }
  }
}
finally { $Zip.Dispose() }
$PassphraseText | & node (Join-Path $RepoRoot "scripts\pie_backup_crypto_v1.js") encrypt $TraversalZip $TraversalArchive | Out-Null
if($LASTEXITCODE -ne 0){ throw "PIE_SESSION_BACKUP_SELFTEST_TRAVERSAL_ENCRYPT_FAILED" }
$Traversal = Invoke-BackupChild -Arguments @("-Action","verify","-ArchivePath",$TraversalArchive)
if($Traversal.exit_code -eq 0 -or $Traversal.output -notmatch "PIE_SESSION_BACKUP_PATH_INVALID"){ throw "PIE_SESSION_BACKUP_SELFTEST_TRAVERSAL_NOT_BLOCKED" }
if(Test-Path -LiteralPath (Join-Path $RepoRoot "runs\session_backups\escaped.txt")){ throw "PIE_SESSION_BACKUP_SELFTEST_PATH_ESCAPED" }

Move-Item -LiteralPath $RunRoot -Destination $HoldingRoot
try {
  & (Join-Path $RepoRoot "scripts\pie_session_backup_v1.ps1") -RepoRoot $RepoRoot -Action restore -ArchivePath $Archive.FullName -Passphrase $Passphrase | Out-Null
  $Restored = PIE_GetAgentSession -RepoRoot $RepoRoot -SessionId $SessionId -RequireIntegrity
  if(@($Restored.conversation_turns).Count -ne 1 -or [string]$Restored.conversation_turns[0].message -ne "remember the backup boundary"){ throw "PIE_SESSION_BACKUP_SELFTEST_HISTORY_CHANGED" }
  if((PIE_ReadUtf8Text -Path (Join-Path $RunRoot "custom\unicode.txt")).Trim() -ne "sunset café recall"){ throw "PIE_SESSION_BACKUP_SELFTEST_ARTIFACT_CHANGED" }
  $SecondCollision = Invoke-BackupChild -Arguments @("-Action","restore","-ArchivePath",$Archive.FullName)
  if($SecondCollision.exit_code -eq 0 -or $SecondCollision.output -notmatch "PIE_SESSION_RESTORE_COLLISION"){ throw "PIE_SESSION_BACKUP_SELFTEST_SECOND_COLLISION_NOT_BLOCKED" }
}
finally { if(Test-Path -LiteralPath $HoldingRoot -PathType Container){ Remove-Item -LiteralPath $HoldingRoot -Recurse -Force } }

$ReceiptText = @(Get-ChildItem -LiteralPath (Join-Path $RepoRoot "runs\session_backups\receipts") -File | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
if($ReceiptText.Contains($PassphraseText) -or $ReceiptText.Contains($WrongPassphraseText)){ throw "PIE_SESSION_BACKUP_SELFTEST_PASSPHRASE_PERSISTED" }

Write-Host "PIE_SESSION_BACKUP_SELFTEST_OK" -ForegroundColor Green
