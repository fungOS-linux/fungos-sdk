# fungos-sdk

Rust and Lua SDK for fungOS Spores.

The SDK has two jobs:

1. Make Spore UI code pleasant to write and compose.
2. Make the contracts between Spore UI, Spore logic, Canvas, and Unibus explicit.

```text
fungos-sdk/
  lua/fungos/
    ui.lua        # declarative tree, host layout, scene primitives
    compose.lua   # app + component + chrome + rice composition
    config.lua    # profile resolution
    action.lua    # action intents
    validate.lua  # preflight tree/scene validation for mush
  rust/
    crates/fungos-sdk/src/
      action.rs   # action envelopes
      scene.rs    # scene and layout types
  schemas/        # shared JSON shapes
  docs/           # composition and Lua API contract
  tools/          # mush preview/compose
  examples/
  templates/      # user-spores and user-dotfiles starting points
```

## The boundary

```text
Spore UI Lua
  snapshot + theme + viewport -> semantic tree + action intents
  no WIT, no Unibus, no filesystem, no clock

Spore logic
  WIT imports + Unibus grants -> validate/mutate -> new snapshot

Canvas
  tree -> host layout -> scene -> pixels/input

Unibus
  action catalog -> grants/approval -> Spore.act
```

## Required Lua documentation

Every Spore with a `[ui]` entry must ship `ui/API.md`. See
[`docs/lua-api-contract.md`](docs/lua-api-contract.md).

The Lua API is part of the package ABI. If another Spore, rice, or dotfile may
depend on it, document it.

## Quick start

Once the SDK is installed:

```bash
mush doctor
mush examples/inbox.lua --snapshot examples/inbox_snapshot.lua --surface md
```

`mush` composes the SDK, the view, a snapshot, and the user profile into a
preview module, runs a fake-host preflight, and only then writes/reloads Canvas.
The preflight catches sparse child arrays, duplicate ids, invalid kinds, empty or
non-printable scene text, non-finite geometry, and malformed scene calls.

## User repos

The intended user setup is two repos:

```text
user/spores     # their own Spores and component/rice packages
user/dotfiles   # ~/.config, including fungos/ui.lua and app overlays
```

`dotfiles` should be usable both in the real home directory and in the fungOS
VFS `.config`. See [`docs/user-repos.md`](docs/user-repos.md).

## Status

The first slice is deliberately narrow:

- Lua UI tree + host layout helpers
- component/slot composition
- profile resolution
- action intents
- `mush` preview loop
- Rust action/scene types
- Spore Lua API documentation contract

Not yet implemented:

- Lua guest runtime for Spore logic
- settings Spore
- TOML profile loader (Lua profile today)
- package-level component resolution from installed Spores
