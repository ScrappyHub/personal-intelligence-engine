param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$Model,
  [Parameter(Mandatory=$false)][string]$Message = "",
  [Parameter(Mandatory=$false)][string]$MessagePath = "",
  [Parameter(Mandatory=$false)][int]$MaxNewTokens = 512
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# onnxruntime-genai backend (subprocess shape). Output-bytes only; the recording law and the
# sealed-model binding are owned by scripts\pie_run_v1.ps1. Contract:
# engine\adapters\onnx\PIE_ENGINE_ADAPTER.v1.json

. (Join-Path $RepoRoot 'scripts\_lib_pie_v1.ps1')
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

if(-not [string]::IsNullOrWhiteSpace($MessagePath)){
  if(-not (Test-Path -LiteralPath $MessagePath -PathType Leaf)){
    throw ("PIE_ONNX_MESSAGE_PATH_NOT_FOUND: " + $MessagePath)
  }
  $Message = Get-Content -LiteralPath $MessagePath -Raw
}
if([string]::IsNullOrWhiteSpace($Message)){ throw "PIE_ONNX_MESSAGE_REQUIRED" }

. (Join-Path $PSScriptRoot "_lib_pie_persona_v1.ps1")
$System = PIE_PersonaSystem "ONNX"
$Prompt = $System + "`n`n" + $Message.Replace("\n","`n")

# --- Resolve the ONNX model directory (fail-closed, deterministic order). ---
$ModelDir = ""
if(-not [string]::IsNullOrWhiteSpace($env:PIE_ONNX_MODEL_DIR)){
  $ModelDir = $env:PIE_ONNX_MODEL_DIR
}
else {
  $manifestPath = PIE_ModelManifestPath $RepoRoot $Model
  if(Test-Path -LiteralPath $manifestPath -PathType Leaf){
    $mj = (NL_ReadUtf8 $manifestPath) | ConvertFrom-Json
    if($mj.PSObject.Properties.Name -contains 'onnx_model_dir' -and -not [string]::IsNullOrWhiteSpace([string]$mj.onnx_model_dir)){
      $candidate = [string]$mj.onnx_model_dir
      if(-not [System.IO.Path]::IsPathRooted($candidate)){ $candidate = Join-Path $RepoRoot $candidate }
      $ModelDir = $candidate
    }
  }
  if([string]::IsNullOrWhiteSpace($ModelDir)){
    $c1 = Join-Path (PIE_RegistryRoot $RepoRoot) (Join-Path $Model 'onnx')
    $c2 = Join-Path $RepoRoot (Join-Path 'models' $Model)
    if(Test-Path -LiteralPath $c1 -PathType Container){ $ModelDir = $c1 }
    elseif(Test-Path -LiteralPath $c2 -PathType Container){ $ModelDir = $c2 }
  }
}
if([string]::IsNullOrWhiteSpace($ModelDir) -or -not (Test-Path -LiteralPath $ModelDir -PathType Container)){
  throw ("PIE_ENGINE_ONNX_MODEL_DIR_UNRESOLVED: " + $Model)
}

# --- Locate Python. ---
$python = $env:PIE_PYTHON
if([string]::IsNullOrWhiteSpace($python)){
  $cmd = Get-Command python -ErrorAction SilentlyContinue
  if($null -eq $cmd){ $cmd = Get-Command python3 -ErrorAction SilentlyContinue }
  if($null -eq $cmd){ throw "PIE_ENGINE_ONNX_PYTHON_MISSING" }
  $python = $cmd.Source
}

$helper = Join-Path $RepoRoot 'scripts\pie_backend_onnx_generate_v1.py'
if(-not (Test-Path -LiteralPath $helper -PathType Leaf)){ throw ("PIE_ENGINE_BACKEND_UNAVAILABLE: " + $helper) }

# Pass the prompt via a temp file to avoid argument-length and quoting issues.
$tmp = Join-Path $RepoRoot ('runs\onnx_prompt_' + ([guid]::NewGuid().ToString('n')) + '.txt')
NL_WriteUtf8NoBomLf $tmp $Prompt
try {
  $out = & $python $helper --model-dir $ModelDir --prompt-file $tmp --max-new-tokens $MaxNewTokens 2>&1 | Out-String
  $code = $LASTEXITCODE
}
finally {
  Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
}

if($code -ne 0){ throw ("PIE_ENGINE_ONNX_GENERATION_FAILED: exit " + $code + " :: " + $out) }
$out = $out.TrimEnd("`r","`n")
if([string]::IsNullOrWhiteSpace($out)){ throw "PIE_ENGINE_ONNX_EMPTY" }

Write-Output $out
