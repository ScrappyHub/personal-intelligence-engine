#!/usr/bin/env python3
"""PIE onnx engine backend — local, offline text generation via onnxruntime-genai.

Output-bytes only. The recording law (hashing, ledger, artifacts, sealed-model binding) is
owned by scripts\\pie_run_v1.ps1; this helper just turns (model_dir, prompt) into text on stdout.

Contract: engine/adapters/onnx/PIE_ENGINE_ADAPTER.v1.json
Invoked by: scripts\\pie_backend_onnx_cmd_v1.ps1

Exit codes:
  0  success (generated text on stdout)
  2  onnxruntime-genai not installed
  3  model directory missing/invalid
  4  empty generation
Error tokens are printed to stderr with a PIE_ENGINE_ONNX_ prefix.
"""
import argparse
import os
import sys


def _fail(code: int, token: str, detail: str = "") -> None:
    msg = token if not detail else f"{token}: {detail}"
    print(msg, file=sys.stderr)
    sys.exit(code)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--model-dir", required=True, help="Directory containing the ONNX model + genai_config.json")
    ap.add_argument("--prompt", help="Prompt text (use --prompt-file for long/complex prompts)")
    ap.add_argument("--prompt-file", help="Path to a UTF-8 file containing the prompt")
    ap.add_argument("--max-new-tokens", type=int, default=512)
    args = ap.parse_args()

    if args.prompt_file:
        try:
            with open(args.prompt_file, "r", encoding="utf-8") as fh:
                prompt = fh.read()
        except OSError as exc:
            _fail(3, "PIE_ENGINE_ONNX_PROMPT_FILE_NOT_FOUND", str(exc))
    elif args.prompt is not None:
        prompt = args.prompt
    else:
        _fail(3, "PIE_ENGINE_ONNX_PROMPT_REQUIRED")

    if not os.path.isdir(args.model_dir):
        _fail(3, "PIE_ENGINE_ONNX_MODEL_DIR_NOT_FOUND", args.model_dir)

    try:
        import onnxruntime_genai as og
    except Exception as exc:  # noqa: BLE001 - report any import failure fail-closed
        _fail(2, "PIE_ENGINE_ONNX_RUNTIME_MISSING", str(exc))

    try:
        model = og.Model(args.model_dir)
        tokenizer = og.Tokenizer(model)
        input_tokens = tokenizer.encode(prompt)

        params = og.GeneratorParams(model)
        # Greedy / deterministic-leaning decode (do_sample off, temperature 0).
        try:
            params.set_search_options(max_length=len(input_tokens) + args.max_new_tokens, do_sample=False, temperature=0.0)
        except TypeError:
            params.set_search_options(max_length=len(input_tokens) + args.max_new_tokens)

        generator = og.Generator(model, params)
        generator.append_tokens(input_tokens)

        out_ids = []
        while not generator.is_done():
            generator.generate_next_token()
            out_ids.append(generator.get_next_tokens()[0])

        text = tokenizer.decode(out_ids)
    except Exception as exc:  # noqa: BLE001
        _fail(3, "PIE_ENGINE_ONNX_GENERATION_FAILED", str(exc))

    if text is None or text.strip() == "":
        _fail(4, "PIE_ENGINE_ONNX_EMPTY")

    sys.stdout.write(text)


if __name__ == "__main__":
    main()
