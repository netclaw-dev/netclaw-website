---
title: "Troubleshooting llama.cpp Tool Calls"
description: "Fix XML markup leaking into chat, truncated responses, and repetition loops on self-hosted llama.cpp deployments."
---

This page covers llama.cpp (`llama-server`) specifically. If you're using Ollama or vLLM, these flags don't apply — those servers handle chat templates automatically.

Self-hosted netclaw on llama.cpp producing garbage? Raw `<tool_call>` XML in chat messages, `</think>` tags in replies, empty tool arguments, or responses that trail off into repetition loops — these all trace back to how the inference server parses the model's chat template.

Netclaw just assembles whatever streaming deltas it receives. If the server emits `<tool_call>` as literal text instead of structured tool-call deltas, that's what shows up in chat.

## Quick checklist

Try these first before diving into root causes:

1. **Add `--jinja`** to your llama-server launch arguments. If absent and you're on Qwen3 / DeepSeek-R1, that's almost certainly the problem.
2. **Check the model card** on Hugging Face for recommended flags. If it lists `--jinja` or a custom chat template file, use it.
3. **Check your quantization.** Switch to Q5_K_XL or Q6_K_XL if you're on Q4 or lower.
4. **Disable speculative decoding** if you're seeing truncation or repetition loops. Remove `--spec-default`.
5. **Check the llama.cpp build** for known regressions. Tool-call parser fixes land frequently.
6. **Verify the GGUF's embedded template** isn't broken. Community-corrected templates exist for several Qwen3 quants.

If that didn't fix it, read on for root cause details.

## Symptoms

| What you're seeing | Likely cause |
|---|---|
| `<tool_call>`, `<function=…>`, `<parameter=…>` tags as plain text | [Chat template mismatch](#chat-template-mismatch) |
| Stray `</think>` or `<think>` in replies | [Chat template mismatch](#chat-template-mismatch) |
| Tool-call arguments containing another tool call concatenated onto the end | [Chat template mismatch](#chat-template-mismatch) |
| Empty or partial tool arguments (`args={}`, `{"Path": ""}`) | [Chat template mismatch](#chat-template-mismatch) or [quantization too aggressive](#quantization) |
| Lists truncate mid-item with `finishReason=stop` | [Speculative decoding](#speculative-decoding) |
| Token repetition loops (`they'd'd'd'd...`) | [Speculative decoding](#speculative-decoding) |
| Long SSE silence, then watchdog kills the session | [Speculative decoding](#speculative-decoding) |
| Works in one session, breaks in another with longer history | [Chat template mismatch](#chat-template-mismatch) — longer context makes misfires more likely |

## Chat template mismatch

Different model families use different delimiters for tool calls and thinking blocks:

| Model family | Tool-call format | Reasoning format |
|---|---|---|
| Qwen3 / Qwen3.5 / Qwen3-Coder | `<tool_call><function=…><parameter=…>…</parameter></tool_call>` | `<think>…</think>` |
| DeepSeek-R1 | JSON-shaped | `<think>…</think>` |
| Hermes / Mistral | JSON-shaped | varies |

`llama-server` only parses these correctly with **`--jinja`**. That flag tells it to use the chat template embedded in the GGUF. Without it, the server falls back to a heuristic parser that doesn't recognize the delimiters and passes them through as plain text.

### Fix: add `--jinja` and `--reasoning-format`

For Qwen3 (the most common netclaw deployment):

```bash
llama-server \
  --model <path/to/qwen3-gguf> \
  --jinja \
  --reasoning-format deepseek \
  --flash-attn on \
  --ctx-size <N> \
  --parallel <K> \
  --port 8080
```

- **`--jinja`** — uses the GGUF's embedded chat template. Knows the model's tool-call delimiters.
- **`--reasoning-format deepseek`** — correct for Qwen3, which uses the same `<think>`/`</think>` delimiters as DeepSeek.

Restart llama-server with these flags, then send a message that triggers a tool call. You should see structured JSON tool calls in netclaw's session log — not `<tool_call>` XML leaking into chat.

### Rule of thumb

Models with XML-style tool-call markup or a bundled `chat_template.jinja` need `--jinja`.

### Models known to require `--jinja`

- **Qwen3 / Qwen3.5 / Qwen3.6 / Qwen3-Coder** — confirmed. `<tool_call>` XML and `</think>` leak without it.
- **Qwen2.5-Instruct (with tool calling)** — covered explicitly by [llama.cpp's function-calling docs](https://github.com/ggml-org/llama.cpp/blob/master/docs/function-calling.md).
- **DeepSeek-R1 distills** — reasoning leakage if `--reasoning-format` is wrong.

### Buggy GGUF templates

Some GGUF files (quantized model packages) ship with broken embedded templates. Check the model's Hugging Face discussions for community-corrected templates — serve them with `--chat-template-file <path>` instead of relying on the embedded one.

The [Unsloth Qwen3-Coder GGUF discussions](https://huggingface.co/unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF/discussions/10) document the exact failure modes and link to corrected templates.

## Quantization

Tool-call structure is quantization-sensitive. Sub-4-bit quants (Q3, Q2, IQ) produce malformed tool calls even with the correct template.

If you're on Q4 and seeing empty or garbled arguments, switch to Q5_K_XL or Q6_K_XL. You'll burn a bit more VRAM, but structured output accuracy jumps significantly.

## Speculative decoding

Speculative decoding (specdec) with `--spec-default` (or a separate draft model) causes three distinct failures on reasoning-format models like Qwen3:

1. **Mid-list truncation.** Model writes `1. <item>`, starts `2.`, then emits an end-of-sequence (EOS) token. Output is plain text, just cut short. `finishReason=stop` (not `length`).
2. **Token repetition loops.** Model enters a state producing hundreds of repetitions of a 1-2 character suffix. The inference server eventually returns HTTP 500.
3. **Long SSE silence.** Streaming starts normally, then deltas slow to a trickle and stop. Netclaw's streaming watchdog kills the session on inactivity timeout.

All three reproduce only with speculative decoding enabled.

### Why it happens

Specdec accepts tokens that match between draft and main, rejects on first divergence. At list markers, sentence boundaries, and `</think>`, rejections spike the EOS probability and flip the next token into stop emission (truncation) or a single-token loop with no recovery. Template mismatch between draft and main models concentrates rejections at these positions. Q4 quantization makes it worse — the compressed logit distribution means a single high-EOS position cascades more easily than on Q5/Q6.

### Fix: disable specdec

Remove `--spec-default` from your llama-server launch flags. If symptoms disappear, specdec rejection at template boundaries is confirmed.

Long-term, Multi-Token Prediction (MTP) uses the model's native multi-token heads instead of a draft model and avoids these rejection artifacts. For Qwen3.6, MTP support is tracked in [ggml-org/llama.cpp#22673](https://github.com/ggml-org/llama.cpp/pull/22673).

## Diagnosing with netclaw logs

Netclaw logs diagnostic counters at three layers for every LLM streaming call:

| Layer | What it reports |
|---|---|
| **SSE** | Raw deltas off the wire — delta counts, suppressed deltas, finish reason |
| **Middleware** | What the chat-client decorator saw before the actor consumed it |
| **Actor** | Assembled `ChatResponse` — text chars, thinking chars, tool calls, finish reason |

These show up in the per-session log at `~/.netclaw/logs/sessions/<channel>_<thread>/session.log`. Enable debug logging to see them — see [Debug Logging](/channels/troubleshooting/#debug-logging) for the config.

If counts match across all three layers but a tool call's `arguments` field is corrupted, the corruption originates upstream of netclaw — the inference server's chat template.

### Reading the counters

| Pattern | Diagnosis |
|---|---|
| `textChars=173 finishReason=stop` on a truncated list | Specdec early termination |
| `output=2 finishReason=stop` after long silence | Specdec stall — streaming watchdog timeout |
| High `thinkingChars` with `finishReason=length` | Repetition loop hit max-token cap |
| `textChars` inflated, then HTTP 500 from upstream | Repetition loop crashed the server's parser |

## See also

- [Self-Hosted Providers](/configuration/self-hosted-providers/) — llama.cpp and Ollama setup
- [Channel Troubleshooting](/channels/troubleshooting/) — Slack and Discord connectivity issues
- [`netclaw doctor`](/cli/doctor/) — health check diagnostics
- [`netclaw status`](/cli/status/) — live connector health

## Resources

- [llama.cpp function-calling docs](https://github.com/ggml-org/llama.cpp/blob/master/docs/function-calling.md) — definitive reference for `--jinja` and tool-call parsing
- [Qwen llama.cpp guide](https://qwen.readthedocs.io/en/latest/run_locally/llama.cpp.html) — official Qwen deployment guide
- [Unsloth Qwen3-Coder template fixes](https://huggingface.co/unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF/discussions/10) — community-corrected GGUF templates
- [llama.cpp server docs](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md) — full flag reference
