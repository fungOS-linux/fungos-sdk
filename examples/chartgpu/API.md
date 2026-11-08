# ChartGPU demo API

![ChartGPU dashboard on Canvas](screenshot.png)

## Entrypoint

`compact.lua` exports `M.render(snapshot)` and is the entrypoint used by the
Canvas hot loop. It paints five panels with retained rect nodes and stays inside
Canvas's 256-node / 64 KiB module budget.

`view.lua` is the full `fungos.chart` / `fungos.viz` reference. It is useful for
native or GPU scene hosts, but its polylines expand past the Canvas module
budget and should not be used as the `tend --surface` module without reducing
the sample count.

## Snapshot

`snapshot.lua` returns deterministic `{ x, y }` point arrays for latency,
throughput, resources, errors and connections. The shape mirrors the native
ChartGPU incident replay without requiring the Rust live host.

## Actions

None. This is a presentation-only iteration surface.

## Slots

None.

## Components

Uses `fungos.chart`, `fungos.viz`, and `fungos.ui` sub-surfaces.

## Theme/config

Uses the active `fungos.ui` theme and the ChartGPU dark palette. Canvas's Lua
fallback consumes semantic theme inks; raw RGB is retained in the portable scene
but is not used by the native compositor path.

## Hot loop

```sh
lua tools/tend.lua watch examples/chartgpu/compact.lua \
  examples/chartgpu/snapshot.lua \
  --name chartgpu --surface chartgpu --no-workspace
```

## Stable ids

`compact.lua` namespaces ids by panel prefix (`latency-`, `throughput-`,
`resources-`, `errors-`, `connections-`) and by series/column, so a reload does
not collide with the previous retained scene. `view.lua` uses `fungos.viz` layer
ids and `fungos.chart` surface namespacing.

## Authority

None. Pure presentation; no records, network, clock, filesystem or actions.
