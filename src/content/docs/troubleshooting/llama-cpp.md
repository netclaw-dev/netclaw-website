---
title: "Troubleshooting llama.cpp"
description: "Fix XML markup in chat, truncated replies, repetition loops, silent or endless thinking, and wrong context or vision detection on self-hosted llama.cpp."
---

This page covers llama.cpp (`llama-server`). If you're on Ollama or vLLM, these flags don't apply: Ollama applies chat templates itself, and vLLM has [its own page](/troubleshooting/vllm/).

Raw `<tool_call>` XML in chat, stray `</think>` tags, empty tool arguments, replies that trail off, a model that thinks forever, a session that goes quiet: most of these trace back to how the server parses the model's chat template. netclaw assembles the streaming deltas it receives, and it extracts `<tool_call>` blocks that arrive as plain text, so what you see in chat is usually what the server emitted.

## Quick checklist

Try these before reading on:

1. Check that `--jinja` is on. It's the default in current llama.cpp builds, but older builds need it spelled out, and a build that predates the default is the usual cause on Qwen3 and DeepSeek-R1.
2. Read the model card on Hugging Face for recommended flags or a custom chat template.
3. Check the quantization. Q4 or lower breaks tool-call structure on some models. Try Q5 or Q6.
4. Turn speculative decoding off if replies truncate or repeat. Remove `--spec-default`.
5. Update llama.cpp. Tool-call parser fixes land often.
6. Check the GGUF's embedded template. Community-corrected templates exist for several Qwen3 quants.

## Symptoms

| What you're seeing | Jump to |
|---|---|
| `<tool_call>`, `<function=...>`, `<parameter=...>` as plain text | [Raw tool-call XML in chat](#raw-tool-call-xml-in-chat) |
| Stray `<think>` or `</think>` in replies | [Raw tool-call XML in chat](#raw-tool-call-xml-in-chat) |
| Empty or partial tool arguments (`args={}`, `{"Path": ""}`) | [Raw tool-call XML in chat](#raw-tool-call-xml-in-chat) or [Garbled tool arguments](#garbled-tool-arguments) |
| Lists truncate mid-item, or output loops on one token | [Truncated or looping output](#truncated-or-looping-output) |
| `The model reply was truncated: the model reached its output limit...` | [Truncated or looping output](#truncated-or-looping-output) |
| The channel goes quiet, or a turn runs for minutes | [Silent, slow, or endless thinking](#silent-slow-or-endless-thinking) |
| `I didn't manage to produce a reply` | [Silent, slow, or endless thinking](#silent-slow-or-endless-thinking) |
| `netclaw status` shows `input: Text` for a vision model | [Wrong context window or vision](#wrong-context-window-or-vision) |
| Compaction on every turn, or `Context window exceeded` | [Wrong context window or vision](#wrong-context-window-or-vision) |

## Raw tool-call XML in chat

**Symptom:** `<tool_call>` markup, `<function=...>` tags, or `</think>` appear in replies. It gets worse in long sessions, because longer context makes misfires more likely.

**Cause:** Model families use different delimiters for tool calls and thinking:

| Model family | Tool-call format | Reasoning format |
|---|---|---|
| Qwen3 / Qwen3.5 / Qwen3-Coder | `<tool_call><function=...><parameter=...>...</parameter></tool_call>` | `<think>...</think>` |
| DeepSeek-R1 | JSON-shaped | `<think>...</think>` |
| Hermes / Mistral | JSON-shaped | varies |

`llama-server` parses these correctly only with the Jinja chat template enabled, which uses the template embedded in the GGUF. Without it the server falls back to a heuristic parser that passes the delimiters through as text.

**Fix:** Run with `--jinja` and a reasoning format. For Qwen3:

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

- `--jinja` uses the GGUF's chat template and knows the model's tool-call delimiters. Current builds default to it.
- `--reasoning-format deepseek` puts thinking in `message.reasoning_content` instead of the reply. Qwen3 uses the same `<think>` delimiters as DeepSeek. The default is `auto`.

Restart, then send a message that triggers a tool call. The session log should show structured tool calls, not XML in chat. Models with XML-style tool markup or a bundled `chat_template.jinja` need this: Qwen3 through Qwen3.6, Qwen3-Coder, Qwen2.5-Instruct with tools ([covered in llama.cpp's function-calling docs](https://github.com/ggml-org/llama.cpp/blob/master/docs/function-calling.md)), and DeepSeek-R1 distills.

Some GGUF files ship a broken embedded template. Check the model's Hugging Face discussions for a corrected one and serve it with `--chat-template-file <path>`. The [Unsloth Qwen3-Coder discussion](https://huggingface.co/unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF/discussions/10) documents the failure modes and links corrected templates.

## Garbled tool arguments

**Symptom:** Tool calls with empty arguments or a second tool call glued onto the end of the first.

**Cause:** Tool-call structure is quantization-sensitive. Sub-4-bit quants (Q3, Q2, IQ) produce malformed calls even with the right template, and Q4 does on some models.

**Fix:** Move to Q5_K_XL or Q6_K_XL. It costs a bit more VRAM and accuracy of structured output rises a lot.

## Truncated or looping output

A reply that stops at the output limit (`finishReason=length` with no tool call) fails the turn with `The model reply was truncated: the model reached its output limit before it finished. The cut-off text was not posted.` For a self-hosted server netclaw sends a 32000-token limit, clamped to the context window, only when that window is known from `ContextWindow` or the server's own probe. Change it with `netclaw model set <role> <provider> <model> --max-output-tokens N`.

The other symptoms in this section:

**Symptom:** A list stops mid-item with `finishReason=stop`, the model emits hundreds of one- or two-character repeats until the server returns HTTP 500, or streaming slows to a trickle and the watchdog ends the session.

**Cause:** Speculative decoding on reasoning-format models like Qwen3. It accepts tokens that match between draft and main model and rejects at the first divergence. At list markers, sentence ends, and `</think>`, rejections spike the end-of-sequence probability, which flips the next token into a stop (truncation) or a single-token loop. A template mismatch between draft and main model concentrates the rejections there, and Q4 makes it worse. All three failures reproduce only with speculative decoding on.

**Fix:** Remove `--spec-default` (or the separate draft model) from your launch flags. If the symptoms vanish, that was it. Multi-Token Prediction uses the model's native heads instead of a draft model and avoids the artifacts. Qwen3.6 support is tracked in [ggml-org/llama.cpp#22673](https://github.com/ggml-org/llama.cpp/pull/22673).

## Silent, slow, or endless thinking

**Symptom:** A Slack or Discord channel goes quiet for minutes after a message. `netclaw chat` shows no output for a long time. Or the turn ends with `I didn't manage to produce a reply. Please try rephrasing or sending your request again.`

**Cause:** Usually one of three things, and they look alike from the outside:

1. **Prefill.** A long context on a slow GPU, or a busy single slot, delays the first token. netclaw waits up to 30 minutes for it by default.
2. **A reasoning model that thinks and never answers.** Qwen3.x and DeepSeek-R1 style models can emit thinking with no reply and no tool call. netclaw nudges the model to answer (`Stop thinking and write your answer now`) and retries, up to 5 times before any tool work and 8 times after. Then it gives up with the message above. Thinking text isn't shown in channels by design.
3. **An endless tool loop.** After two equal rounds netclaw refuses the next identical call and nudges the model (repeats 1 to 4), nudges harder at repeat 5, and ends the turn quietly at repeat 6. Failed calls with no success between them get a nudge at 4, a stronger one at 6, and end the turn at 8. A success in the batch resets that count. A model call that streams only thinking ends the turn at three times `Session.NoProgressTimeoutSeconds` (60 minutes by default).

On a single-slot server, one runaway turn blocks every other request to that endpoint, which is why a whole channel can look dead.

**Fix:**

- Tell prefill from a hang: watch the llama-server console. Prompt processing shows progress, a thinking loop shows steady generation, and a wedge shows nothing.
- Set the thinking level in netclaw with `netclaw model set main <provider> <model> --thinking off`. For llama.cpp, `model set` detects the server and saves `Providers:<name>:VendorOptions:ThinkingDialect` as `ReasoningEffort`, which sends `reasoning_effort` (`none` for `off`, then `low`, `medium` or `high`, with no `max`). You can also switch thinking off or cap it at the server. `--reasoning-budget 0` ends thinking immediately, a positive value caps the tokens, and for Qwen3 `--chat-template-kwargs '{"enable_thinking": false}'` turns it off in the template.
- Raise or lower the limits with `Session.PrefillTimeoutSeconds`, `Session.FirstTokenTimeoutSeconds`, and `Session.NoProgressTimeoutSeconds` (see [Slow models and timeouts](/configuration/models/#slow-models-and-timeouts)). A watchdog hit shows as `Session processing operation 'LlmCall' exceeded watchdog timeout of <n>s` or `produced no substantive output within <n>s`.
- Give llama-server more slots (`--parallel`) if several channels share one endpoint.
- If a turn is stuck right now, restarting the daemon frees the slot.

An older bug where the model re-narrated the same plan before every tool call (strict ChatML templates, [netclaw#1216](https://github.com/netclaw-dev/netclaw/issues/1216)) was fixed after 0.21.1. If you see it on a current version, open an issue.

## Wrong context window or vision

**Symptom:** `netclaw status` shows `input: Text` for a model that takes images, or `context:` doesn't match your `--ctx-size`. Or compaction fires on every turn, or the reply says `Context window exceeded after compaction`.

**Cause:** netclaw reads `n_ctx` and `modalities.vision` from llama-server's `/props` endpoint. If `/props` is blocked (a reverse proxy, a path prefix), the server runs in router mode, or `ContextWindow` was overridden to the wrong number, detection is wrong. netclaw reads `/props` at the host root, so a proxy that serves the API under a prefix hides it.

**Fix:** Open `/props` on the server and compare. Then set the right value on the definition:

```bash
netclaw model set main llama-server my-model --context-window 32768 --input-modalities "Text, Image"
```

A `ContextWindow` smaller than the server's context makes compaction fire constantly. One larger than `--ctx-size` gets the request rejected. [Models](/configuration/models/#context-window-and-modalities) has the full table, and [Images and other file types](/guides/multimodal-files/) covers vision.

## Diagnosing with netclaw logs

At debug level, netclaw logs counters at three layers for every streaming call:

| Layer | What it reports |
|---|---|
| SSE | Raw deltas off the wire: delta counts, suppressed deltas, finish reason |
| Middleware | What the chat-client decorator saw before the session consumed it |
| Actor | The assembled response: `textChars`, `thinkingChars`, tool calls, finish reason |

The tool call lines carry redacted arguments, so a string over 256 characters shows as `<N chars, sha256 ...>` and one that held a secret as `<N chars, redacted>`. To check for a corrupted `arguments` field, read the debug-level SSE counters rather than the `args=` text.

They land in the session's log at `~/.netclaw/sessions/<channel>_<thread>-<id>/logs/session.log`. Sessions created before 0.27 keep their log under `~/.netclaw/logs/sessions/`. See [Debug logging](/channels/troubleshooting/#turn-on-debug-logging) to enable it.

If the counts match across all three layers but a tool call's `arguments` field is corrupted, the corruption came from upstream of netclaw: the server's chat template.

| Pattern | Diagnosis |
|---|---|
| `textChars=173 finishReason=stop` on a truncated list | Speculative decoding ended early |
| `output=2 finishReason=stop` after a long silence | Speculative decoding stall, then the watchdog |
| High `thinkingChars` with `finishReason=length` | Thinking loop hit the token cap. The turn now fails with `The model reply was truncated: the model reached its output limit before it finished.` instead of looking silent |
| High `thinkingChars`, no `textChars`, repeated retries | Thinking-only responses: see [Silent, slow, or endless thinking](#silent-slow-or-endless-thinking) |
| `textChars` inflated, then HTTP 500 from upstream | A repetition loop crashed the server's parser |

## Related pages

- [Self-hosted providers](/configuration/self-hosted-providers/) - llama.cpp and Ollama setup
- [Models](/configuration/models/) - context window, modalities, and timeouts
- [vLLM quirks](/troubleshooting/vllm/) - the same problems on vLLM
- [Channel troubleshooting](/channels/troubleshooting/) - Slack and Discord connectivity
- [`netclaw status`](/cli/status/) - live model and connector health

## Resources

- [llama.cpp function-calling docs](https://github.com/ggml-org/llama.cpp/blob/master/docs/function-calling.md) - the reference for `--jinja` and tool-call parsing
- [llama.cpp server docs](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md) - the full flag reference
- [Qwen llama.cpp guide](https://qwen.readthedocs.io/en/latest/run_locally/llama.cpp.html) - the official Qwen deployment guide
- [Unsloth Qwen3-Coder template fixes](https://huggingface.co/unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF/discussions/10) - community-corrected GGUF templates
