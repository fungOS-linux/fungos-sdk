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
[`docs/chart.md`](docs/chart.md).

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
```

`tend` composes the SDK, the view, components, a snapshot, and the user profile
into a module, runs a fake-host preflight, and only then writes/reloads Canvas.
The preflight catches sparse child arrays, duplicate ids, invalid kinds, empty or
non-printable scene text, non-finite geometry, and malformed scene calls.

## Checks

The development loop is what every Spore author depends on, so it is checked
like code rather than trusted like a script.

```bash
lua tests/run.lua                 # the suite; plain Lua, no modules to install
lua tests/run.lua validate        # one suite by name

tend api-check --root spores      # every spore.toml must ship ui/API.md
tend <view> --snapshot <snap>     # per-view: preflight + ui/API.md gate
```

`tend api-check` is the repo-wide sweep. Because the Lua API is part of the
package ABI, a Spore with a `spore.toml` and no `ui/API.md` is a build failure —
but `spores/` has eight Spores that predate the rule, so the sweep takes a
baseline:

```bash
tend api-check --root spores --baseline tools/api-baseline.txt
```

Known-undocumented Spores are tolerated **by path**, so a new Spore without docs
fails immediately, and a Spore that gets documented drops out of the tolerated
set. `--strict-baseline` fails while that file still lists a Spore that no longer
needs it, which is what stops the ratchet slipping backwards.

CI runs the suite, composes three real example views end to end, and runs the
sweep (`.github/workflows/ci.yml`).

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
- Spore Lua API documentation contract, enforced by `tend api-check`

Bound rather than merely declared:

- `tend`'s pure half lives in `lua/fungos/tend.lua` and has a test suite
  (`tests/`), so the preflight is verified instead of assumed.
- `ui/API.md` is a gate, not a convention: CI fails a Spore that skips it.
- CI runs on every push and pull request.

Not yet implemented:

- Lua guest runtime for Spore logic
- settings Spore
- TOML profile loader (Lua profile today)
- package-level component resolution from installed Spores
