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

## Series types

`live.series` supports the same marks the portable scene vocabulary exposes:

```lua
-- line / area / scatter
live.series { label = "p95", source = "latency.p95", kind = "line" }
live.series { label = "p50", source = "latency.p50", kind = "area", fill_opacity = 0.12 }
live.series { label = "samples", source = "latency.p99", kind = "scatter" }

-- grouped bars: one mark per sample, grouped by visible bar series
live.series {
  label = "5xx", kind = "bar", source = "errors.5xx",
  stride = 4, bar_width = 0.74, bar_radius = 2, baseline = 0,
}

-- OHLC candles: close is `source` when `close_source` is omitted
live.series {
  label = "cost", kind = "candle", source = "cost.close",
  open_source = "cost.open", high_source = "cost.high",
  low_source = "cost.low", close_source = "cost.close",
  width = 6, stride = 2,
  up_color = { 34, 197, 94 }, down_color = { 239, 68, 68 },
}

-- a filled ribbon between two streams
live.series {
  label = "P50–P95", kind = "band",
  source = "latency.p95", band_source = "latency.p50",
  color = { 234, 179, 8 }, color2 = { 34, 197, 94 },
  fill_opacity = 0.14,
}

-- stacked areas: series are accumulated in declaration order
live.series {
  label = "Active", kind = "stacked_area",
  source = "connections.active", color = { 6, 182, 212 },
}
live.series {
  label = "Waiting", kind = "stacked_area",
  source = "connections.waiting", color = { 236, 72, 153 },
}
```

`stride` samples every Nth 5 Hz point. Use it for bars and candles so marks
remain legible. `baseline` defaults to zero. Bars from several visible series
are grouped in one category slot; hidden legends reflow the group.

The host exposes these resident streams:

```text
latency.p50 / latency.p95 / latency.p99
throughput
memory / cpu
errors.5xx / errors.4xx
connections.active / connections.waiting
cost.open / cost.high / cost.low / cost.close / cost
```

## History and animation

The live host samples at a fixed 5 Hz cadence into a resident 160-sample
history. A sample is immutable once emitted: advancing the clock never
recomputes old points from a new `now`. During playback the host only appends
new samples and drops the oldest.

The viewport, not the data, moves. Between two samples the host uses the real
fractional time to scroll marks left; the newest mark appears when its sample
closes. That keeps lines and candlesticks from rewriting their history every
frame while still moving smoothly at the render rate.

`seek` is the exception: a deterministic capture rebuilds the whole visible
window for the requested time. Normal playback and `tick` are append-only.

## Host

```sh
tools/viz_live.sh
```

This writes `/tmp/fungos-viz-live.json` and starts:

```text
soil-viz --live /tmp/fungos-viz-live.json --fps 60
```

The host:

- scales text by the window scale factor so Retina windows do not shrink it;
- draws a hover crosshair and per-series tooltip from the shared input pointer;
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
