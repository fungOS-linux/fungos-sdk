# Grafana dashboard gap analysis

Status: the first vertical is landed. The shared dashboard types are in
`crates/fungos-sdk/src/dashboard.rs`, the Grafana importer is in `grafana.rs`,
the Prometheus-over-Unibus contract is in `prometheus.rs`, and Soil has a native
`soil-grafana` preview plus a `grafana-viewer` Spore package. The actual
Prometheus adapter process and appdata/Unibus host wiring are next. Scope: what
an operational Grafana dashboard needs, how Soil's `Lua -> scene -> WGPU` stack
maps to it, and what must exist before a Grafana importer is credible.

## Recommendation

Do **not** pause GPU work wholesale. Run interop as a separate track with a hard
boundary:

```text
GPU track       resident dense buffers -> compute decimation -> 3D pipeline
Interop track   DataFrame / query / field config / variables -> Grafana adapter
```

Grafana dashboards are mostly a **control plane and data model**, not a renderer
problem. Pausing the GPU work would not shorten the interop path. Conversely,
starting with a Grafana JSON importer would bake Grafana's model into Soil before
we have a portable dashboard contract.

The order should be:

1. Shared dashboard/data-frame contract.
2. Field config, thresholds, units and overrides.
3. Time range and variables.
4. Transform pipeline.
5. Grafana JSON import for a deliberately supported subset.
6. Prometheus/Loki/SQL adapters.
7. Sharing, snapshots and embedding.

## What a Grafana dashboard actually needs

Grafana's dashboard model is wider than its panel rendering. A useful subset for
ops dashboards has these layers.

| Layer | Grafana requirements | Soil today | Status |
| --- | --- | --- | --- |
| Dashboard model | panels, rows, `gridPos`, title, tags, time, refresh, timezone, links, version, `schemaVersion` | Lua scene with explicit `rect` or auto-grid | partial |
| Layout | 24-column grid, panel resize/move, rows, collapsed rows, repeat | normalized rects and auto-grid; no rows or repeat | partial |
| Data frames | named frames, fields with type/labels/unit, wide/long series, nulls, `refId` | resident Rust streams turned directly into marks | missing |
| Queries | panel targets, datasource UID, range vs instant, interval, max points, mixed datasources | hardcoded resident streams | missing |
| Expressions | math/Reduce/Resample, server-side expressions | none | missing |
| Time | global range, relative ranges, timezone, refresh, zoom history, compare/shift | relative seconds into a local history window | partial |
| Variables | custom/query/constant/datasource/interval/textbox/adhoc; multi-value, include-all, regex, chaining | none | missing |
| Transforms | reduce, filter, organize, rename, merge, join, calculate, sort, limit, labels/rows conversions | none | missing |
| Panels | time series, stat, gauge, bar gauge, table, heatmap, status history, histogram, logs, text, node graph, geomap | line/area/scatter/bar/stacked/candle/band/histogram/dense/3D/graph/map/atlas | partial |
| Field config | unit, decimals, min/max, thresholds, mappings, color mode, no-value, display name | theme inks, series colors, widths, fills, static threshold annotations | partial |
| Overrides | match by name/regex/query, per-field config | none | missing |
| Annotations | dashboard and datasource annotations, tags, region annotations | static Lua bands/events/thresholds | partial |
| Links | data links, panel links, dashboard links, URL variables, drilldown | none | missing |
| Legend/tooltip | modes, values, sorting, shared crosshair, multi-series tooltip | wrapped legend, shared cursor, per-panel tooltip | partial |
| Alerts | Grafana-managed rules, contact points, policies, silences, alert state | none | out of scope for now |
| Sharing | snapshot, public dashboard, iframe embed, export/import JSON, image/PDF render | deterministic offscreen frame only | missing |
| Data sources | Prometheus, Loki, SQL, JSON API, CSV, TestData, Tempo, Pyroscope; auth, proxy, TLS | synthetic streams plus native system metrics | missing |
| Streaming | refresh, websocket, Loki live tail | fixed 5 Hz resident history | partial |
| Provisioning | files/API, folders, version history, library panels | Spore package + spec file | partial |
| Permissions | folders, orgs, teams, RBAC, datasource permissions | Spore grants | out of scope for now |
| Query UX | query editor, autocomplete, history, Explore, inspector | Lua-authored spec only | out of scope for now |

## Current Soil strengths

These are real and should not be thrown away:

- portable scene vocabulary rather than per-chart WGSL;
- Lua-owned layout/style with no per-frame Lua callback;
- resident Rust data and delta-time animation;
- interactive legend, linked crosshair and tooltip;
- axes with nice ticks and Y-bound fitting;
- annotations, bands and thresholds;
- 2D mark breadth: line, area, band, bars, stacked bars/areas, candles, step,
  histogram, dense line/scatter and a GPU 3D point cloud;
- resident dense buffers with a GPU compute decimation pass;
- a depth-tested 3D pipeline with a rotating camera;
- native WGPU host that can target WebGPU later;
- Spore packaging and deterministic frame capture.

The missing pieces are mostly **below** the mark renderer and **above** the
individual panel.

## Gap priority

### P0: portable dashboard contract

Before importing anything, define the objects Grafana, Prometheus and future
browser surfaces all have to share:

```text
Dashboard
  title, time, refresh, variables, panels, annotations, links

Panel
  id, title, rect, queries, transforms, field defaults, overrides, options

Query
  datasource, expression, time range, interval, max points, instant, refId

DataFrame
  name, refId, fields[]
    name, type, labels, unit, values

FieldConfig
  unit, decimals, min, max, thresholds, mappings, color, links, no_value
```

This belongs in Rust and should be serializable. Lua should author it; a Grafana
importer should produce it; the renderer should consume it.

### P1: field config and panel semantics

Without these, a dashboard imports but is not faithful:

- units and decimals;
- value mappings (value, range, regex, special);
- threshold steps and threshold-driven colors;
- field overrides by name/regex/query;
- legend modes and value formatting;
- stat, gauge, bar gauge and table panels;
- heatmap/status-history field semantics;
- logs panel with level filters and live tail.

### P1: time and variables

- global time range plus per-panel override;
- relative ranges and timezone;
- variable interpolation in queries, titles and repeat keys;
- multi-value / include-all / chained variables;
- ad-hoc filters;
- row/panel repeat.

### P1: transforms

A small, composable chain is enough for most dashboards:

```text
reduce, filter, organize, rename, merge, join, calculate,
sort, limit, labels-to-fields, rows-to-fields, series-to-rows
```

Transform results should remain DataFrames, not turn into scene nodes.

### P2: adapters

- Grafana dashboard JSON importer for the supported subset;
- Prometheus range/instant queries;
- Loki range queries and live tail;
- SQL/JSON API adapter;
- Grafana data-frame mapping;
- annotations query adapter.

### P2: sharing and delivery

- dashboard JSON export/import;
- snapshots;
- URL state for time/variables;
- embeddable browser surface;
- PNG/PDF render through the same scene;
- library panels.

### Deferred / do not clone

- Grafana's unified alerting and contact-point system;
- org/team/RBAC administration;
- datasource management UI;
- the Grafana plugin API;
- a full Explore/query-editor clone;
- Grafana's provisioning API.

Soil should integrate these where needed, or expose hooks, not reimplement them.

## Grafana import mapping

If we build the importer, the mapping should be explicit and loud:

| Grafana | Soil |
| --- | --- |
| `panels[]` / `gridPos` | dashboard panels / normalized rects |
| `targets[]` | `Query[]` with `refId` |
| `datasource` | datasource binding + adapter |
| `fieldConfig.defaults` | panel field config |
| `fieldConfig.overrides` | field override matchers |
| `thresholds.steps` | threshold config |
| `mappings` | value/range/regex mappings |
| `templating.list` | variables |
| `transformations` | transform chain |
| `annotations.list` | annotation queries |
| `time` / `timezone` / `refresh` | dashboard time model |
| unsupported panel type | named fallback + import diagnostic |

The importer must never silently drop a panel or a field config. Either the
feature is represented, the importer emits a visible diagnostic, or the import
fails.

## First interop slice

Small enough to land without blocking GPU:

1. ~~Add `DataFrame`, `FieldConfig`, `Query` and `Panel` types to the shared Rust
   model, with JSON round-trip tests.~~ Landed in `fungos-sdk`.
2. ~~Add a Grafana fixture importer for time-series + stat panels only.~~
   Landed for time series, stat, gauge, table and text, with explicit warnings
   for unsupported panels/transforms.
3. ~~Render an imported Grafana fixture with the existing scene renderer.~~
   Landed as the native `soil-grafana` preview and `grafana-viewer` Spore.
4. Add a Prometheus adapter process behind `prometheus.query.request.v1`.
5. Add appdata/Unibus host wiring to the Spore runtime.
6. Add variables and a time-range picker after the data contract is stable.

This gives a credible answer to "can the framework host a Grafana dashboard?"
without committing to all of Grafana's control plane.

## Relationship to the GPU track

The GPU boundary has landed:

```text
resident dense buffer -> GPU compute decimation -> depth-tested 3D pipeline
```

Surfaces, richer 3D materials and more decimation policies are still future
work, but the expensive architectural jump is done. It remains orthogonal to
dashboard interop: it makes Soil better than a dashboard renderer for rich UIs,
large-scale traces and 3D operational views. It is not a prerequisite for basic
Grafana-style time series.

The two tracks meet at the shared field config and DataFrame contract:

```text
Grafana / Prometheus / native streams
                |
             DataFrame
                |
      transforms + field config
                |
         scene / GPU renderer
```

Keeping that boundary explicit is the difference between a visualization
foundation and a Grafana clone.
