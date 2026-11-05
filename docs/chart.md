# fungos.chart

`fungos.chart` is a pure Lua chart description. It emits the same scene
primitives as every other `fungos.ui` view, so it works through Canvas today and
through a native GPU scene renderer without a second chart ABI.

```lua
local chart = require("fungos.chart")

local c = chart.new {
  title = "Fleet latency",
  subtitle = "p50 / p95 · rolling 60s",
  width = 900,
  height = 520,
  x = { label = "seconds" },
  y = { label = "ms" },
}

c:line {
  id = "p50",
  label = "p50",
  ink = "success",
  width = 2,
  points = { { 0, 42 }, { 1, 44 }, { 2, 41 } },
}

c:line {
  id = "p95",
  label = "p95",
  ink = "primary",
  width = 2,
  points = { { 0, 88 }, { 1, 91 }, { 2, 84 } },
}

c:render()          -- paint through ui.surface
-- or
local present = c:present()  -- portable soil_scene document
```

## Series

| Method | Shape |
| --- | --- |
| `c:line(opts)` | `points = { {x,y}, ... }`, `ink`, `width`, `join`, `label` |
| `c:area(opts)` | line points plus `fill_opacity`; fill drops to zero |
| `c:scatter(opts)` | `points`, `size`, `ink`, `opacity`, `label` |
| `c:bar(opts)` | `values = { number, ... }`, `labels`, `ink` |
| `c:heatmap(opts)` | `rows`, `cols`, row-major `values`, optional `min`/`max` |
| `c:candles(opts)` | `candles = { {x,open,high,low,close}, ... }`, `up_ink`, `down_ink` |

## Axes

```lua
x = { min = 0, max = 60, format = function(v) return ... end }
y = { min = 0, max = 200 }
```

`min`/`max` are inferred from the series when omitted. `padding`, `grid`,
`legend`, `max_points`, `title`, `subtitle`, `crosshair`, `annotations`, and
`selection` are chart options.

```lua
local c = chart.new {
  crosshair = { x = 12, y = 48 },
  annotations = {
    { x = 9, y = 54, label = "deploy", ink = "warning" },
  },
}
```

`crosshair` is host-driven: a Spore supplies the data coordinate, the SDK draws
the guide lines and labels. `selection` is the same shape as an x/y range and
draws a translucent range box. Pointer routing still belongs to Canvas.

## Navigation

`chart.navigator` is the reusable, pure viewport model behind the live demo:

```lua
local nav = chart.navigator():set_bounds(xlo, xhi, ylo, yhi)
nav:feed { kind = "pointer", phase = "press", x = 0.2, y = 0.4 }
nav:feed { kind = "pointer", phase = "move", x = 0.5, y = 0.4 }
nav:feed { kind = "pointer", phase = "release", x = 0.5, y = 0.4 }
local x, y, crosshair, selection = nav:view()
```

Supported input:

| Input | Behavior |
| --- | --- |
| drag | pan x/y |
| wheel | zoom around pointer |
| Shift-drag | zoom to the selected x/y range |
| double press | reset zoom and pan |
| `r` / `0` / Home | reset |
| `+` / `-` | zoom in/out |
| arrows | pan |

The navigator never calls a host API. The host routes pointer, scroll and key
events; the Spore supplies data bounds and paints the returned domains.

## On-the-fly charts

Build a new chart from the current snapshot on every render. There is no chart
state in the SDK: points, series, selection and streaming windows belong to the
Spore snapshot.

```lua
function M.render(snapshot)
  local c = chart.new { title = snapshot.title }
  for _, series in ipairs(snapshot.series) do
    c:line(series)
  end
  c:render()
end
```

Line series emit a single `polyline` scene node per series. The GPU renderer
draws the stroke as quads plus native joins; `join = "miter" | "round" | "bevel"`
defaults to `round` for chart lines, with `miter_limit` limiting sharp miters.
Area series add a single `area` node and fill to zero. Scatter emits one
`points` node, heatmaps one `heatmap` node, and OHLC series one `candles` node,
so dense catalog views do not pay one scene node per mark.

Series above `max_points` (default 1200, override per series) are downsampled
with Largest-Triangle-Three-Buckets before projection. LTTB runs in Lua, keeps
the endpoints, and preserves the visually dominant point in each bucket. There
is no TypeScript runtime and no second chart ABI.


## Composition

Charts are ordinary layers. Place them beside graphs, maps and atlases with
`fungos.viz`; see [viz.md](viz.md). `chart.dashboard` remains a quick 1D/2D
chart-only grid built on the same `ui.subsurface` mechanism.

## Churn and warmup

`chart.window(points, count)` returns the newest `count` points without mutating
the snapshot. Use it for streaming charts:

```lua
local c = chart.new { max_points = 240 }
c:line { points = chart.window(snapshot.samples, 240) }
```

## Live demo

`tools/chart_animate.sh` runs the catalog against Canvas with sin/random data:

```sh
tools/chart_animate.sh
```

It writes `line`, `scatter`, `heatmap`, `dense`, and `candle` scenes under
`/tmp/fungos-chart-demo`, then `soil-scene-gpu --watch` republishes each frame.
No TypeScript runtime is involved.

The GPU producer now accepts host input over the same `ui.sock` connection:

```text
pointer press / move / release / leave
scroll x y dx dy
```

`tools/chart_live.lua` applies those events to the chart domain:

- drag to pan
- wheel to zoom around the pointer
- Shift-drag to select and zoom to a range
- double-click to reset
- `r`, `+`, `-`, and arrows from a focused producer
- move for the crosshair
- leave clears the crosshair

Chart input is still data the producer owns. Canvas owns the hit test, window
geometry and normalized coordinates; the producer never gets a window handle.
