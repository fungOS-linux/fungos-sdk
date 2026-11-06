# fungos.viz

`fungos.viz` composes visualization layers at runtime on one Canvas surface.

A layer is any table with:

```lua
layer:render(surface, width, height)
```

Charts, graphs, maps, atlases and ordinary `fungos.ui` surfaces all satisfy that
shape. The scene owns placement and sub-surfaces; it does not know what the
layers mean.

```lua
local viz = require("fungos.viz")
local chart = require("fungos.chart")
local graph = require("fungos.graph")
local map = require("fungos.map")
local atlas = require("fungos.atlas")

local scene = viz.scene { width = 1000, height = 700, gap = 10 }
scene:add(chart.new { title = "Latency" }:line { points = points },
  { x = 0, y = 0, width = 0.5, height = 0.5 })
scene:add(graph.new { nodes = nodes, edges = edges },
  { x = 0.5, y = 0, width = 0.5, height = 0.5 })
scene:add(map.new { center = { -20, 25 }, zoom = 2, features = features },
  { x = 0, y = 0.5, width = 0.5, height = 0.5 })
scene:add(atlas.new { points = points, density = true },
  { x = 0.5, y = 0.5, width = 0.5, height = 0.5 })
scene:render()
```

Each child gets a `ui.subsurface`, so it draws in local pixels while the scene
maps it into a parent cell. Child scene IDs are prefixed automatically.

## Layers

| Module | Layer |
| --- | --- |
| `fungos.chart` | axes, series, annotations, crosshair |
| `fungos.graph` | nodes, edges, labels, grouped inks |
| `fungos.map` | GeoJSON lines, polygons, points, graticule |
| `fungos.atlas` | density heatmap, point cloud, labels |
| `fungos.ui` | any ordinary UI surface |

Layout is normalized:

```lua
{ x = 0.0, y = 0.0, width = 0.5, height = 0.5 }
```

Composition is presentation-only. Every layer remains in the same no-authority
Lua sandbox; no layer gains host authority by being composed.

## Native Soil window

`soil-viz` renders the composed scene in a native winit window using wgpu. It
does not start Canvas or a Spore runtime; this is Soil owning the host.

```sh
cargo build -p soil-scene-gpu --bin soil-viz
```

Then:

```sh
tools/viz_window.sh
```

The script captures `examples/viz.lua` + `examples/viz_snapshot.lua` into one
scene and opens it with `--watch`, so re-running `tend --scene` updates the
window.

The same scene can be rendered offscreen for screenshots:

```sh
tend --scene /tmp/viz.json --width 1200 --height 840 \
  examples/viz.lua examples/viz_snapshot.lua
soil-scene-gpu --scene /tmp/viz.json --canvas-socket /tmp/unused \
  --source-id viz --size 1200x840 --rgba /tmp/viz.rgba
```

## Live native host

For a resident Rust animation loop driven by a Lua-owned spec, see
[live.md](live.md). `fungos.viz` composes a scene now; `fungos.live` configures
a persistent native host that samples Rust streams and advances by real delta
time.
