---
title: "netclaw memory"
description: "Embed memories that have no vector yet, after an upgrade to 0.27 or a model change."
---

`netclaw memory` has one subcommand: `backfill-embeddings`. It makes sure every stored memory has a vector from the current embedding model, so semantic recall can find it. You need it once after upgrading to 0.27 with memories you already had, and again after you change `Memory.Embeddings.ModelId`. It doesn't list, search, edit or delete memories. For that, see [fix a wrong memory](/configuration/memory/#fix-a-wrong-memory).

The command is offline. It reads and writes `~/.netclaw/netclaw.db` and the model files directly, so the daemon doesn't need to be running. It's safe to run next to a live daemon: each write checks the content hash first and skips anything the daemon has already embedded.

## Usage

```bash
netclaw memory backfill-embeddings [--force]
netclaw memory help
```

Running `netclaw memory` with no subcommand, or any unknown one, prints the same help. In Docker, run it through `docker exec <container> netclaw memory ...`.

## Options

| Flag | Description | Default |
|------|-------------|---------|
| `--force` | Re-scan every recallable memory, not only those missing a vector for the current model | Off |

`--force` still skips a memory whose stored vector matches its current text, so on an up-to-date store it reports `skipped-hash-unchanged` for everything and writes nothing. Use it when you suspect stale vectors. A change to the memory text or the model id is detected without it.

## Examples

### Backfill after upgrading to 0.27

```bash
netclaw memory backfill-embeddings
```

```text
Provisioning embedding model 'snowflake-arctic-embed-m-int8'...
Loading embedder 'snowflake-arctic-embed-m-int8' (768 dims)...
Embedding 1 document(s)...
  ...1/1

Done: embedded=1 skipped-hash-unchanged=0 failed=0
```

The command downloads the model first if it isn't on disk (about 110 MB, then loads it), embeds the memories in batches of 16, and prints progress. The exit code is `0` when nothing failed and `1` if any batch or memory failed. Rerunning is safe.

When everything already has a vector:

```text
Provisioning embedding model 'snowflake-arctic-embed-m-int8'...
Loading embedder 'snowflake-arctic-embed-m-int8' (768 dims)...
Nothing to backfill: all recallable documents already have a current-model embedding.
```

### Fix the doctor warning

`netclaw doctor` shows this when vectors are missing, for example after memories were changed directly in the database:

```text
[WARN] Memory Embeddings: 1 of 1 recallable documents lack a current-model embedding. queryPrefix=True floor=0.240 (source=manifest).
       fix: The daemon's gap-repair sweep heals this at next startup, or run `netclaw memory backfill-embeddings` now.
```

Restarting the daemon fixes the same gap. Run the command when you don't want to restart.

### Offline hosts

With `Memory.Embeddings.AutoDownload` set to `false`, the command doesn't download. It loads the model from `~/.netclaw/models/` or exits `1`:

```text
[FAIL] unable to provision embedding model 'snowflake-arctic-embed-m-int8': Embedding model 'snowflake-arctic-embed-m-int8' is not provisioned (or fails hash verification) at /home/netclaw/.netclaw/models/snowflake-arctic-embed-m-int8, and Memory.Embeddings.AutoDownload is false. Provision the model manually, or enable AutoDownload and re-run this command.
```

Copy the model in first. [Run offline](/configuration/memory/#run-offline) has the file list.

### Embeddings turned off

With `Memory.Embeddings.Enabled` set to `false`, the command does nothing, with or without `--force`. It downloads no model, embeds nothing and exits `0`:

```text
Embeddings are disabled (Memory.Embeddings.Enabled is false); nothing to backfill. Set Memory.Embeddings.Enabled to true to embed memories.
```

## Related pages

- [Memory and embeddings](/configuration/memory/) - settings, resource cost, offline use, fixing a wrong memory
- [Memory model](/architecture/memory-model/) - how recall uses the vectors
- [`netclaw doctor`](/cli/doctor/) - reports missing vectors and model health
- [Upgrade netclaw](/guides/upgrading/) - when to run the backfill

## Resources

- [snowflake-arctic-embed-m](https://huggingface.co/Snowflake/snowflake-arctic-embed-m) - the default embedding model
- [ONNX Runtime](https://onnxruntime.ai/) - the runtime that executes it
