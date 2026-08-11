Set-StrictMode -Version Latest

function PIE_GroundResponse {
  param(
    [Parameter(Mandatory=$true)][AllowEmptyString()][string]$Response,
    [Parameter(Mandatory=$true)][string]$ProjectRepo
  )

  $Corrections = New-Object System.Collections.Generic.List[string]
  $GroundedResponse = $Response
  $ProjectRepo = (Resolve-Path -LiteralPath $ProjectRepo).Path
  $ParentRepo = Split-Path -Parent $ProjectRepo
  $Tick = [char]96
  $WrongRootToken = [string]$Tick + $ParentRepo + "\" + [string]$Tick
  $CorrectRootToken = [string]$Tick + $ProjectRepo + [string]$Tick

  if($GroundedResponse.Contains($WrongRootToken)){
    $GroundedResponse = $GroundedResponse.Replace($WrongRootToken,$CorrectRootToken)
    [void]$Corrections.Add("Corrected the repository root to " + $ProjectRepo + ".")
  }

  $MemoryScripts = @(Get-ChildItem -LiteralPath (Join-Path $ProjectRepo "scripts") -Filter "pie_memory*_v1.ps1" -File -ErrorAction SilentlyContinue | Sort-Object Name)
  $MemoryTests = @(Get-ChildItem -LiteralPath (Join-Path $ProjectRepo "scripts") -Filter "selftest_pie_memory*_v1.ps1" -File -ErrorAction SilentlyContinue | Sort-Object Name)
  $ClaimsMemoryMissing = $GroundedResponse -match '(?is)(memory.{0,220}(no concrete implementation|not implemented|has not been implemented)|no concrete implementation.{0,220}memory)'
  if($ClaimsMemoryMissing -and ($MemoryScripts.Count + $MemoryTests.Count) -gt 0){
    $Evidence = @($MemoryScripts.Name + $MemoryTests.Name) -join ", "
    [void]$Corrections.Add("The claim that memory lacks a concrete implementation is contradicted by repository evidence: " + $Evidence + ".")
  }

  $GovernanceEvidenceNames = @(
    "GOVERNANCE_GREEN_RUNNER_PIE_v1.ps1","pie_green_audit_v1.ps1","pie_policy_decide_v1.ps1",
    "pie_reason_trace_v1.ps1","pie_execution_replay_v1.ps1","pie_exec_with_snapshot_v1.ps1",
    "pie_state_snapshot_v1.ps1","pie_green_terminal_receipt_v1.ps1","pie_run_packet_sign_v1.ps1"
  )
  $GovernanceEvidence = @($GovernanceEvidenceNames | Where-Object { Test-Path -LiteralPath (Join-Path $ProjectRepo ("scripts\" + $_)) -PathType Leaf })
  $ClaimsGovernanceMissing = $GroundedResponse -match '(?is)(lack.{0,180}(governance|audit|traceability)|governance.{0,180}(missing|not implemented|lack)|lacks robust mechanisms.{0,180}(tracking|audit)|no scripts dedicated.{0,180}(governance|security))'
  if($ClaimsGovernanceMissing -and $GovernanceEvidence.Count -gt 0){
    [void]$Corrections.Add("Broad claims that PIE lacks governance, auditing, security controls, or traceability are contradicted by policy, audit, replay, snapshot, signing, reason-trace, and receipt scripts: " + ($GovernanceEvidence -join ", ") + ". This evidence does not by itself prove comprehensive encryption or regulatory compliance.")
  }

  $WorkbenchPath = Join-Path $ProjectRepo "workbench"
  $WorkbenchImplementationFiles = @()
  if(Test-Path -LiteralPath $WorkbenchPath -PathType Container){
    $WorkbenchImplementationFiles = @(Get-ChildItem -LiteralPath $WorkbenchPath -Recurse -File -ErrorAction SilentlyContinue |
      Where-Object { $_.Extension.ToLowerInvariant() -in @(".html",".css",".js",".jsx",".ts",".tsx",".cs",".py") })
  }
  $AssertsHighestPriority = $GroundedResponse -match '(?i)highest[ -]priority'
  $NamesVerifiedPriorityGap = $GroundedResponse -match '(?i)(workbench|user interface|UI implementation|ecosystem classification|cloud credentials)'
  if($AssertsHighestPriority -and -not $NamesVerifiedPriorityGap -and $WorkbenchImplementationFiles.Count -eq 0){
    [void]$Corrections.Add("The priority recommendation was not grounded in the verified gap list. The clearest implementation gap is the nontechnical local workbench: workbench/contracts/PIE_WORKBENCH_CONTRACTS.v1.json exists, but workbench contains no UI implementation files.")
  }

  $InvalidReferences = New-Object System.Collections.Generic.List[string]
  foreach($Match in [regex]::Matches($GroundedResponse,'`([^`\r\n]+\.(?:ps1|md|json|txt))`','IgnoreCase')){
    $Reference = [string]$Match.Groups[1].Value
    if([System.IO.Path]::IsPathRooted($Reference)){
      if($Reference.StartsWith($ProjectRepo,[System.StringComparison]::OrdinalIgnoreCase) -and -not (Test-Path -LiteralPath $Reference)){
        [void]$InvalidReferences.Add($Reference)
      }
    }
    elseif($Reference.Contains("\") -or $Reference.Contains("/")){
      $Candidate = Join-Path $ProjectRepo $Reference
      if(-not (Test-Path -LiteralPath $Candidate)){ [void]$InvalidReferences.Add($Reference) }
    }
  }
  foreach($Reference in @($InvalidReferences.ToArray() | Sort-Object -Unique)){
    [void]$Corrections.Add("The referenced repository path does not exist: " + $Reference + ".")
  }

  if($Corrections.Count -gt 0){
    $GroundedResponse = $GroundedResponse.TrimEnd() + "`n`n### PIE Grounding Corrections`n`n"
    foreach($Correction in $Corrections){ $GroundedResponse += "- " + $Correction + "`n" }
    $GroundedResponse = $GroundedResponse.TrimEnd()
  }

  return [pscustomobject]@{
    response = $GroundedResponse
    correction_count = $Corrections.Count
    corrections = $Corrections.ToArray()
  }
}
