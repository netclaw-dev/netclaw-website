---
title: "vLLM Quirks"
description: "Known sharp edges when running netclaw against a vLLM backend — modality detection, tool-call streaming, and timings."
---

vLLM is a solid self-hosted backend — [PagedAttention](https://docs.vllm.ai/en/latest/design/kernel/paged_attention.html) for efficient GPU memory use, first-class AMD ROCm support, and the most widely deployed OpenAI-compatible server in production. Netclaw works with vLLM via the `openai-compatible` provider type.

But vLLM's `/v1/models` endpoint is minimal compared to llama.cpp's `/props`. Auto-detection works on llama.cpp but needs manual config on vLLM for a few things.

## Vision models report as text-only

**Symptom:** `netclaw status` shows `input: Text` even though your model supports images. Image attachments in Slack/Discord are captured but not sent to the model:

```
[attachment] name="image.png" mime="image/png" size=519623 path="inbox/image.png" inlined="false"
  note="current model has no image modality; file is on disk but not viewable this turn"
```

**Why:** vLLM's `/v1/models` response has no modality information. Netclaw falls back to a HuggingFace lookup, but that only works when the served name matches the HuggingFace id (e.g., `Qwen/Qwen3.6-VL-30B-FP8`). Friendly aliases like `qwen36-ultimate` fail silently and modality defaults to text-only.

This doesn't affect llama.cpp, where `llama-server` exposes `/props` with an explicit `modalities.vision` flag.

**Fix:** Declare modalities explicitly in `~/.netclaw/config/netclaw.json`:

```json
"Main": {
  "Provider": "my-vllm-provider",
  "ModelId": "qwen36-ultimate",
  "InputModalities": "Text, Image",
  "OutputModalities": "Text"
}
```

Use comma-separated strings, not JSON arrays — .NET binds `[Flags]` enums that way. `["Text", "Image"]` silently fails and your override gets ignored.

## Tool-call streaming with the Hermes parser

**Symptom:** Raw `<tool_call>…</tool_call>` XML appears in chat output instead of structured tool calls. Looks identical to the [llama.cpp `--jinja` problem](/troubleshooting/llama-cpp/#chat-template-mismatch), but you're on vLLM.

**Why:** vLLM's tool-call parsing is plugin-based (`--tool-call-parser <name>`). The `hermes` parser — vLLM's general recommendation for Qwen3 — has a [known streaming bug](https://github.com/vllm-project/vllm/issues/31871) (open since v0.15.1): when `stream: true`, vLLM returns raw XML inside `delta.content` with `finish_reason: "stop"` instead of the structured `tool_calls` delta array the OpenAI spec requires. Non-streaming requests work fine.

Netclaw always streams (`stream: true`), so this bug hits every tool-calling request through the `hermes` parser.

**Fix:** Netclaw's `TextToolCallParser` detects and extracts `<tool_call>` XML from text content. It was built for llama.cpp but handles this vLLM quirk too. If you're seeing XML in chat, make sure you're on netclaw v0.9+ (check with `netclaw --version`).

If you're on an older version, the workaround is to test whether `--tool-call-parser qwen3_coder` (vLLM 0.10+) handles streaming correctly for your model. Results vary by model family.

## No per-request timings

**Symptom:** Session-level cache hit rates and prompt latency metrics show as zero or null in `netclaw stats` and OpenTelemetry exports.

**Why:** llama.cpp returns a `timings` object on every `/v1/chat/completions` response with `cached_tokens`, `prompt_ms`, and `predicted_per_second`. Netclaw uses these to track cache hit rates and latency. vLLM doesn't include this object. It's a llama.cpp extension, not part of the OpenAI spec.

vLLM does expose `usage.prompt_tokens_details.cached_tokens` for its automatic prefix cache, and aggregate metrics via its `/metrics` Prometheus endpoint. But per-request prompt latency has to come from client-side wall-clock measurements.

**Impact:** This is an observability gap, not a functionality gap. Tool calls, memory, sessions — everything works. You just lose per-request cache and latency telemetry.

**Workaround:** None needed if you don't use the affected metrics. If you do, llama.cpp provides richer per-request telemetry today.

## Context window detection

vLLM exposes `max_model_len` in its `/v1/models` response. Netclaw reads this correctly — context window detection works out of the box on vLLM.

This is worth calling out because it *used* to be a gap. If you're on netclaw < v0.10, upgrade (`netclaw --version` to check).

## Recommended vLLM flags for netclaw

```bash
vllm serve <model> \
  --served-model-name <name> \
  --tool-call-parser hermes \
  --max-model-len <N> \
  --port 8000
```

For vision models, also declare modalities in netclaw config as shown above — don't rely on auto-detection when using a friendly served name.

## See also

- [Self-Hosted Providers](/configuration/self-hosted-providers/) — vLLM and llama.cpp setup
- [llama.cpp Troubleshooting](/troubleshooting/llama-cpp/) — `--jinja`, quantization, and specdec issues
- [Channel Troubleshooting](/channels/troubleshooting/) — Slack and Discord connectivity issues
- [`netclaw status`](/cli/status/) — check detected modalities and context window

## Resources

- [vLLM OpenAI-compatible server docs](https://docs.vllm.ai/en/latest/serving/openai_compatible_server.html) — full flag reference
- [vLLM tool-call-parser options](https://docs.vllm.ai/en/latest/serving/openai_compatible_server.html#tool-calling) — parser selection for different model families
- [vLLM streaming tool-call bug (hermes parser)](https://github.com/vllm-project/vllm/issues/31871) — open issue tracking XML leakage in streaming mode
