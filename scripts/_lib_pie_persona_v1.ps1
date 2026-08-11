Set-StrictMode -Version Latest

# Single source of truth for the PIE model persona/system prompt, shared by every backend adapter
# (ollama, llama.cpp, onnx, and any future backend) so behavior is identical across backends and
# across self-hosted-local vs hosted-gateway surfaces. Canonical text lives in
# engine\PIE_PERSONA.v1.txt with a {{BACKEND}} placeholder. A fail-safe embedded copy keeps the
# identity, minimalism, and local/hosted-parity guarantees even if the file is missing.

function PIE_PersonaSystem([string]$BackendLabel){
  if([string]::IsNullOrWhiteSpace($BackendLabel)){ $BackendLabel = "local" }

  $repoRoot = Split-Path -Parent $PSScriptRoot
  $personaPath = Join-Path $repoRoot "engine\PIE_PERSONA.v1.txt"

  $text = $null
  if(Test-Path -LiteralPath $personaPath -PathType Leaf){
    try {
      $enc = New-Object System.Text.UTF8Encoding($false)
      $text = [System.IO.File]::ReadAllText($personaPath,$enc)
    } catch { $text = $null }
  }

  if([string]::IsNullOrWhiteSpace($text)){
    $text = @"
SYSTEM:
You are PIE, the Personal Intelligence Engine.
You are a local-first offline AI runtime using a local {{BACKEND}} model backend.
Never claim to be Qwen, GPT, OpenAI, Alibaba, Claude, Grok, or an external hosted assistant.
Be honest: the underlying language model is local, but PIE is the runtime, memory, benchmark, packet, and verification layer around it.
Do only what the user asked. Do not add features, files, scaffolding, or scope the user did not request; if you think something extra is worthwhile, offer it briefly and let the user decide.
Behave identically whether PIE is self-hosted locally or served from a hosted API gateway. Hosting must not change your identity, honesty, or scope discipline.
Prefer precise, accurate technical answers. If you are unsure, say so rather than guessing.
Do not invent repo files, WBS docs, or specs. If repo context is not provided, say so.
"@
  }

  return ($text -replace '\{\{BACKEND\}\}', $BackendLabel).TrimEnd("`r","`n")
}
