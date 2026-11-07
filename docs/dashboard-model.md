# Dashboard model

`fungos-sdk` now carries a portable dashboard/data-frame contract in
`crates/fungos-sdk/src/dashboard.rs`.

The renderer does not consume Grafana JSON. It consumes this model. A Grafana
importer, a Prometheus adapter, a native stream, or Lua UI all produce the same
objects.

```text
datasource adapter ─┐
Grafana importer   ─┼─> DataFrame / Query / FieldConfig ─> scene / renderer
native streams     ─┘
```

## Core objects

```text
Dashboard   uid, title, time, refresh, variables, panels, annotations, links
Panel       id, title, kind, rect, queries, transforms, field, overrides, options
Query       ref_id, datasource, expression, range/instant, interval, max_points
DataFrame   name, ref_id, fields[], meta
Field       name, type, labels, unit, values
FieldConfig unit, decimals, min/max, thresholds, mappings, color, links
```

All types are serde-serializable and reject unknown fields. Validation is
available on the top-level objects:

- `Dashboard::validate()`
- `DataFrame::validate()`

## Time and variables

`TimeRange` carries either a relative dashboard expression (`now-6h`) or an
absolute Unix-millisecond bound. `Variable` supports query, custom, constant,
datasource, interval, textbox and ad-hoc kinds, with multi-value, include-all,
regex, sort and refresh metadata.

## Panels

The panel kind is explicit:

```text
time_series, stat, gauge, bar_gauge, table, heatmap,
status_history, logs, text, histogram, node_graph, geomap, custom
```

`PanelRect` is normalized to the dashboard surface (`0..1`). A Grafana importer
converts `gridPos` into this rect.

`PanelOptions` carries legend/tooltip/orientation/reduce/color/show-values
settings. Panel-specific options can be added as the renderer grows; the shared
model should stay rendering-agnostic.

## Field config

`FieldConfig` is where Grafana fidelity lives:

- units and decimals;
- min/max and no-value text;
- thresholds (absolute or percentage);
- value, range, regex and special mappings;
- field color mode (`series`, `continuous`, `thresholds`, `fixed`);
- data links.

`FieldOverride` applies a `FieldConfig` through a name/regex/query matcher.

## Transforms

`TransformSpec` covers the first useful subset:

```text
reduce, filter, organize, rename, merge, join, calculate,
sort, limit, labels_to_fields, rows_to_fields, series_to_rows
```

Transforms stay in the data plane. They return DataFrames; they do not create
scene nodes.

## DataFrames

`FieldValues` is typed:

```text
time    -> Vec<Option<i64>>   Unix milliseconds
number  -> Vec<Option<f64>>   finite
string  -> Vec<Option<String>>
boolean -> Vec<Option<bool>>
```

Fields in one frame must have equal lengths. A field's declared type must match
its values. Nulls are first-class.

## Grafana adapter

`grafana-import` converts Grafana dashboard JSON into this contract:

```sh
grafana-import dashboard.json --out dashboard.normalized.json
```

It imports rows, panels, targets, variables, annotations, field config,
thresholds, mappings, overrides, links and the supported transform subset.
Unsupported panels/transforms remain explicit (`custom`) and are reported as
warnings; the importer does not silently pretend they worked.

The Prometheus-over-Unibus query contract is in
[`grafana-query-contract.md`](grafana-query-contract.md).

## Example

```json
{
  "schema_version": 1,
  "uid": "fleet",
  "title": "Fleet",
  "time": {
    "from": { "kind": "relative", "expression": "now-6h" },
    "to": { "kind": "relative", "expression": "now" }
  },
  "panels": [
    {
      "id": "latency",
      "title": "Latency",
      "kind": "time_series",
      "rect": { "x": 0.0, "y": 0.0, "width": 0.5, "height": 0.5 },
      "queries": [
        {
          "ref_id": "A",
          "datasource": { "uid": "prom", "kind": "prometheus" },
          "expression": "histogram_quantile(0.95, rate(latency_bucket[$__rate_interval]))",
          "query_type": "range",
          "max_points": 2000
        }
      ],
      "field": {
        "unit": "ms",
        "decimals": 2,
        "thresholds": {
          "mode": "absolute",
          "steps": [
            { "value": null, "color": [34, 197, 94] },
            { "value": 250, "color": [245, 190, 80] },
            { "value": 500, "color": [239, 68, 68] }
          ]
        }
      }
    }
  ]
}
```

## Deliberate non-goals

This model is not Grafana's database schema. It does not include alerting rules,
RBAC, datasource administration, plugin manifests, or the internal dashboard
version/provisioning envelope. Those belong to adapters and host policy.
