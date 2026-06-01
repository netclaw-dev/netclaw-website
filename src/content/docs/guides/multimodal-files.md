---
title: "Images, Audio, and Other File Types"
description: "How netclaw classifies files and hands images to vision-capable models."
---

When the agent reads a file, netclaw classifies it upfront instead of assuming everything is text. A text file comes back as text; an image gets handed to the model as something it can actually see; a PDF or zip comes back with a note on how to extract it. One classifier drives this for both `file_read` and channel attachments.

## How files are classified

Netclaw identifies a file by its extension and its magic bytes (the signature in the first few KB), then recognizes its type:

| Type | Examples |
|------|----------|
| Text | `.txt`, `.md`, `.csv`, `.json`, `.xml`, `.yaml` — plus any UTF-8 text file (source code included), detected by content |
| Image | PNG, JPEG, GIF, WebP, BMP, TIFF |
| PDF | `application/pdf` |
| Document | DOCX, XLSX, PPTX, ODT, RTF |
| Archive | ZIP, 7z, gzip, bzip2, xz |
| Audio | MP3, M4A, WAV, OGG |
| Video | MP4, MOV, WebM, MKV, AVI |

Extension and signature are reconciled, so a `.md` file declared as `text/plain` is still treated as markdown, and a file with the wrong extension is caught by its actual bytes.

## Reading files with `file_read`

What `file_read` returns depends on the category:

- **Text** -- the content, with `Offset`/`Limit` for paging and truncation past a size cap. Same as you'd expect.
- **Image, on a vision-capable model** -- netclaw attaches the image to the next model call and returns a note: *"Image loaded for model-visible inspection on the next LLM call."* The model sees the actual picture on its next turn. Inlined formats are **PNG, JPEG, GIF, and WebP**; BMP and TIFF are recognized but passed by path only. Files are capped at **25 MB**.
- **Image, on a model with no vision** -- a note that the current model has no image modality. The file is on disk; the model just can't look at it.
- **PDF, document, archive, audio, video** -- metadata plus a pointer to the right extraction tool. `file_read` never dumps raw bytes into the conversation; use `shell_execute` (for example, `pdftotext` for a PDF) to pull text out.

## Attachments from channels

Files shared in Slack, Discord, or Mattermost flow through the same classifier. An image dropped in a channel reaches a vision model the same way a `file_read` image does, and the same per-format and size rules apply.

What's allowed per channel is governed by the [audience](/security/security-model/)'s attachment policy: which categories are accepted, a max file size (25 MB by default), and a max number of files per message (10 by default). The policy's categories are coarser than the types above -- `Image`, `PDF`, `Document`, `Archive`, `Media`, and `Other` -- and audio and video both fall under a single `Media` category, so you can't allow one without the other. Lock a channel down by narrowing its allowed categories.

:::note
Vision support is a property of the model, not netclaw. Point a model role at a vision-capable model (check `netclaw model`) before expecting the agent to read images. As of 0.22.1, an image attached via a tool call stays attached across turn boundaries -- earlier builds could drop it, leaving the model to guess at what it never actually received.
:::

## Related pages

- [Models](/configuration/models/) -- assign a vision-capable model to a role
- [Security Model](/security/security-model/) -- per-audience attachment policies
- [MCP Tool Permissions](/guides/mcp-tool-permissions/) -- granting `file` and `shell` tools

## External resources

- [Magic numbers (file signatures)](https://en.wikipedia.org/wiki/List_of_file_signatures) -- how content-based type detection works
- [`pdftotext` (Poppler)](https://poppler.freedesktop.org/) -- extract text from PDFs via `shell_execute`
