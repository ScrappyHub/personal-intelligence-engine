Set-StrictMode -Version Latest

# PIE schema migration framework (release-blocker B1 foundation).
# Enforces the "no silent drift / no silent downgrade" invariant (PIE LAW 4, SPEC invariant 7):
# a reader MUST fail closed on an unknown schema or a version newer than this build knows.
# Actual per-schema migrations are registered in $script:PIE_MIGRATIONS as they are introduced;
# today every persistent schema is at its current version, so the map is intentionally empty.

function PIE_LoadSchemaRegistry([string]$RepoRoot){
  $p = Join-Path $RepoRoot "schemas\PIE_SCHEMA_REGISTRY.v1.json"
  if(-not (Test-Path -LiteralPath $p -PathType Leaf)){ throw ("PIE_SCHEMA_REGISTRY_MISSING: " + $p) }
  $enc = New-Object System.Text.UTF8Encoding($false)
  return ([System.IO.File]::ReadAllText($p,$enc) | ConvertFrom-Json)
}

# Parse a schema id like "pie.memory.record.v1" or "run_record.v1" into base + integer version.
function PIE_ParseSchemaId([string]$SchemaId){
  if($SchemaId -match '^(.*)\.v(\d+)$'){
    return [pscustomobject]@{ base = $Matches[1]; version = [int]$Matches[2]; id = $SchemaId }
  }
  return [pscustomobject]@{ base = $SchemaId; version = 1; id = $SchemaId }
}

# The current known version for a schema base, from the registry (keyed by full id).
function PIE_CurrentSchemaVersion($Registry,[string]$SchemaId){
  $parsed = PIE_ParseSchemaId $SchemaId
  foreach($s in @($Registry.schemas)){
    $rp = PIE_ParseSchemaId ([string]$s.id)
    if($rp.base -ieq $parsed.base){ return [int]$s.current }
  }
  return $null
}

# Registered migrations: array of @{ base=<string>; from=<int>; to=<int>; fn=<scriptblock($obj)> }.
$script:PIE_MIGRATIONS = @()

function PIE_RegisterMigration([string]$Base,[int]$From,[int]$To,[scriptblock]$Fn){
  $script:PIE_MIGRATIONS += ,([pscustomobject]@{ base=$Base; from=$From; to=$To; fn=$Fn })
}

# Fail-closed guard. Returns the current known version on success; throws on unknown/newer schema.
function PIE_AssertKnownSchema($Registry,[string]$SchemaId){
  if([string]::IsNullOrWhiteSpace($SchemaId)){ throw "PIE_SCHEMA_MISSING_FIELD" }
  $current = PIE_CurrentSchemaVersion $Registry $SchemaId
  if($null -eq $current){ throw ("PIE_SCHEMA_UNKNOWN: " + $SchemaId) }
  $parsed = PIE_ParseSchemaId $SchemaId
  if($parsed.version -gt $current){ throw ("PIE_SCHEMA_VERSION_TOO_NEW: " + $SchemaId + " (build knows v" + $current + "); refusing to downgrade") }
  return $current
}

# Idempotently migrate a parsed object (must carry a .schema) up to current. No-op when already current.
function PIE_MigrateObject($Registry,$Obj){
  if($null -eq $Obj -or -not ($Obj.PSObject.Properties.Name -contains 'schema')){ throw "PIE_SCHEMA_MISSING_FIELD" }
  $schemaId = [string]$Obj.schema
  [void](PIE_AssertKnownSchema $Registry $schemaId)
  $parsed  = PIE_ParseSchemaId $schemaId
  $current = PIE_CurrentSchemaVersion $Registry $schemaId
  $v = $parsed.version
  while($v -lt $current){
    $step = @($script:PIE_MIGRATIONS | Where-Object { $_.base -ieq $parsed.base -and $_.from -eq $v }) | Select-Object -First 1
    if($null -eq $step){ throw ("PIE_SCHEMA_NO_MIGRATION_PATH: " + $parsed.base + " v" + $v + " -> v" + $current) }
    $Obj = & $step.fn $Obj
    $v = $step.to
    $Obj.schema = ($parsed.base + ".v" + $v)
  }
  return $Obj
}
