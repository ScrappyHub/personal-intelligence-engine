# Lighting up the engine positive checks

The negative + binding checks for all three backends already pass with no services running
(`_RUN_pie_engine_verify_all_v1.ps1` → GREEN with the three engines INCONCLUSIVE). To turn each
`INCONCLUSIVE` into a real green (actual generation sealed + ledgered), give that backend a live
model. Each is independent.

## Ollama

Ollama tags contain `:` (illegal in a Windows folder name), so seal the pulled model into a
filesystem-safe id; `pie_run_v1` maps it back to the real tag via the manifest's `ollama_model`.

```powershell
.\pie.ps1 runtime start
ollama pull qwen2.5-coder:1.5b
.\scripts\pie_seal_ollama_model_v1.ps1 -RepoRoot . -Model qwen2.5-coder:1.5b
#   -> registry\models\qwen2.5-coder_1.5b\model_manifest.v1.json (ollama_model = the real tag)
.\scripts\_RUN_pie_engine_verify_all_v1.ps1 -RepoRoot . -OllamaModel qwen2.5-coder_1.5b
```

## llama.cpp

The llama.cpp server serves whatever model it was launched with and ignores the model name in
the request, so the sealed id only satisfies the binding. A ready-made sealed fixture is
included: `pie-llamacpp-fixture`.

```powershell
# start a llama.cpp server on 127.0.0.1:8080 with any instruct model, e.g.:
#   .\llama-server.exe -m <model>.gguf -c 4096 --port 8080
.\scripts\_RUN_pie_engine_verify_all_v1.ps1 -RepoRoot . -LlamaCppModel pie-llamacpp-fixture
# custom port/url:  $env:PIE_LLAMACPP_URL = "http://127.0.0.1:8080/completion"
```

## ONNX

The sealed fixture `pie-onnx-fixture` is already registered. Drop a real onnxruntime-genai export
(with `genai_config.json`, the ONNX graph, and tokenizer files) into its `onnx/` dir, then run.

```powershell
pip install onnxruntime-genai            # or onnxruntime-genai-directml / -cuda
# copy a model export into: registry\models\pie-onnx-fixture\onnx\
.\scripts\_RUN_pie_engine_verify_all_v1.ps1 -RepoRoot . -OnnxModelDir registry\models\pie-onnx-fixture\onnx
```

## All at once

```powershell
.\scripts\_RUN_pie_engine_verify_all_v1.ps1 -RepoRoot . -IncludeTier0 `
  -OllamaModel qwen2.5-coder_1.5b -LlamaCppModel pie-llamacpp-fixture `
  -OnnxModelDir registry\models\pie-onnx-fixture\onnx
```

Green when every executed check passes; each backend flips from INCONCLUSIVE to a real
`SELFTEST_PIE_ENGINE_*_V1_GREEN` once its positive generation is sealed and ledgered. Receipt:
`runs\engine_verify\latest.json`.
