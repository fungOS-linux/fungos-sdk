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
| `c:scatter(opts)` | `points`, `size`, `ink`, `label` |
| `c:bar(opts)` | `values = { number, ... }`, `labels`, `ink` |
| `c:heatmap(opts)` | `rows`, `cols`, row-major `values`, optional `ink` |

## Axes

```lua
x = { min = 0, max = 60, format = function(v) return ... end }
y = { min = 0, max = 200 }
```

`min`/`max` are inferred from the series when omitted. `padding`, `grid`,
`legend`, `max_points`, `title`, and `subtitle` are chart options.

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
Area series add a single `area` node and fill to zero.

Series above `max_points` (default 1200, override per series) are downsampled
with Largest-Triangle-Three-Buckets before projection. LTTB runs in Lua, keeps
the endpoints, and preserves the visually dominant point in each bucket. There
is no TypeScript runtime and no second chart ABI.
