$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "_lib_neverlost_v1.ps1")
function PIE_Die([string]$m){ throw $m }
function PIE_Sha256HexBytes([byte[]]$b){ if($null -eq $b){$b=@()} $sha=[System.Security.Cryptography.SHA256]::Create(); try{$h=$sha.ComputeHash([byte[]]$b)} finally{$sha.Dispose()} $sb=New-Object System.Text.StringBuilder; foreach($x in $h){[void]$sb.Append($x.ToString("x2"))}; $sb.ToString() }
function PIE_Sha256HexFile([string]$Path){ if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ PIE_Die ("missing_file: " + $Path) } $b=[System.IO.File]::ReadAllBytes($Path); PIE_Sha256HexBytes $b }
function PIE_RegistryRoot([string]$RepoRoot){ Join-Path $RepoRoot "registry\models" }
function PIE_ModelManifestPath([string]$RepoRoot,[string]$ModelId){ Join-Path (PIE_RegistryRoot $RepoRoot) (Join-Path $ModelId "model_manifest.v1.json") }
function PIE_RunLedgerPath([string]$RepoRoot){ Join-Path $RepoRoot "runs\run_ledger.ndjson" }
function PIE_AppendRunLedger([string]$RepoRoot,[hashtable]$run){ $p=PIE_RunLedgerPath $RepoRoot; $enc=New-Object System.Text.UTF8Encoding($false); $prev=""; if(Test-Path -LiteralPath $p -PathType Leaf){ $lines=@(@([System.IO.File]::ReadAllLines($p,$enc))); if($lines.Count -gt 0){ $prev=$lines[$lines.Count-1] } } if(-not [string]::IsNullOrWhiteSpace($prev)){ $run.prev_hash = PIE_Sha256HexBytes ([System.Text.Encoding]::UTF8.GetBytes($prev)) } $line=NL_ToCanonJson $run; [System.IO.File]::AppendAllText($p, ($line + "`n"), $enc); NL_AppendReceipt $RepoRoot "pie_run_ledger" "appended run ledger entry" @{ run_id=$run.run_id; line_sha256=(PIE_Sha256HexBytes([System.Text.Encoding]::UTF8.GetBytes($line))) }; $line }
