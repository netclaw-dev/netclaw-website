---
title: "Memory and embeddings"
description: "Turn local semantic memory off, run it offline, size the host for it, and fix a memory that's wrong."
---

netclaw keeps what it learns in `netclaw.db` and recalls it before each turn. Since 0.27.0 that recall includes local semantic search: two small ONNX models run inside the daemon, so no cloud embedding service is involved. It's on by default, and the only network access it needs is a one-time model download from huggingface.co on first start. For how recall works, read the [memory model](/architecture/memory-model/). This page covers what to configure, what it costs, and what to do when a memory is wrong.

## What's on by default

| Piece | Default | Where it lives |
|-------|---------|----------------|
| Memory (formation, curation, recall) | On | `~/.netclaw/netclaw.db` (SQLite) |
| Embedding model `snowflake-arctic-embed-m-int8` | On, downloads on first start | `~/.netclaw/models/snowflake-arctic-embed-m-int8/` |
| Relevance model `ms-marco-minilm-l-6-v2` | On with embeddings, downloads on first start | `~/.netclaw/models/ms-marco-minilm-l-6-v2/` |

Both models come from a pinned allowlist, and netclaw verifies a SHA-256 hash on every load. It never loads a model from an arbitrary URL.

## What it costs

Measured on the 0.27.1 release image, one container with embeddings on and one with `Memory.Embeddings.Enabled` set to `false`, each started on an empty data directory.

| | Embeddings on (default) | Embeddings off |
|---|---|---|
| Daemon RSS, idle | about 480 MB | about 235 MB |
| Daemon RSS, after a few memory writes and recalls | about 560 MB | about 250 MB |
| Download on first start | 129 MB (110 MB embedder, 23 MB relevance model) | none |
| Disk under `models/` | 129 MB | none |

The download took about 4 seconds on a fast connection. The daemon doesn't wait for it. The listener came up about a second after launch, the embedder was ready 3 seconds later, and the relevance model half a second after that. Until both are ready, recall runs full-text only.

The 0.27.0 release notes plan for roughly 800 MB total RSS on their reference configuration. Size the host for that, not for the idle number.

## Turn embeddings off

Set `Memory.Embeddings.Enabled` to `false` in `~/.netclaw/config/netclaw.json`:

```json
{
  "Memory": {
    "Embeddings": { "Enabled": false }
  }
}
```

The daemon restarts itself when `netclaw.json` changes. Nothing gets downloaded, no models load, and recall falls back to full-text search with the composite score floor. The relevance gate follows the embeddings switch, so it turns off too. `netclaw doctor` reports both as disabled, which is a pass, not a warning:

```text
[PASS] Memory Embeddings: Embeddings disabled (Memory.Embeddings.Enabled is false).
[PASS] Memory Relevance Gate: Relevance gate disabled (follows Memory.Embeddings.Enabled, which is false).
```

`netclaw memory backfill-embeddings` honors the same switch. With embeddings off it downloads nothing, embeds nothing and exits `0` with a message naming the setting. See [`netclaw memory`](/cli/memory/).

## Settings

Everything lives under `Memory` in `netclaw.json`. The defaults are right for most installs. For every key in the file, see the [configuration reference](/configuration/reference/).

| Key | Type | Default | What it does |
|-----|------|---------|--------------|
| `Memory.Enabled` | bool | `true` | Master switch. `false` removes the memory tools and automatic recall. |
| `Memory.RecallTimeoutMs` | int | `300` | Time budget for automatic recall per turn. |
| `Memory.AutoRecallMaxItems` | int | `3` | Most memories injected into one turn (1 to 10). |
| `Memory.Embeddings.Enabled` | bool | `true` | Load the local models, embed on write, hybrid recall, relevance gate. |
| `Memory.Embeddings.ModelId` | string | `snowflake-arctic-embed-m-int8` | Allowlisted embedding model. See below. |
| `Memory.Embeddings.AutoDownload` | bool | `true` | Fetch missing models at startup. `false` means a missing model degrades loudly instead. |
| `Memory.Recall.MinCosineSimilarity` | number or null | `null` | Similarity floor. `null` uses the model's calibrated value (0.24 for both Snowflake models). |
| `Memory.Recall.RelevanceGate.Enabled` | bool or null | `null` | `null` follows `Memory.Embeddings.Enabled`. |
| `Memory.Recall.RelevanceGate.Threshold` | number or null | `null` | `null` uses the relevance model's calibrated value (0.02). |
| `Memory.Recall.VectorWeight` / `LexicalWeight` | number | `0.7` / `0.3` | Weights in the hybrid score. |
| `Memory.Recall.RecencyHalfLifeDays` | number | `30` | Half-life of the recency decay on recalled scores. |
| `Memory.Curation.NominatorSimilarityThreshold` | number | `0.86` | Cosine similarity above which an existing memory is shown to the curation call as a possible duplicate. |
| `Memory.Curation.NominatorK` | int | `5` | Most near-duplicates shortlisted per new memory. |
| `Memory.Curation.LlmTimeoutSeconds` | int | `60` | Timeout on the curation model call. Curation uses your Main model, not the Compaction model. |

Memory formation timing lives under `Session`: `Session.MemoryObserverIdleSeconds` (default 90) and `Session.Tuning.MemoryDistillationTurnInterval` (default 5). See [Sessions](/architecture/sessions/).

:::note
Leave `MinCosineSimilarity` and the gate threshold alone unless you've re-measured. Cosine scores are specific to the model and its query prefix, so a floor tuned for one model can drop every candidate on another.
:::

### Pick a different model

`Memory.Embeddings.ModelId` accepts three ids: `snowflake-arctic-embed-m-int8` (default), `snowflake-arctic-embed-m` (the fp32 weights of the same model, which use noticeably more memory), and `mxbai-embed-large-v1` (not calibrated, so hybrid recall falls back to full-text unless you set `MinCosineSimilarity`). Any other id is rejected. The daemon logs `memory_embedding_unavailable ... Unknown embedding model id` at startup and runs on full-text recall. There's no setting that points embeddings at a remote service.

When you change the id, the daemon re-embeds the whole memory store under the new model at the next start. `netclaw doctor` warns about the mixed state until that finishes.

## Run offline

Two settings and one copy step get you a daemon that never touches the network for memory. With `Memory.Embeddings.AutoDownload` set to `false`, a missing model becomes a visible degraded state instead of a download.

1. Download the files on a machine with access, from the pinned revisions netclaw uses:

   | File | Source |
   |------|--------|
   | `snowflake-arctic-embed-m-int8/model.onnx` | [onnx/model_uint8.onnx](https://huggingface.co/Snowflake/snowflake-arctic-embed-m/resolve/fc74610d18462d218e312aa986ec5c8a75a98152/onnx/model_uint8.onnx) |
   | `snowflake-arctic-embed-m-int8/vocab.txt` | [vocab.txt](https://huggingface.co/Snowflake/snowflake-arctic-embed-m/resolve/fc74610d18462d218e312aa986ec5c8a75a98152/vocab.txt) |
   | `ms-marco-minilm-l-6-v2/model.onnx` | [onnx/model_quantized.onnx](https://huggingface.co/Xenova/ms-marco-MiniLM-L-6-v2/resolve/a09144355adeed5f58c8ed011d209bf8ee5a1fec/onnx/model_quantized.onnx) |
   | `ms-marco-minilm-l-6-v2/vocab.txt` | [vocab.txt](https://huggingface.co/Xenova/ms-marco-MiniLM-L-6-v2/resolve/a09144355adeed5f58c8ed011d209bf8ee5a1fec/vocab.txt) |

   The simpler route is to let a connected netclaw download them once, then copy its `~/.netclaw/models/` directory. The layout is `models/<model id>/model.onnx` and `models/<model id>/vocab.txt`, as in the table.

2. Put the files in `~/.netclaw/models/` on the offline host, owned by the user that runs the daemon. In Docker, copy them into the data volume and fix the owner:

   ```bash
   docker cp ./models netclaw:/home/netclaw/.netclaw/
   docker exec -u root netclaw chown -R 1654:1654 /home/netclaw/.netclaw/models
   ```

3. Set `AutoDownload` to `false`, then restart the daemon (`docker restart netclaw` in Docker):

   ```json
   {
     "Memory": {
       "Embeddings": { "AutoDownload": false }
     }
   }
   ```

4. Run `netclaw doctor`. Both checks pass once the hashes match:

   ```text
   [PASS] Memory Embeddings: Embeddings healthy: 0/0 documents embedded under 'snowflake-arctic-embed-m-int8'. queryPrefix=True floor=0.240 (source=manifest).
   [PASS] Memory Relevance Gate: Relevance gate healthy: model 'ms-marco-minilm-l-6-v2' provisioned (threshold 0.020).
   ```

If a model is missing or fails its hash, `AutoDownload: false` blocks even the repair download. The daemon still starts and recall runs full-text only. Doctor reports `[FAIL] Memory Embeddings` and `[FAIL] Memory Relevance Gate`, and the daemon log carries `memory_embedding_unavailable` and `memory_relevance_gate_unavailable` errors.

:::note
On a host with no network at all, the daemon's update check also fails at startup. That's unrelated to memory, but `netclaw doctor` may show a "Daemon Crash Logs" warning for it. It's an unobserved connection error from the update check, and the daemon keeps running.
:::

## Fix a wrong memory

Memory is only as good as what was said and stored. A failed attempt, a guess, or an outdated fact can get remembered and then recalled with confidence. There's no `netclaw memory list` or `delete` command, and the CLI can't export memories. The supported route is to ask the agent, which has the memory tools. The database is the fallback.

### 1. Find it

Ask in any chat where you have Personal or Team access:

```text
Search your memory for the staging database and show me the ids.
```

The agent runs `find_memories` and `get_memories` and shows ids like `doc-ea98f564e23b412b9e3e9aae6f6524ec`. To see the stored text directly, read the database. The Docker image includes `sqlite3`:

```bash
docker exec -u netclaw netclaw sqlite3 -readonly /home/netclaw/.netclaw/netclaw.db \
  "select document_id, title, update_semantics, recall_mode, substr(markdown_body,1,120) from memory_documents;"
```

On a native install, point `sqlite3` at `~/.netclaw/netclaw.db`. Stock Linux images don't ship it, so install it first (`sudo apt-get install -y sqlite3` on Ubuntu).

### 2. Correct it

Tell the agent the right fact and give it the id:

```text
Update memory doc-ea98f564e23b412b9e3e9aae6f6524ec: the staging database is PostgreSQL 16, not 15.
```

The agent calls `update_memory` with `old_text` and `new_text` (or `new_content` for a full rewrite) and replies `Memory "doc-..." updated.` The edit drops the memory's old vector and embeds the new text before the tool replies, so the corrected memory is recalled on meaning straight away. With embeddings off there's no vector to refresh.

### 3. Remove it

```text
Delete memory doc-ea98f564e23b412b9e3e9aae6f6524ec. Use update_memory with delete set to true.
```

The tool answers `Memory "doc-..." tombstoned.` A tombstone keeps the row but sets `update_semantics` to `tombstone` and `recall_mode` to `never`, and deletes the memory's full-text entry and its vectors, so it can't be recalled or found by search.

Name the `delete` flag. In testing, a model that wasn't told about it decided `update_memory` couldn't delete and overwrote the body with "DELETED". The memory then stayed recallable as a normal document containing that text.

### 4. Remove it from the database

If the agent can't do it, or you want the row gone, stop relying on tools and edit the file. This isn't a supported interface and the schema can change between releases. Back up first, run it in a transaction, then restart. The `-u netclaw` keeps the database files owned by the daemon's user:

```bash
docker exec -u netclaw netclaw sqlite3 /home/netclaw/.netclaw/netclaw.db ".backup '/home/netclaw/.netclaw/netclaw.db.bak'"
docker exec -u netclaw netclaw sqlite3 /home/netclaw/.netclaw/netclaw.db "
BEGIN;
DELETE FROM memory_embeddings WHERE item_id = 'doc-ea98f564e23b412b9e3e9aae6f6524ec';
DELETE FROM memory_documents_fts WHERE document_id = 'doc-ea98f564e23b412b9e3e9aae6f6524ec';
DELETE FROM memory_documents WHERE document_id = 'doc-ea98f564e23b412b9e3e9aae6f6524ec';
COMMIT;"
docker restart netclaw
```

The restart matters. The daemon holds the vector index in memory and only notices its own writes. `netclaw doctor` should report `0/0 documents embedded` or a count that matches what you kept.

### Check for a duplicate

Fixing one memory doesn't stop a new one forming from the same conversation. In testing, a corrected memory and a freshly distilled one both existed a minute later, with the new one under a different title. After you fix something, search again for the topic and delete the leftover.

## Check memory health

| Command | What it shows |
|---------|---------------|
| `netclaw status` | `memory: sqlite (healthy)` or degraded |
| `netclaw stats` | Counts of anchors, documents, records and edges, pending checkpoints, memories formed and recalled this process |
| `netclaw doctor` | Checkpoint backlog (warns above 25 pending), curation model health, embeddings, relevance gate |

To see why a turn injected nothing, read the daemon log. The line is `memory_retrieval_final`, with `injectedCount`, `filteredByFloor`, `droppedByGate` and `gateScores`. Most turns inject nothing, by design.

## Troubleshooting

### Doctor says documents lack a current-model embedding

**Symptom:** `[WARN] Memory Embeddings: N of M recallable documents lack a current-model embedding.`

**Cause:** Memories written before 0.27, changed directly in the database, or written while embeddings were off or the model was unavailable.

**Fix:** Restart the daemon, which repairs the gap at startup, or run `netclaw memory backfill-embeddings` now.

### Recall seems to ignore memories you know exist

**Symptom:** The agent doesn't mention a stored fact until you ask it to search.

**Cause:** Automatic recall only injects memories that clear the similarity floor and the relevance gate. A loosely related question often injects nothing, and the agent then needs `find_memories`. In testing, a question about rolling out billing infrastructure cleared the similarity floor against a stored billing memory, but the gate scored it 0.007 against a 0.02 threshold (`droppedByGate=1`), so nothing was injected.

**Fix:** Ask directly ("check your memory for..."), or rephrase closer to the stored wording. Check `memory_retrieval_final` in the daemon log to see what was filtered.

### Embeddings never become ready

**Symptom:** `[FAIL] Memory Embeddings` or `[FAIL] Memory Relevance Gate` in doctor, and recall stays full-text.

**Cause:** The host can't reach huggingface.co, `AutoDownload` is `false` with no models in place, or a file fails its hash.

**Fix:** Follow [Run offline](#run-offline). Delete the bad model directory under `~/.netclaw/models/` so it's fetched or copied again.

## Related pages

- [Memory model](/architecture/memory-model/) - how memories form, get curated, and are recalled
- [`netclaw memory`](/cli/memory/) - the backfill command
- [Configuration reference](/configuration/reference/) - every key in `netclaw.json`
- [Upgrade netclaw](/guides/upgrading/) - what changes when you move to 0.27
- [Data directory layout](/reference/data-directory/) - where `netclaw.db` and `models/` live

## Resources

- [snowflake-arctic-embed-m](https://huggingface.co/Snowflake/snowflake-arctic-embed-m) - the default embedding model
- [ms-marco-MiniLM-L-6-v2](https://huggingface.co/Xenova/ms-marco-MiniLM-L-6-v2) - the relevance model behind the gate
- [ONNX Runtime](https://onnxruntime.ai/) - the inference runtime netclaw embeds
- [SQLite FTS5](https://www.sqlite.org/fts5.html) - the full-text search that recall combines with vectors
