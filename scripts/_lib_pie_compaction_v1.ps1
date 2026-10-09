Set-StrictMode -Version Latest

# Deterministic conversation compaction with pinned-fact retention (release-blocker B6 foundation).
# When accumulated turns exceed a character budget, keep ALL pinned facts plus the most recent turns
# that fit, and replace the dropped older turns with a single deterministic marker. No LLM
# summarization is used, so the same input always yields the same output. Nothing is dropped
# silently: the result lists exactly which turn hashes were removed. Integration into the live send
# path is a follow-up; this is the reusable, verifiable core.

function PIE_CompactContext {
  param(
    [Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$Turns,   # ordered oldest->newest; each has .turn_sha256 .message .response
    [Parameter(Mandatory=$true)][int]$MaxChars,                             # budget for the rendered turn block
    [Parameter(Mandatory=$false)][string[]]$PinnedFacts = @()
  )

  $RenderTurn = { param($t) ("USER: " + [string]$t.message + "`nPIE: " + [string]$t.response + "`n") }

  $PinnedBlock = ""
  if($PinnedFacts.Count -gt 0){
    $PinnedBlock = "PINNED FACTS:`n" + (($PinnedFacts | ForEach-Object { "- " + $_ }) -join "`n") + "`n"
  }

  $Budget = $MaxChars - $PinnedBlock.Length
  if($Budget -lt 0){ $Budget = 0 }

  # Greedily keep the most recent turns that fit under the remaining budget (pinned facts always win).
  $Kept = New-Object System.Collections.Generic.List[object]
  $Used = 0
  for($i = $Turns.Count - 1; $i -ge 0; $i--){
    $Txt = & $RenderTurn $Turns[$i]
    if(($Used + $Txt.Length) -gt $Budget){ break }
    $Kept.Insert(0, $Turns[$i]); $Used += $Txt.Length
  }

  $DroppedCount = $Turns.Count - $Kept.Count
  $Dropped = @()
  if($DroppedCount -gt 0){ for($j=0; $j -lt $DroppedCount; $j++){ $Dropped += [string]$Turns[$j].turn_sha256 } }

  $Marker = ""
  if($DroppedCount -gt 0){ $Marker = "[" + $DroppedCount + " earlier turn(s) compacted; pinned facts retained]`n" }

  $KeptText = (@($Kept | ForEach-Object { & $RenderTurn $_ }) -join "")
  $Rendered = $PinnedBlock + $Marker + $KeptText

  return [pscustomobject]@{
    rendered            = $Rendered
    kept_count          = $Kept.Count
    dropped_count       = $DroppedCount
    dropped_turn_sha256 = $Dropped
    pinned_count        = $PinnedFacts.Count
    chars               = $Rendered.Length
  }
}
