Set-StrictMode -Version Latest

function PIE_MemorySha256Text {
  param([Parameter(Mandatory=$true)][AllowEmptyString()][string]$Text)
  $Bytes = [System.Text.Encoding]::UTF8.GetBytes($Text.Replace("`r`n","`n").Replace("`r","`n"))
  $Sha = [System.Security.Cryptography.SHA256]::Create()
  try { $Hash = $Sha.ComputeHash($Bytes) } finally { $Sha.Dispose() }
  return (($Hash | ForEach-Object { $_.ToString("x2") }) -join "")
}

function PIE_MemoryId {
  param(
    [string]$Lane,
    [string]$Project,
    [string]$ProjectRepo,
    [string]$Text
  )

  $Canonical = @($Lane,$Project,$ProjectRepo,$Text) | ForEach-Object {
    ([string]$_).Replace("`r`n","`n").Replace("`r","`n").Trim()
  }
  $Bytes = [System.Text.Encoding]::UTF8.GetBytes(($Canonical -join "`n"))
  $Sha = [System.Security.Cryptography.SHA256]::Create()
  try { $Hash = $Sha.ComputeHash($Bytes) } finally { $Sha.Dispose() }
  return "mem_" + (($Hash | ForEach-Object { $_.ToString("x2") }) -join "")
}

function PIE_MemoryPolicy {
  param([string]$RepoRoot,[string]$PolicyPath = "")

  $Path = $PolicyPath
  if([string]::IsNullOrWhiteSpace($Path)){ $Path = Join-Path $RepoRoot "memory\policy.json" }
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ throw ("PIE_MEMORY_POLICY_MISSING: " + $Path) }
  try { $Policy = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }
  catch { throw ("PIE_MEMORY_POLICY_INVALID: " + $Path + " :: " + $_.Exception.Message) }
  if([string]$Policy.schema -ne "pie.memory.policy.v1"){ throw ("PIE_MEMORY_POLICY_SCHEMA_BAD: " + $Path) }
  if([string]$Policy.mode -notin @("ask","auto_accept","manual_only","off")){ throw ("PIE_MEMORY_POLICY_MODE_INVALID: " + [string]$Policy.mode) }
  foreach($Name in @("repo_memory_enabled","project_memory_enabled","coding_memory_enabled")){
    $Property = $Policy.PSObject.Properties[$Name]
    if($null -eq $Property -or $Property.Value -isnot [bool]){ throw ("PIE_MEMORY_POLICY_BOOLEAN_INVALID: " + $Name) }
  }
  return $Policy
}

function PIE_MemoryProperty {
  param([object]$Object,[string]$Name)
  $Property = $Object.PSObject.Properties[$Name]
  if($null -eq $Property){ return "" }
  return [string]$Property.Value
}

function PIE_NormalizeMemoryRepo {
  param([string]$Path)
  if([string]::IsNullOrWhiteSpace($Path)){ return "" }
  try { return [System.IO.Path]::GetFullPath($Path).TrimEnd('\','/') }
  catch { throw ("PIE_MEMORY_PROJECT_REPO_INVALID: " + $Path) }
}

function PIE_AcquireMemoryLock {
  param([Parameter(Mandatory=$true)][string]$MemoryRoot)
  if(-not (Test-Path -LiteralPath $MemoryRoot -PathType Container)){ New-Item -ItemType Directory -Force -Path $MemoryRoot | Out-Null }
  try {
    return [System.IO.File]::Open((Join-Path $MemoryRoot ".memory.lock"),[System.IO.FileMode]::OpenOrCreate,[System.IO.FileAccess]::ReadWrite,[System.IO.FileShare]::None)
  }
  catch { throw "PIE_MEMORY_BUSY" }
}

function PIE_MemoryRecords {
  param(
    [string]$RepoRoot,
    [string]$MemoryRoot = "",
    [string]$Project = "",
    [string]$ProjectRepo = "",
    [string]$ProjectIdentityHash = "",
    [switch]$IncludeAllProjects,
    [string]$Query = "",
    [string]$Lane = "all",
    [int]$Limit = 25
  )

  if([string]::IsNullOrWhiteSpace($MemoryRoot)){ $MemoryRoot = Join-Path $RepoRoot "memory" }
  $ProjectRepo = PIE_NormalizeMemoryRepo -Path $ProjectRepo
  if($Limit -lt 1 -or $Limit -gt 200){ throw "PIE_MEMORY_LIMIT_INVALID" }
  if($Lane -notin @("all","active","coding","project")){ throw ("PIE_MEMORY_UNKNOWN_LANE: " + $Lane) }

  $Files = New-Object System.Collections.Generic.List[object]
  foreach($Pair in @(
    @{ lane="active"; path=(Join-Path $MemoryRoot "active\memory.ndjson") },
    @{ lane="coding"; path=(Join-Path $MemoryRoot "coding\memory.ndjson") }
  )){
    if($Lane -in @("all",$Pair.lane)){ [void]$Files.Add($Pair) }
  }

  if($Lane -in @("all","project")){
    $ProjectsRoot = Join-Path $MemoryRoot "projects"
    if(Test-Path -LiteralPath $ProjectsRoot -PathType Container){
      foreach($File in @(Get-ChildItem -LiteralPath $ProjectsRoot -Recurse -File -Filter "memory.ndjson" | Sort-Object FullName)){
        [void]$Files.Add(@{ lane="project"; path=$File.FullName })
      }
    }
  }

  $Records = New-Object System.Collections.Generic.List[object]
  $Tombstones = @{}

  foreach($FileInfo in $Files){
    $Path = [string]$FileInfo.path
    if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ continue }
    $LineNumber = 0
    foreach($Line in @(Get-Content -LiteralPath $Path)){
      $LineNumber++
      if([string]::IsNullOrWhiteSpace($Line)){ continue }
      try { $Obj = $Line | ConvertFrom-Json }
      catch { throw ("PIE_MEMORY_NDJSON_INVALID: " + $Path + ":" + $LineNumber + " :: " + $_.Exception.Message) }

      $Schema = PIE_MemoryProperty -Object $Obj -Name "schema"
      if($Schema -eq "pie.memory.tombstone.v1"){
        $Target = PIE_MemoryProperty -Object $Obj -Name "target_memory_id"
        if([string]::IsNullOrWhiteSpace($Target)){ throw ("PIE_MEMORY_TOMBSTONE_TARGET_MISSING: " + $Path + ":" + $LineNumber) }
        $Tombstones[($Path + "|" + $Target)] = $LineNumber
        continue
      }
      if(-not [string]::IsNullOrWhiteSpace($Schema) -and $Schema -ne "pie.memory.record.v1"){
        throw ("PIE_MEMORY_SCHEMA_BAD: " + $Path + ":" + $LineNumber)
      }

      $Text = PIE_MemoryProperty -Object $Obj -Name "text"
      if([string]::IsNullOrWhiteSpace($Text)){ throw ("PIE_MEMORY_TEXT_MISSING: " + $Path + ":" + $LineNumber) }
      $RecordLane = PIE_MemoryProperty -Object $Obj -Name "lane"
      if([string]::IsNullOrWhiteSpace($RecordLane)){ $RecordLane = PIE_MemoryProperty -Object $Obj -Name "scope" }
      if([string]::IsNullOrWhiteSpace($RecordLane)){ $RecordLane = [string]$FileInfo.lane }
      if($RecordLane -notin @("active","coding","project") -or $RecordLane -ne [string]$FileInfo.lane){
        throw ("PIE_MEMORY_LANE_MISMATCH: " + $Path + ":" + $LineNumber)
      }
      $RecordProject = PIE_MemoryProperty -Object $Obj -Name "project"
      $RecordProjectRepo = PIE_NormalizeMemoryRepo -Path (PIE_MemoryProperty -Object $Obj -Name "project_repo")
      $RecordProjectIdentity = PIE_MemoryProperty -Object $Obj -Name "project_identity_sha256"
      if($RecordLane -eq "active" -and -not [string]::IsNullOrWhiteSpace($ProjectRepo)){ continue }
      if($RecordLane -eq "project"){
        if([string]::IsNullOrWhiteSpace($RecordProject) -or [string]::IsNullOrWhiteSpace($RecordProjectRepo)){
          throw ("PIE_MEMORY_PROJECT_BINDING_MISSING: " + $Path + ":" + $LineNumber)
        }
        if($IncludeAllProjects){
          if(-not [string]::IsNullOrWhiteSpace($Project) -and $RecordProject -ine $Project){ continue }
        }
        else {
          if([string]::IsNullOrWhiteSpace($ProjectRepo)){ continue }
          if($RecordProject -ine $Project -or $RecordProjectRepo -ine $ProjectRepo){ continue }
          if(-not [string]::IsNullOrWhiteSpace($RecordProjectIdentity) -and $RecordProjectIdentity -ne $ProjectIdentityHash){
            throw ("PIE_MEMORY_PROJECT_IDENTITY_DRIFT: " + $Path + ":" + $LineNumber)
          }
        }
      }
      $MemoryId = PIE_MemoryProperty -Object $Obj -Name "memory_id"
      $ExpectedMemoryId = PIE_MemoryId -Lane $RecordLane -Project $RecordProject -ProjectRepo $RecordProjectRepo -Text $Text
      if([string]::IsNullOrWhiteSpace($MemoryId)){ $MemoryId = $ExpectedMemoryId }
      elseif($MemoryId -ne $ExpectedMemoryId){ throw ("PIE_MEMORY_ID_MISMATCH: " + $Path + ":" + $LineNumber) }
      $Created = PIE_MemoryProperty -Object $Obj -Name "created_utc"
      if([string]::IsNullOrWhiteSpace($Created)){ $Created = PIE_MemoryProperty -Object $Obj -Name "ts" }

      [void]$Records.Add([pscustomobject]@{
        memory_id = $MemoryId
        lane = $RecordLane
        project = $RecordProject
        project_repo = $RecordProjectRepo
        project_identity_sha256 = $RecordProjectIdentity
        text = $Text
        created_utc = $Created
        source_path = $Path
        source_line = $LineNumber
        score = 0
      })
    }
  }

  $Tokens = @($Query.ToLowerInvariant() -split '[^a-z0-9._-]+' | Where-Object { $_.Length -ge 3 } | Sort-Object -Unique)
  $Visible = New-Object System.Collections.Generic.List[object]
  foreach($Record in $Records){
    $TombstoneKey = $Record.source_path + "|" + $Record.memory_id
    if($Tombstones.ContainsKey($TombstoneKey) -and [int]$Tombstones[$TombstoneKey] -gt [int]$Record.source_line){ continue }
    $Haystack = ($Record.text + " " + $Record.project + " " + $Record.lane).ToLowerInvariant()
    $Score = 0
    foreach($Token in $Tokens){ if($Haystack.Contains($Token)){ $Score++ } }
    $Record.score = $Score
    [void]$Visible.Add($Record)
  }

  return @($Visible.ToArray() | Sort-Object @{Expression="score";Descending=$true}, @{Expression="created_utc";Descending=$true}, @{Expression="memory_id";Descending=$false} | Select-Object -First $Limit)
}

function PIE_MemoryAppendReceipt {
  param([string]$RepoRoot,[string]$Event,[string]$MemoryId,[string]$Lane,[string]$Project,[string]$ReceiptPath = "")

  $Path = $ReceiptPath
  if([string]::IsNullOrWhiteSpace($Path)){ $Path = Join-Path $RepoRoot ".pie\receipts\memory.ndjson" }
  $Dir = Split-Path -Parent $Path
  if(-not (Test-Path -LiteralPath $Dir -PathType Container)){ New-Item -ItemType Directory -Force -Path $Dir | Out-Null }
  $Obj = [ordered]@{
    schema = "pie.memory.receipt.v1"
    event = $Event
    memory_id = $MemoryId
    lane = $Lane
    project = $Project
    created_utc = [DateTime]::UtcNow.ToString("o")
  }
  [System.IO.File]::AppendAllText($Path,(($Obj | ConvertTo-Json -Compress) + "`n"),(New-Object System.Text.UTF8Encoding($false)))
}
