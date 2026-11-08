# fungos-sdk

Rust and Lua SDK for fungOS Spores.

The SDK has two jobs:

1. Make Spore UI code pleasant to write and compose.
2. Make the contracts between Spore UI, Spore logic, Canvas, and Unibus explicit.

```text
fungos-sdk/
  lua/fungos/
    ui.lua        # declarative tree, host layout, scene primitives
    dashboard.lua # panel/stat/gauge/table/chart scene primitives
    compose.lua   # app + component + chrome + rice composition
    config.lua    # profile resolution
    action.lua    # action intents
    validate.lua  # preflight tree/scene validation for tend
  rust/
    crates/fungos-sdk/src/
      action.rs   # action envelopes
      scene.rs    # scene and layout types
  schemas/        # shared JSON shapes
  docs/           # composition and Lua API contract
  tools/          # tend preview/compose
  examples/
  templates/      # user-spores and user-dotfiles starting points
```

Action bars can be hand-authored or projected from a granted Canvas/DCP action
catalog with `ui.action_bar_from_catalog`. See
[`docs/action-bar.md`](docs/action-bar.md).

Charts use the same rule: `require("fungos.chart")` describes series, axes and
labels in Lua; the painter emits scene primitives. See
[`docs/chart.md`](docs/chart.md). Dashboard panels use
[`lua/fungos/dashboard.lua`](lua/fungos/dashboard.lua); the fixture-driven
[`examples/gallery`](examples/gallery) demonstrates panel chrome, stats, gauges,
tables, thresholds and time-series selection.

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
tend doctor examples/inbox.lua --snapshot examples/inbox_snapshot.lua
tend check examples/inbox.lua examples/inbox_snapshot.lua
tend examples/inbox.lua --snapshot examples/inbox_snapshot.lua --surface inbox
tend watch examples/inbox.lua examples/inbox_snapshot.lua --surface inbox --name inbox
tend build examples/gallery/view.lua examples/gallery/snapshot.lua --name gallery --out /tmp/tend-build
```

`tend` composes the SDK, the view, components, a snapshot, and the user profile
into a module, runs a fake-host preflight, and only then writes/reloads Canvas.
The preflight catches sparse child arrays, duplicate ids, invalid kinds, empty or
non-printable scene text, non-finite geometry, and malformed scene calls. It also
enforces Canvas's 256 retained-node and 64 KiB module ceilings by default;
override them with `--max-nodes` and `--max-bytes` for a different host.

## GPU scene capture

`ui.capture(width, height, theme, paint)` runs a view that uses `ui.surface` and
returns a portable `soil_scene` document plus normalized hit targets. It never
calls `canvas.rect`, `canvas.text`, or `widget.hit`.

`tend --scene /tmp/view.json` writes that document. Set `SOIL_LAYOUT` to the
`soil-layout` binary to use real Taffy geometry instead of the preview fallback:

```sh
SOIL_LAYOUT=../soil/target/debug/soil-layout \
  tend --scene /tmp/calendar.json --width 1000 --height 900 \
  examples/calendar/calendar.lua examples/calendar/live.lua
```

A host with a GPU scene renderer can present the result as a Spore-owned texture.
The Lua UI remains a pure projection; layout and pixels still belong to the host.

Build with shared components:

```bash
tend build examples/components/demo.lua examples/components/snapshot.lua \
  --component components/fungos.ui.lua \
  --name components-demo \
  --out dist/
```

For the portable dashboard/data-frame contract, see
[`docs/dashboard-model.md`](docs/dashboard-model.md). For the Grafana gap
analysis, see [`docs/grafana-gap.md`](docs/grafana-gap.md). The Prometheus over
Unibus query contract is in
[`docs/grafana-query-contract.md`](docs/grafana-query-contract.md).

See [`docs/components.md`](docs/components.md),
[`docs/package-model.md`](docs/package-model.md), and
[`docs/workspaces.md`](docs/workspaces.md).

Workspace discovery:

```bash
tend list
tend build ui/app.lua ui/snapshot.lua --name app
```

`tend.lua` declares members, components, and the default output directory.

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
- `tend` preview loop
- Rust action/scene types
- Spore Lua API documentation contract

Not yet implemented:

- Lua guest runtime for Spore logic
- settings Spore
- TOML profile loader (Lua profile today)
- package-level component resolution from installed Spores
