# Live visualization

The native live path separates UI from data:

```text
Lua / fungos.live  →  live spec JSON  →  Rust host
                                         resident streams
                                         delta-time clock
                                         soil_scene + wgpu
```

Lua owns the **UI and styling**: layer placement, titles, palettes, series
labels, line widths, glow and smoothness. Rust owns the **data and frame
loop**: resident streams, delta time, geometry generation and rendering. Lua is
not called between frames and no FFI bridge carries samples.

## Spec

`fungos.live` emits plain data:

```lua
local live = require("fungos.live")

return live.scene {
  width = 1200,
  height = 840,
  gap = 12,
  fps = 60,
  layers = {
    live.chart {
      id = "latency",
      rect = { x = 0, y = 0, width = 0.5, height = 0.5 },
      title = "Live fleet latency",
      series = {
        live.series {
          label = "p50",
          source = "latency.p50",
          color = { 0, 229, 255 },
          smooth = true,
        },
      },
      style = { glow = 0.16, smooth_steps = 6 },
    },
    live.graph {
      id = "topology",
      rect = { x = 0.5, y = 0, width = 0.5, height = 0.5 },
      title = "Topology",
      node_count = 7,
    },
    live.map {
      id = "routes",
      rect = { x = 0, y = 0.5, width = 0.5, height = 0.5 },
      title = "Routes",
    },
    live.atlas {
      id = "atlas",
      rect = { x = 0.5, y = 0.5, width = 0.5, height = 0.5 },
      title = "Embedding atlas",
    },
  },
}
```

`source` names a resident Rust stream. The current demo source is synthetic
(`latency.p50`, `latency.p95`, `latency.p99`) but the binding point is explicit:
system metrics, PTY volume, network counters, audio bands or Spore events can
replace it without a Lua callback.

## Host

```sh
tools/viz_live.sh
```

This writes `/tmp/fungos-viz-live.json` and starts:

```text
soil-viz --live /tmp/fungos-viz-live.json --fps 60
```

The host:

- reads the spec once;
- ticks from `Instant` deltas, clamped so a suspended process does not jump;
- skips a frame when the next deadline has not arrived;
- reuses one wgpu device, pipeline set, glyph atlas renderer and target texture;
- hot-reloads the spec file without restarting the window.

`soil-live-frame` renders one deterministic frame:

```sh
soil-live-frame --spec /tmp/fungos-viz-live.json \
  --time 3.2 --rgba /tmp/live.rgba
```

## Why this split

A pure Lua frame generator is convenient but pays a Lua parse/eval cost per
frame and needs an external file/process bridge. A pure Rust UI would move every
style change into a release. The spec keeps both sides honest: Lua can reshape
and restyle the UI at runtime, while the hot loop stays resident Rust.
