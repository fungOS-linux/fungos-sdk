# Grafana query path over Unibus

The viewer does not talk to Prometheus directly. It publishes a bounded query
request and consumes matching result frames. The adapter owns HTTP, TLS,
credentials and datasource configuration.

## Existing adapter check

The current Unibus-side Prometheus support is a **scalar widget collector**
(`unibus-widget-source` / `canvas-prometheus-feed.py`), not a general PromQL
range-query gateway. It selects exact series from configured commands or emits
one scalar snapshot. It is useful, but it cannot serve a Grafana time-series
dashboard.

So the path needs a small adapter with a query contract. This is that contract.

## Request

```text
kind: prometheus.query.request.v1
```

```json
{
  "request_id": "dashboard-fleet-latency-A-1700000000",
  "datasource": { "uid": "prom", "kind": "prometheus" },
  "panel_id": "latency",
  "ref_id": "A",
  "expression": "histogram_quantile(0.95, rate(latency_bucket[$__rate_interval]))",
  "start_ms": 1700000000000,
  "end_ms": 1700003600000,
  "step_ms": 15000,
  "max_points": 2000,
  "instant": false
}
```

Rules:

- `request_id` is caller-generated and unique for the request lifetime.
- `datasource` is an adapter-local identity. Never a URL, bearer token, or
  certificate path.
- `expression` is the PromQL text after dashboard variable interpolation.
- `step_ms` and `max_points` bound the result. The adapter may coarsen the step.
- `instant = true` is a single point.
- The adapter must reject malformed, over-budget, or unsupported requests
  loudly.

## Result

```text
kind: prometheus.query.result.v1
```

```json
{
  "request_id": "dashboard-fleet-latency-A-1700000000",
  "frames": [
    {
      "name": "latency",
      "ref_id": "A",
      "fields": [
        {
          "name": "time",
          "type": "time",
          "values": { "type": "time", "values": [1700000000000] }
        },
        {
          "name": "p95",
          "type": "number",
          "labels": { "instance": "neo" },
          "unit": "ms",
          "values": { "type": "number", "values": [212.4] }
        }
      ],
      "meta": {}
    }
  ],
  "error": null,
  "elapsed_ms": 38
}
```

Rules:

- Frames use the shared `DataFrame` contract in `fungos-sdk`.
- An error result carries no frames. A successful result carries at least one.
- Missing samples are `null`, never zero.
- The caller correlates `request_id`, `panel_id`, and `ref_id`; do not rely on
  frame order.
- A cancelled/expired request is an error result or no result with explicit
  staleness handling, not an empty success.

## Discovery

The adapter advertises a Mycelium service (`kind = "prometheus"`) or an Unibus
adapter catalog entry with message kinds:

```text
prometheus.query.request.v1
prometheus.query.result.v1
```

The Spore selects a reviewed datasource id from appdata/config. It never scans
the network or chooses an endpoint itself.

## Appdata layout

Synced, per-app, per-user:

```text
dashboards/{uid}       normalized dashboard JSON
settings/grafana       datasource selection and variable defaults
snapshots/{uid}        optional last-known-good frame cache
```

Local-only:

```text
cache/queries/{hash}   short-lived query result cache
```

Use `save_if_generation` for dashboard edits so a second device edits against a
known generation. A conflict is presented, not overwritten.

## Adapter ownership

A minimal adapter can be a separate process:

```text
Unibus poll(request) -> Prometheus /api/v1/query_range -> Unibus publish(result)
```

It must enforce:

- per-datasource request budgets and concurrency;
- time range and max-point limits;
- no arbitrary URLs from the bus;
- credentials only in the adapter's private config;
- explicit error frames for HTTP/TLS/parse failures;
- cancellation when the request TTL expires.

This keeps `soil:unibus` as the Spore-facing authority boundary. `soil:mycelium`
can supply the service target and identity, but it should not become the
Prometheus query API.
