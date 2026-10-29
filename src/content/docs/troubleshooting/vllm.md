---
title: "vLLM Quirks"
description: "Known sharp edges when running netclaw against a vLLM backend: modality detection, tool-call streaming, silent or endless thinking, and timings."
---

vLLM is a solid self-hosted backend. [PagedAttention](https://docs.vllm.ai/en/latest/design/kernel/paged_attention.html) makes efficient use of GPU memory, AMD ROCm support is first-class, and it's the most widely deployed OpenAI-compatible server in production. netclaw works with vLLM through the `openai-compatible` provider type.

But vLLM's `/v1/models` endpoint is minimal compared to llama.cpp's `/props`. Auto-detection works on llama.cpp and needs manual config on vLLM for a few things.

## Symptoms

| What you're seeing | Jump to |
|---|---|
| `netclaw status` shows `input: Text` for a vision model | [Vision models report as text-only](#vision-models-report-as-text-only) |
| Raw `<tool_call>` XML in chat | [Tool-call streaming with the Hermes parser](#tool-call-streaming-with-the-hermes-parser) |
| Tool calls are ignored, or the server returns an error about tool choice | [Tool calls don't happen](#tool-calls-dont-happen) |
| A turn goes quiet or ends with `I didn't manage to produce a reply` | [Silent or endless thinking](#silent-or-endless-thinking) |
| Cache hit rate and prompt latency read zero in `netclaw stats` | [No per-request timings](#no-per-request-timings) |
| Compaction every turn, or the wrong context size | [Context window detection](#context-window-detection) |

## Vision models report as text-only

**Symptom:** `netclaw status` shows `input: Text` even though your model supports images. Image attachments in Slack and Discord are captured but not sent to the model:

```
[attachment] name="image.png" mime="image/png" size=519623 path="inbox/image.png" inlined="false"
  note="current model has no image modality; file is on disk but not viewable this turn"
```

**Cause:** vLLM's `/v1/models` response has no modality information. netclaw falls back to a Hugging Face lookup, but that only works when the served name matches the Hugging Face ID (`Qwen/Qwen3.6-VL-30B-FP8`, say). Friendly aliases like `qwen36-ultimate` don't match, and modality defaults to text-only. The daemon log says so: `resolved to text-only input; no modality data came from the provider or capability oracles`.

This doesn't affect llama.cpp, where `llama-server` exposes `/props` with an explicit `modalities.vision` flag.

**Fix:** Declare modalities on the model definition. The CLI is the shortest way:

```bash
netclaw model set main my-vllm-provider qwen36-ultimate --input-modalities "Text, Image"
```

Or edit `~/.netclaw/config/netclaw.json`:

```json
{
  "Models": {
    "Definitions": {
      "qwen36": {
        "Provider": "my-vllm-provider",
        "ModelId": "qwen36-ultimate",
        "InputModalities": "Text, Image",
        "OutputModalities": "Text"
      }
    },
    "Roles": { "Main": "qwen36" }
  }
}
```

Use comma-separated strings, not JSON arrays. The config schema types the field as a string, so [`netclaw doctor`](/cli/doctor/) flags an array. `netclaw model set ... --clear-modalities` goes back to detection. Don't paste a bare `"Main": {...}` block next to `Definitions` and `Roles`: that mixes two config shapes. A running daemon ignores the edit and `netclaw status` reports `config on disk not applied`, and a restart stops at startup (see [Migrating model configuration](/guides/migrating-model-config/)).

## Tool-call streaming with the Hermes parser

**Symptom:** Raw `<tool_call>...</tool_call>` XML appears in chat instead of structured tool calls. It looks identical to the [llama.cpp `--jinja` problem](/troubleshooting/llama-cpp/#raw-tool-call-xml-in-chat), but you're on vLLM.

**Cause:** vLLM's tool-call parsing is plugin-based (`--tool-call-parser <name>`). The `hermes` parser, vLLM's general recommendation for Qwen3, had a [streaming bug](https://github.com/vllm-project/vllm/issues/31871) (since closed): with `stream: true`, vLLM returned the raw XML inside `delta.content` with `finish_reason: "stop"` instead of the structured `tool_calls` delta array the OpenAI spec requires. Non-streaming requests worked. netclaw always streams, so the bug hit every tool-calling request through that parser.

**Fix:** netclaw's `TextToolCallParser` detects and extracts `<tool_call>` XML from text content. It was built for llama.cpp and handles this vLLM quirk too, so a current netclaw copes. If you still see XML in chat, update vLLM first, then check that the parser matches your model family. vLLM's [tool-calling docs](https://docs.vllm.ai/en/latest/features/tool_calling/) list the parser names (`hermes` for Hermes-style models, `qwen3_xml` for Qwen3-Coder at the time of writing).

## Tool calls don't happen

**Symptom:** The model describes what it would do instead of calling tools, or vLLM returns an error about `tool_choice`.

**Cause:** vLLM only produces structured tool calls when it's started with auto tool choice and a parser.

**Fix:** Add both flags: `--enable-auto-tool-choice` and `--tool-call-parser <name>`.

## Silent or endless thinking

**Symptom:** A channel goes quiet for minutes, `netclaw chat` shows nothing, or the turn ends with `I didn't manage to produce a reply. Please try rephrasing or sending your request again.`

**Cause:** A reasoning model emitted thinking with no reply and no tool call. netclaw nudges it to answer and retries (up to 5 times before any tool work and 8 after), then gives up with that message. Thinking text isn't shown in channels by design. Slow prefill on a long context can look the same.

**Fix:** Turn thinking off or shorten it. To do it from netclaw, set `Providers:<name>:VendorOptions:ThinkingDialect` to `ChatTemplateKwargs` by hand and run `netclaw model set main <provider> <model> --thinking off`. Netclaw then sends `chat_template_kwargs: {enable_thinking: false}` with each request, and only `off` is on offer. Without a dialect an `openai-compatible` provider can't send a level. A reply that hits the output limit fails the turn with `The model reply was truncated`, and a call that streams only thinking ends the turn at three times `Session.NoProgressTimeoutSeconds`. To do it on the server instead, vLLM takes template arguments with `--default-chat-template-kwargs '{"enable_thinking": false}'` for Qwen3, and `--reasoning-parser <name>` separates thinking from the reply so it doesn't land in message text. If the server is just slow, raise `Session.PrefillTimeoutSeconds` and `Session.NoProgressTimeoutSeconds` ([Slow models and timeouts](/configuration/models/#slow-models-and-timeouts)). More background in the [llama.cpp page's thinking section](/troubleshooting/llama-cpp/#silent-slow-or-endless-thinking), since the netclaw side is the same.

## No per-request timings

**Symptom:** Session-level cache hit rates and prompt latency metrics show as zero or null in `netclaw stats` and OpenTelemetry exports.

**Cause:** llama.cpp returns a `timings` object on every `/v1/chat/completions` response with `cached_tokens`, `prompt_ms`, and `predicted_per_second`. netclaw uses these to track cache hit rates and latency. vLLM doesn't include the object. It's a llama.cpp extension, not part of the OpenAI spec.

vLLM does expose `usage.prompt_tokens_details.cached_tokens` for its automatic prefix cache, and aggregate metrics through its `/metrics` Prometheus endpoint. Per-request prompt latency has to come from client-side wall-clock measurements.

**Impact:** An observability gap, not a functionality gap. Tool calls, memory, and sessions all work. You just lose per-request cache and latency telemetry.

**Fix:** None needed if you don't use the affected metrics. If you do, llama.cpp provides richer per-request telemetry today.

## Context window detection

vLLM exposes `max_model_len` in its `/v1/models` response, and netclaw reads it, so context window detection works out of the box. It used to be a gap on old netclaw versions, so update if `netclaw status` shows 32,768 for a model served with a larger `--max-model-len`.

**Symptom:** `netclaw status` shows a different context than `--max-model-len`, or compaction fires every turn.

**Cause:** A `ContextWindow` override on the definition wins over detection. A value smaller than netclaw's own first-turn prompt (about 10,000 tokens with the default tools) makes compaction fire constantly, and one larger than `--max-model-len` makes vLLM reject the request.

**Fix:** `netclaw model set main my-vllm-provider <model> --clear-context-window` to hand it back to detection, or set it to match `--max-model-len`.

## Recommended vLLM flags for netclaw

```bash
vllm serve <model> \
  --served-model-name <name> \
  --enable-auto-tool-choice \
  --tool-call-parser hermes \
  --max-model-len <N> \
  --port 8000
```

For vision models, also declare modalities in netclaw config as shown above. Don't rely on auto-detection when using a friendly served name. Point netclaw at `http://<host>:8000`. A trailing `/v1` works too (see [Endpoint URL](/configuration/self-hosted-providers/#endpoint-url)).

## Related pages

- [Self-hosted providers](/configuration/self-hosted-providers/) - vLLM and llama.cpp setup
- [llama.cpp troubleshooting](/troubleshooting/llama-cpp/) - `--jinja`, quantization, speculative decoding, and thinking loops
- [Models](/configuration/models/) - context window, modalities, and timeouts
- [Channel troubleshooting](/channels/troubleshooting/) - Slack and Discord connectivity
- [`netclaw status`](/cli/status/) - check detected modalities and context window

## Resources

- [vLLM OpenAI-compatible server docs](https://docs.vllm.ai/en/latest/serving/openai_compatible_server.html) - the full flag reference
- [vLLM tool calling](https://docs.vllm.ai/en/latest/features/tool_calling/) - parser selection for different model families
- [vLLM streaming tool-call bug (hermes parser)](https://github.com/vllm-project/vllm/issues/31871) - the closed issue on XML leakage in streaming mode
