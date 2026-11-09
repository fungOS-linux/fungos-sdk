-- Deterministic fixtures for the Canvas dashboard component gallery.
-- Shapes match the shared dashboard contract: panel metrics, threshold steps,
-- table rows and time-series points. No live data or authority is involved.
--
-- Canvas supplies `module.event` and a host-stamped `module.now` on every
-- render. When the module host is driving the surface, shift the fixture phase
-- with that clock so periodic reloads animate the chart. `tend` preflight has
-- no event, so `tend check` stays deterministic.
local live_module = rawget(_G, "module")
local live = type(live_module) == "table" and type(live_module.event) == "table"
local live_phase = live and ((tonumber(live_module.now and live_module.now.epoch_ms) or 0) / 1000) or 0

local function series(count, base, amplitude, period, phase, spike_at, spike)
  local points = {}
  for index = 0, count do
    local y = base + amplitude * math.sin((index + phase + live_phase * 2.2) / period)
    if spike_at and index >= spike_at then
      local tail = math.max(0, 1 - (index - spike_at) / 10)
      y = y + spike * tail
    end
    points[#points + 1] = { x = index, y = math.max(0, y) }
  end
  return points
end

local snapshot = {
  generated = "fixture",
  stats = {
    {
      id = "throughput",
      label = "Throughput",
      value = 1240,
      unit = " req/s",
      delta = 8.4,
      status = "healthy",
      status_label = "LIVE",
    },
    {
      id = "latency",
      label = "P95 latency",
      value = 238,
      unit = " ms",
      delta = 12.0,
      delta_ink = "warning",
      status = "warning",
      status_label = "WARN",
    },
    {
      id = "errors",
      label = "Error rate",
      value = 0.42,
      decimals = 2,
      unit = "%",
      delta = -0.06,
      delta_decimals = 2,
      delta_ink = "success",
      status = "healthy",
      status_label = "OK",
    },
  },
  gauge = {
    title = "CPU pressure",
    subtitle = "host pool · 5m",
    value = 76,
    min = 0,
    max = 100,
    unit = "%",
    thresholds = {
      { value = 70, ink = "warning" },
      { value = 90, ink = "danger" },
    },
    status = "warning",
    status_label = "WARN",
  },
  table = {
    title = "Services",
    subtitle = "last 15m",
    status = "healthy",
    status_label = "UP",
    columns = {
      { key = "service", label = "Service", width = 2.2 },
      { key = "p95", label = "P95", width = 1, align = "right" },
      { key = "errors", label = "Errors", width = 1, align = "right" },
      { key = "status", label = "Status", width = 1.4, kind = "status" },
    },
    rows = {
      { service = "checkout", p95 = "238 ms", errors = "0.42%", status = "warn" },
      { service = "catalog", p95 = "164 ms", errors = "0.08%", status = "ok" },
      { service = "auth", p95 = "412 ms", errors = "1.80%", status = "crit" },
      { service = "search", p95 = "190 ms", errors = "0.21%", status = "ok" },
    },
  },
  chart = {
    title = "Request latency",
    subtitle = "p50 / p95 / p99 · incident replay",
    y_min = 0,
    y_max = 520,
    unit = " ms",
    threshold = { value = 300, label = "SLO 300ms" },
    selection = { x0 = 12, x1 = 18 },
    series = {
      { id = "p50", label = "p50", ink = "success", points = series(23, 70, 12, 5, 0) },
      { id = "p95", label = "p95", ink = "warning", points = series(23, 210, 40, 6, 2, 14, 60) },
      { id = "p99", label = "p99", ink = "danger", points = series(23, 300, 55, 5, 5, 14, 90) },
    },
  },
}

if live then
  local pulse = math.sin(live_phase * 1.7)
  snapshot.gauge.value = 76 + pulse * 2.5
  snapshot.stats[1].value = 1240 + pulse * 24
  snapshot.stats[2].value = 238 + pulse * 3
end

return snapshot
