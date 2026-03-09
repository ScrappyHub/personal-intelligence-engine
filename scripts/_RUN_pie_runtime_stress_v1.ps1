param(
    [Parameter(Mandatory=$true)][string]$RepoRoot,
    [int]$Iterations = 25
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$PSExe = (Get-Command powershell.exe -ErrorAction Stop).Source

function Run-Child {
    param(
        [Parameter(Mandatory=$true)][string]$ScriptPath,
        [Parameter(Mandatory=$true)][string[]]$ArgumentList
    )

    if(-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)){
        throw ("MISSING_CHILD_SCRIPT: " + $ScriptPath)
    }

    & $PSExe @ArgumentList
    if($LASTEXITCODE -ne 0){
        throw ("CHILD_FAIL exit=" + $LASTEXITCODE + " script=" + $ScriptPath)
    }
}

for($i=1; $i -le $Iterations; $i++){

    $runId = "stress_" + $i
    $packetRoot = Join-Path $RepoRoot ("proofs\runs\" + $runId + "\packet")

    Write-Host ("RUN " + $runId) -ForegroundColor Cyan

    Run-Child `
        -ScriptPath (Join-Path $RepoRoot "scripts\pie_seal_run_v1.ps1") `
        -ArgumentList @(
            "-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass",
            "-File",(Join-Path $RepoRoot "scripts\pie_seal_run_v1.ps1"),
            "-RepoRoot",$RepoRoot,
            "-RunId",$runId
        )

    Run-Child `
        -ScriptPath (Join-Path $RepoRoot "scripts\pie_build_packet_optionA_v1.ps1") `
        -ArgumentList @(
            "-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass",
            "-File",(Join-Path $RepoRoot "scripts\pie_build_packet_optionA_v1.ps1"),
            "-RepoRoot",$RepoRoot,
            "-RunId",$runId
        )

    Run-Child `
        -ScriptPath (Join-Path $RepoRoot "scripts\pie_run_packet_sign_v1.ps1") `
        -ArgumentList @(
            "-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass",
            "-File",(Join-Path $RepoRoot "scripts\pie_run_packet_sign_v1.ps1"),
            "-RepoRoot",$RepoRoot,
            "-PacketRoot",$packetRoot
        )

    Run-Child `
        -ScriptPath (Join-Path $RepoRoot "scripts\pie_verify_packet_optionA_v1.ps1") `
        -ArgumentList @(
            "-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass",
            "-File",(Join-Path $RepoRoot "scripts\pie_verify_packet_optionA_v1.ps1"),
            "-RepoRoot",$RepoRoot,
            "-PacketRoot",$packetRoot
        )
}

Write-Host "PIE_RUNTIME_STRESS_COMPLETE" -ForegroundColor Green