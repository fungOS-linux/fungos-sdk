---
name: tend
description: Compose, preflight, watch and reload FungOS Canvas Lua UI with tend. Use for iterating on fungos.ui components, chartgpu-style dashboards, Canvas surfaces, and browser Canvas previews.
---

# tend — Canvas module hot loop

`tend` is the external development composer for retained Canvas Lua modules. It
is not a runtime capability and must not be used from inside a Spore sandbox.

Canvas is a compositor and window manager: it arranges surfaces and exposes a
control socket. It does not define dashboard semantics. The view, panels, and
data shapes come from the SDK/Spore content layer; `tend` only composes that
content into a module Canvas can retain.

```text
view + snapshot + SDK modules + components + profile
  -> one self-contained Lua module
  -> fake-host preflight
  -> modules/<name>.lua + <name>.json
  -> optional canvasctl reload_module
```

## Fast loop

```sh
cd ~/src/fungOS/fungos-sdk

# one build + reload
lua tools/tend.lua examples/chartgpu/compact.lua \
  examples/chartgpu/snapshot.lua \
  --surface chartgpu \
  --name chartgpu

# save-triggered loop
lua tools/tend.lua watch examples/chartgpu/compact.lua \
  examples/chartgpu/snapshot.lua \
  --surface chartgpu \
  --name chartgpu \
  --watch-interval 0.25
```

`watch` polls the view, snapshot, components, `tend.lua`, and SDK modules. It
debounces changes, runs a child build, and leaves the watch alive when a build
fails. A save that lands while a build is in flight is built again rather than
being swallowed. `--no-reload` and `tend build` do not send `reload_module`.

The ChartGPU example authors in a stable 1200x840 coordinate space. Canvas scales
the retained scene into whatever surface the compositor gives it. Do not reflow
the view to the surface's native pixel size: a tall dock panel will make the
labels microscopic and the panel geometry will drift between browser and native
hosts. `view.lua` is the full `fungos.chart` reference; `compact.lua` is the
Canvas-node-budget version used by the hot loop.

## Canvas web

The browser host renders the same retained scene and is the most reliable way to
see the full dashboard while iterating. Native Canvas must be running, then:

```sh
cargo run -p canvas-web --bin canvas-web-host --features native-host
```

Open the browser Canvas surface:

```text
http://127.0.0.1:8088/?surface=chartgpu
```

The web surface polls the retained scene, so a successful `tend` reload appears
without a browser refresh. The direct scene path polls at 250 ms; the iced path
polls at 500 ms.

A native Canvas surface may be placed at the compositor's frame size (for
example, 4980x1860) while its viewer window is narrower. That is a compositor
placement, not a `tend` layout issue; use the browser URL above for a full-view
check, or place the surface in a matching compositor region.

## Useful commands

```sh
lua tools/tend.lua doctor examples/chartgpu/compact.lua --snapshot examples/chartgpu/snapshot.lua
lua tools/tend.lua check examples/chartgpu/compact.lua examples/chartgpu/snapshot.lua
lua tools/tend.lua --scene /tmp/chartgpu.json examples/chartgpu/compact.lua examples/chartgpu/snapshot.lua
lua tools/tend.lua list
```

`--scene` writes a portable `soil_scene` document, useful when Canvas itself is
not available. A check can use the same viewport as the target surface:
`tend check view.lua snapshot.lua --width 1200 --height 840`.

## Components

```sh
lua tools/tend.lua examples/components/demo.lua \
  examples/components/snapshot.lua \
  --component components/fungos.ui.lua \
  --name components-demo \
  --surface components-demo
```

A component package exports namespaced pure functions:

```lua
M.components["fungos.ui/card"] = function(ctx, props, children)
  return ui.column(props.id, {}, children)
end
```

No component gets records, network, filesystem, clock, or authority.

## Environment

| Variable | Default |
|---|---|
| `FUNGOS_SDK` | repository root |
| `FUNGOS_MODULES` | `~/Library/Application Support/Dock/canvas/modules` |
| `FUNGOS_CONFIG` | `~/.config/fungos/ui.lua` |
| `SOIL_LAYOUT` | preview layout fallback |
| `TEND_LUA` | current Lua interpreter |

## Limits

| Flag | Default | Meaning |
|---|---|---|
| `--max-nodes` | `1024` | retained scene-node ceiling; preflight fails before writing |
| `--max-bytes` | `262144` | authored module size ceiling; preflight fails before writing |
| `--width` / `--height` | `1200` / `900` | fake-host viewport used by `tend check` and `--scene` |

The current Canvas module path accepts at most 1,024 retained nodes and 256 KiB.
Older hosts may still enforce 256 nodes and 64 KiB; pass `--max-nodes` and
`--max-bytes` when targeting one. The compact ChartGPU example currently
preflights at 241 nodes and about 45 KiB.

## Failure behavior

`tend` preflights before writing, including the node and byte ceilings above. A
failed composition prints the error and exits nonzero. `tend watch` keeps
running so a syntax error does not kill the loop.

Successful writes are temp-file + rename, so a concurrent Canvas poll never sees
a half-written module. `reload_module` is treated as failed unless `canvasctl`
returns both an `ok` status and a `module_reloaded` receipt. On a reload
rejection, `tend` restores the previous module and manifest and exits nonzero;
`watch` reports the failure and keeps the last good surface alive.

## Rules

- `--surface` is required to reload Canvas; `--no-reload` keeps `watch` write-only.
- Keep the module name and surface id stable while iterating.
- Every Spore UI directory needs `API.md` unless `--allow-undocumented`.
- Use `--no-workspace` outside a `tend.lua` workspace.
- `tend` is not a Spore capability and never belongs in package grants.
