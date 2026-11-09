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

## Scene document path

`ui.capture(width, height, theme, paint)` returns a versioned `soil_scene`
`Present` payload plus the view's hit targets. `ui.present(...)` is the live
counterpart: it sends that same document through the host's `canvas.present`
(or `soil.canvas.present`) and registers hits with `widget.hit` when available.
This is the Lua peer of the Rust `soil_sdk_canvas::Surface::present_scene`:
both languages describe the same scene document, with the same semantic inks
and the same view-owned geometry. Hosts without `canvas.present` keep the
legacy `ui.surface` drawing path.

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

### Documented actions

`## Actions` is machine-checked. Under that heading, list the action ids the UI
can emit in a fenced `text` block, one per line:

```text
notes.save
mail.archive
```

The prose, tables and other code fences in the section are for humans; only the
`text` block is read. `tend api-check` scans the Spore's view for a literal
first argument to `action.intent(...)` (also its `action.call` alias and
`ui.action_intent`) and fails when the view emits an id that block does not
list.

That scan is a **static approximation**, and it is worth being blunt about the
limits: an id assembled at runtime (`action.intent("mail." .. verb)`) is
invisible to it, a call spelled out inside a long string is a false positive,
and a view that emits nothing is indistinguishable from one whose emits the
scan could not read. It is a lint for the common mistake — a wired action
nobody documented — not a substitute for running the view.

Two deliberate asymmetries:

- Documented ids the view never emits are only a **warning**. A Spore may
document an action it wires conditionally.
- A file with no `## Actions` `text` block is **not checked at all**. Nearly
every API.md written before this convention has a table or `None` there, and
turning "absent" into "no actions documented" would fail all of them.

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
enforces Canvas's 1,024 retained-node and 256 KiB module ceilings by default;
override them with `--max-nodes` and `--max-bytes` for a host with a different
budget.

## Platform

`tend` is **POSIX-only**. It is a Lua script, but it shells out:

- `ls -d` expands workspace `members`/`components` globs (`tools/tend.lua`).
- `find -name spore.toml` finds the manifests for `tend api-check`.
- `command -v` backs the `doctor` probe for `canvasctl`.

The `bin/tend` and `bin/check-spores` wrappers are `sh` scripts, and the suite's
end-to-end cases use `sh` and `mkdir -p` too.

There is no Windows path, and this is not a case of "probably works": on
Windows those commands do not exist, `io.popen` returns no output, and `tend`
reports an empty workspace or a clean sweep instead of an error. Do not rely on
it there.

Making it cross-platform is a real change, not a portability tweak, because Lua
has no directory-listing API:

1. Replace the `ls -d` glob expansion and the `find` sweep with a directory walk
   that does not shell out. That needs either per-platform commands
   (`dir /b /s`), which keeps the same fragility in a second dialect; the `lfs`
   module, which is a C dependency this SDK does not have; or a small native
   helper binary, which adds a build step.
2. Add a `bin/tend.cmd` wrapper alongside the `sh` ones.
3. Make `doctor` probe for its own platform conventions instead of `command -v`.

Until then the tool is honest about being a Unix development loop.

## Checks

The development loop is what every Spore author depends on, so it is checked
like code rather than trusted like a script.

```bash
lua tests/run.lua                 # the suite; plain Lua, no modules to install
lua tests/run.lua validate        # one suite by name

tend api-check --root spores      # every spore.toml must ship ui/API.md,
                                  # and document every action its view emits
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

### Golden scenes

`tend`'s fake host is a second implementation of the host contract, so the
failure that matters here is drift: a node that quietly stops being emitted, a
renamed id, a lost hit target. `tests/golden/inbox.scene.json` is a real capture
of `examples/inbox.lua`, and the suite pins its node and hit-target ids, so that
drift fails a test instead of blanking a panel.

Capture is reproducible because `--now` fixes the injected clock:

```bash
TZ=UTC tend --scene /tmp/inbox.json --now 1794014400000 \
  examples/inbox.lua examples/inbox_snapshot.lua
```

Without `--now` the scene embeds the wall clock and two runs of the same view
disagree. Civil time stays local, because that is what a Spore rendering a clock
should see; tests pin `TZ` instead of changing the behaviour.

The comparison is structural — ids and counts, not pixels or geometry. Geometry
is layout-engine dependent, and a byte comparison would break on interpreter
differences rather than on real regressions. The committed scene is the artifact
a **host-side** test should consume: that half is what proves the imitation still
matches the original, and it can only live in the host's repository.

### Layout

`tend` lays out with a real layout command when one is available and falls back
to its own approximation otherwise. The fallback is useful, and it is **not**
Taffy, so it is never silent:

- `--layout <cmd>` (or `SOIL_LAYOUT`) runs the real layout command.
- Every capture writes `<scene>.layout.json` recording `preview`, `taffy`,
  `mixed` or `unused`, so a consumer never has to infer it from a green
  preflight.
- `tend check` warns on stderr when preview geometry was used, and `tend doctor`
  reports it as a warning.
- A layout command that exits nonzero, prints nothing, or returns something that
  is not a layout table fails the capture. Silently falling back there would mean
  a developer believes they validated geometry they never ran.

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
- The action ids in that file are checked against the view statically, so an
  action the view emits but the docs never mention fails `tend api-check`.
- CI runs on every push and pull request.

Not yet implemented:

- Lua guest runtime for Spore logic
- settings Spore
- TOML profile loader (Lua profile today)
- package-level component resolution from installed Spores
