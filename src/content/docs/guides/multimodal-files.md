---
title: "Let the agent see images and read other files"
description: "Which file types netclaw hands to a model, how to turn on vision when detection misses it, what happens when the model can't take a file, and the attachment limits."
---

Send the agent a screenshot in Slack or ask it to `file_read` a PNG, and it can look at the picture, as long as the model accepts images. Everything else (PDFs, Office files, archives, audio, video) reaches the agent as a file on disk plus a note about how to extract it. This guide covers what works where, how to turn vision on, and what you see when it doesn't work.

| I want to | Do this |
|-----------|---------|
| Have the agent describe an image | Use a model with `input: Text, Image` in `netclaw status` |
| Turn on vision for a model netclaw thinks is text-only | [Override the modalities](#turn-on-vision) |
| Let a channel accept PDFs or archives | [Widen the attachment policy](#change-what-a-channel-accepts) |
| Read a PDF or Word file | The agent extracts it with `shell_execute`: [What reaches the model](#what-reaches-the-model) |
| Send images to a second model while Main is text-only | Not possible: [Limits](#limits) |

## Before you begin

- A model role that accepts images. Run [`netclaw status`](/cli/status/) and check `input:` for `Image`.
- For channel uploads, the audience's attachment policy must allow the category. Every audience allows images by default.

## What reaches the model

netclaw classifies each file by extension and magic bytes (the signature in the first few KB), then decides what to do:

| Type | Examples | What the agent gets |
|------|----------|---------------------|
| Text | `.txt`, `.md`, `.csv`, `.json`, `.xml`, `.yaml`, source code, any UTF-8 file | The content, paged with `Offset` and `Limit` |
| Image | PNG, JPEG, GIF, WebP | The picture itself, on a model with image input |
| Image | BMP, TIFF | Recognized, but passed by path only |
| PDF | `application/pdf` | Metadata and a pointer to `shell_execute` (`pdftotext`) |
| Document | DOCX, XLSX, PPTX, POTX, ODT, ODS, ODP, RTF, DOC, XLS, PPT | Metadata and a pointer to an extraction tool |
| Archive | ZIP, 7z, gzip, bzip2, xz | Metadata and a pointer to an extraction tool |
| Audio, video | MP3, M4A, WAV, OGG, MP4, MOV, WebM, MKV, AVI | Metadata only. Transcription and keyframes aren't built in |

Extension and signature are reconciled, so a `.md` file declared as `text/plain` is still markdown, and a binary file named `.png` stays metadata-only. HTML counts as text.

The same classifier serves `file_read` and channel attachments (Slack, Discord, Mattermost), so an image dropped in a channel reaches a vision model the way a `file_read` image does. `file_read` also reports an image's dimensions.

## Turn on vision

Vision is a property of the model. netclaw detects it from the server where it can: llama.cpp reports it in `/props`, Ollama in the model metadata, and the OpenRouter and Hugging Face catalogs cover many named models. vLLM and unusual model names often come back text-only. Check:

```bash
netclaw status
```

```
model: demo-model (provider: lab, context: 131,072 tokens)
  input: Text, Image
  output: Text
```

If a model that sees images shows `input: Text`, override it on the definition:

```bash
netclaw model set main my-vllm-provider qwen36-ultimate --input-modalities "Text, Image"
```

`--clear-modalities` hands the field back to detection. The override lives on the definition, so it survives role changes. [Models](/configuration/models/#context-window-and-modalities) has the config form.

Then ask the agent to look at a file. In our test, a 128x128 PNG with a green left half and a magenta right half, on a llama.cpp Qwen3.8 model that reported vision:

```bash
netclaw chat -p "Use your file tool to look at the image /tmp/split.png and tell me what colors you see."
```

The agent called `file_read`, got `Image loaded for model-visible inspection on the next LLM call.`, and answered that the left half was green and the right half magenta.

## When the model can't take the file

The same test with `--input-modalities "Text"` set. `file_read` returned metadata and the note `current model has no image modality; file is on disk but not viewable this turn`, and the agent said it couldn't see the image.

| Situation | What happens |
|-----------|--------------|
| Image, model has no image input | The file lands on disk and the agent gets the note above. The turn continues |
| Image over 25 MB through `file_read` | Metadata and a note that the image exceeds the model-input handoff limit |
| PDF on any model | The note `current model has no native PDF support; use shell_execute (e.g., pdftotext) to extract text` |
| Document, archive, audio, video | The note `format not inlineable; use file_read or shell_execute to process` |
| You switch to a text-only model after images are in the history | The old images are stripped from what's sent, with a warning in the log. The session stays usable |
| You attach a new image to a session whose model has no image input | The message is rejected with `The session input is not compatible with model '<id>'` and lists the required and supported modalities |

## Change what a channel accepts

Each [audience](/security/security-model/) has an attachment policy under `Tools.AudienceProfiles.<Audience>.ChannelAttachments`. The defaults:

| Audience | Allowed categories |
|----------|--------------------|
| Public | `Image` |
| Team | `Image`, `Pdf`, `Document`, `Archive`, `Media` |
| Personal | The Team list plus `Other` |

Limits are 25 MiB per file and 10 files per message for every audience. `Media` covers audio and video together, so you can't allow one without the other. To narrow an audience, give it the shorter list:

```json
{
  "Tools": {
    "AudienceProfiles": {
      "Team": {
        "ChannelAttachments": {
          "AllowedCategories": ["Image", "Pdf"],
          "MaxFileBytes": 10485760,
          "MaxFilesPerMessage": 5
        }
      }
    }
  }
}
```

A list you configure **replaces** the default list. It doesn't add to it, so name every category you want. An unknown category name, or `MaxFileBytes` or `MaxFilesPerMessage` of 0 with categories listed, stops the daemon at startup.

## Limits

- Only PNG, JPEG, GIF, and WebP go to the model as pixels. Nothing transcribes audio or extracts video frames.
- One model sees every image. netclaw can't route images to a second, vision-capable model while Main is text-only. A named image proxy is proposed in [netclaw#1728](https://github.com/netclaw-dev/netclaw/issues/1728) and isn't shipped. Until then, point Main (or Fallback) at a model that takes images.

## Troubleshooting

### The agent says it can't see the image

**Symptom:** The agent answers `I can't see the image` or guesses.

**Cause:** The active model has no image input in netclaw's eyes: `netclaw status` shows `input: Text`.

**Fix:** [Turn on vision](#turn-on-vision) if the model can take images, or switch Main to one that can.

### A channel ignores an upload

**Symptom:** A user posts a PDF or archive and nothing arrives, or they get a rejection reply.

**Cause:** Their audience doesn't allow the category, the file is over the size limit, or the message has too many files.

**Fix:** Check the audience's `ChannelAttachments` above and widen it deliberately.

### A BMP or TIFF isn't viewed

**Symptom:** The agent gets the path but not the picture.

**Cause:** Those formats are accepted but only PNG, JPEG, GIF, and WebP are handed to the model.

**Fix:** Convert the image (`convert in.tiff out.png`) and send that.

## Related pages

- [Models](/configuration/models/) - modality overrides and model roles
- [Security model](/security/security-model/) - per-audience attachment policies
- [vLLM quirks](/troubleshooting/vllm/#vision-models-report-as-text-only) - why vLLM models often come back text-only
- [MCP tool permissions](/guides/mcp-tool-permissions/) - granting `file` and `shell` tools

## Resources

- [List of file signatures](https://en.wikipedia.org/wiki/List_of_file_signatures) - how content-based type detection works
- [`pdftotext` (Poppler)](https://poppler.freedesktop.org/) - extract text from PDFs through `shell_execute`
- [llama.cpp multimodal docs](https://github.com/ggml-org/llama.cpp/blob/master/docs/multimodal.md) - serve a vision model with `--mmproj`
