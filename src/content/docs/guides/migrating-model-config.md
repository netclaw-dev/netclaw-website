---
title: "Migrating Model Configuration"
description: "Move Models.Main / Fallback / Compaction to named definitions and roles, with rollback."
---

Netclaw used to store each model role as an inline object under `Models`. It now stores models as named **definitions** and points **roles** at them by name, so switching a role no longer discards that model's context window and modality overrides.

Definitions and roles arrived in netclaw 0.25.0. Your old config still works there, and upgrading doesn't rewrite anything. Migrate when you're ready — or don't, until the first write to model config migrates the file for you.

## Before You Begin

- An inline `Models` section in `~/.netclaw/config/netclaw.json`. Open the file to check — `netclaw model list` renders both shapes identically.
- No legacy `NETCLAW_Models__Main__*`, `__Fallback__*`, or `__Compaction__*` variables exported anywhere the daemon can see them. They block migration outright — [convert them first](#converting-environment-variables).
- A way to restart the daemon once you're done.

## The two shapes

Legacy — each role carries its own copy of the model:

```json
{
  "Models": {
    "Main": { "Provider": "remote-gpu", "ModelId": "qwen3:30b", "ContextWindow": 32768 },
    "Fallback": { "Provider": "remote-gpu", "ModelId": "qwen3:8b" }
  }
}
```

Canonical — models are described once, roles reference them:

```json
{
  "Models": {
    "Definitions": {
      "remote-gpu-qwen3-30b": { "Provider": "remote-gpu", "ModelId": "qwen3:30b", "ContextWindow": 32768 },
      "remote-gpu-qwen3-8b": { "Provider": "remote-gpu", "ModelId": "qwen3:8b" }
    },
    "Roles": {
      "Main": "remote-gpu-qwen3-30b",
      "Fallback": "remote-gpu-qwen3-8b"
    }
  }
}
```

Never both. A `Models` section holding inline roles *and* `Definitions`/`Roles` is rejected — netclaw won't guess which one you meant.

## What triggers migration

| Action | Migrates? |
|--------|-----------|
| Upgrading netclaw | No |
| Starting the daemon | No |
| `netclaw model list`, `netclaw status` | No — reads don't write |
| `netclaw model set` | **Yes** |
| `netclaw model clear` | **Yes**, when the role was actually set — clearing an unset role writes nothing |
| The model-manager TUI assigning a role | **Yes** |
| `netclaw doctor --fix` | **Yes** |

Reading a legacy config leaves it byte-for-byte alone. The first write converts the whole `Models` section, not just the part you touched.

## Migrating

Run any model write, or do it deliberately:

```bash
netclaw doctor --fix -y
```

:::caution
`doctor --fix` prompts `Apply these fixes? [y/N]:` and **defaults to no**. In a script or a pipe, omitting `-y` means nothing gets migrated.
:::

Migration is deterministic. It preserves each role's provider, model ID, context window, modalities, and provenance, and names definitions `<provider>-<model-id>`. Roles that pointed at identical models collapse into one shared definition:

```json
{
  "Models": {
    "Definitions": {
      "remote-gpu-qwen3-30b": { "Provider": "remote-gpu", "ModelId": "qwen3:30b", "ContextWindow": 32768 },
      "remote-gpu-qwen3-8b": { "Provider": "remote-gpu", "ModelId": "qwen3:8b", "Provenance": "Manual" }
    },
    "Roles": {
      "Main": "remote-gpu-qwen3-30b",
      "Fallback": "remote-gpu-qwen3-8b",
      "Compaction": "remote-gpu-qwen3-8b"
    }
  }
}
```

Fallback and Compaction share one definition here because they were the same model. Editing it now moves both. Split them into separate definitions if you want them to drift apart.

Confirm the result:

```bash
netclaw model list
```

The table should read exactly as it did before. Then restart the daemon — `netclaw daemon stop && netclaw daemon start`, or `systemctl --user restart netclaw` under systemd.

## Rolling back

Migration first copies `netclaw.json` to `~/.netclaw/config/netclaw.json.legacy-models.bak` — a complete snapshot of the file as it stood, not just the `Models` section. It's written once and never overwritten, so a second migration won't clobber your original.

An older netclaw binary can't read the canonical shape. To downgrade, restore the backup **before** installing the old version:

```bash
cp ~/.netclaw/config/netclaw.json.legacy-models.bak ~/.netclaw/config/netclaw.json
netclaw daemon stop && netclaw daemon start
netclaw model list    # confirm the roles read as they did before
```

## Converting environment variables

Legacy `NETCLAW_Models__Main__*` variables still work by themselves. But while any of them is set, migration fails rather than proceeding — after a restart you'd have a canonical file and legacy variables fighting over the same roles, which is exactly the mixed shape netclaw rejects everywhere else.

The same variable also makes `netclaw doctor` unusable for unrelated fixes, so it's worth clearing out regardless.

Convert them first. Before:

```bash
export NETCLAW_Models__Main__Provider="openrouter"
export NETCLAW_Models__Main__ModelId="anthropic/claude-sonnet-4"
export NETCLAW_Models__Main__ContextWindow="200000"
```

After:

```bash
export NETCLAW_Models__Definitions__claude__Provider="openrouter"
export NETCLAW_Models__Definitions__claude__ModelId="anthropic/claude-sonnet-4"
export NETCLAW_Models__Definitions__claude__ContextWindow="200000"
export NETCLAW_Models__Roles__Main="claude"
```

The definition name (`claude`) is yours; it just has to match on both sides. Unset the old variables before migrating — check your shell profile, your Docker env file, and any [`Environment=` or `EnvironmentFile=`](https://www.freedesktop.org/software/systemd/man/systemd.exec.html#Environment=) lines in a systemd unit.

## Troubleshooting

### `Legacy model roles conflict for <provider>/<model>`

Two legacy roles name the same provider and model ID but disagree on metadata — different `ContextWindow` values, say. Migration can't merge them into one definition and won't pick a winner.

Make the roles agree, then migrate:

```json
{
  "Models": {
    "Main": { "Provider": "remote-gpu", "ModelId": "qwen3:8b", "ContextWindow": 32768 },
    "Fallback": { "Provider": "remote-gpu", "ModelId": "qwen3:8b", "ContextWindow": 32768 }
  }
}
```

If they genuinely need different windows, they're different definitions — migrate by hand and give them separate names.

### `Cannot migrate Models while legacy environment override ... is set`

A `NETCLAW_Models__Main__*`, `__Fallback__*`, or `__Compaction__*` variable is still exported. [Convert it](#converting-environment-variables) and try again. Check the daemon's environment too, not just your shell — systemd units and Docker env files are the usual culprits.

### `Models:Roles:<role> references unknown definition '<name>'`

A role names a definition that isn't there, usually after a rename. Migration doesn't cause this and can't fix it. Open `netclaw.json`, compare `Roles` against `Definitions`, and make the names match.

### `Models configuration mixes legacy inline roles with named Definitions/Roles`

The `Models` section has both shapes. Delete whichever one you don't want — keep `Definitions`/`Roles` if it's complete — and re-run.

### `Models:<role> must explicitly declare Provider and ModelId before migration`

A legacy role leaned on schema defaults instead of naming its provider and model. Write them out explicitly, then migrate.

## What's next

Once the file is migrated, overrides live on the definition, so [`netclaw model set`](/cli/model/#model-set) stops throwing away a model's context window every time you reassign a role. [Models configuration](/configuration/models/) covers the shape you now have.

## Related pages

- [Models configuration](/configuration/models/) — the canonical shape, field by field
- [`netclaw model`](/cli/model/) — the CLI that writes it
- [`netclaw doctor`](/cli/doctor/) — validation and `--fix`
- [Managed Providers](/configuration/managed-providers/) — providers your definitions reference

## Resources

- [.NET environment variable configuration](https://learn.microsoft.com/en-us/dotnet/core/extensions/configuration-providers#environment-variable-configuration-provider) — the `__` nesting convention netclaw follows
- [netclaw configuration spec](https://github.com/netclaw-dev/netclaw/blob/dev/docs/spec/configuration.md) — the upstream reference for the `Models` section
