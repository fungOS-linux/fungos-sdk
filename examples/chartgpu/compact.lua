-- ChartGPU dashboard without the full fungos.chart stack.
--
-- Canvas caps an authored module at 64 KiB and a retained scene at 256 nodes.
-- The expressive `fungos.chart` view is useful for native/GPU hosts; this
-- compact view keeps the same five-panel visual language inside both limits.
--
-- Canvas's retained renderer has no polyline primitive, and the generic
-- polyline fallback expands to one rect per few pixels. Each series is therefore
-- a small set of filled columns: one retained rect per sample, which preserves
-- the incident shape without spending the whole node budget on one line.

local ui = require("fungos.ui")

local M = { name = "example.chartgpu.compact", version = "0.2.0" }

local C = {
  bg = { ink = "background", rgb = { 8, 12, 18 } },
  panel = { ink = "surface", rgb = { 18, 24, 32 } },
  plot = { ink = "background", rgb = { 12, 17, 24 } },
  text = { ink = "text", rgb = { 226, 234, 244 } },
  muted = { ink = "muted", rgb = { 132, 148, 166 } },
  green = { ink = "success", rgb = { 34, 197, 94 } },
  yellow = { ink = "warning", rgb = { 234, 179, 8 } },
  red = { ink = "danger", rgb = { 239, 68, 68 } },
  blue = { ink = "primary", rgb = { 59, 130, 246 } },
  cyan = { ink = "info", rgb = { 6, 182, 212 } },
  violet = { ink = "primary", rgb = { 168, 85, 247 } },
  orange = { ink = "warning", rgb = { 249, 115, 22 } },
  pink = { ink = "danger", rgb = { 236, 72, 153 } },
}

local function text_width(value, size)
  return #tostring(value or "") * size * 0.55
end

local function clamp(value, lo, hi)
  if value < lo then return lo end
  if value > hi then return hi end
  return value
end

local function sample(points, columns)
  local out = {}
  if #points == 0 then return out end
  for column = 1, columns do
    local index = 1
    if columns > 1 and #points > 1 then
      index = 1 + math.floor((column - 1) * (#points - 1) / (columns - 1) + 0.5)
    end
    out[column] = tonumber(points[index].y) or 0
  end
  return out
end

local COLUMNS = 16

local function draw_series(surface, item, x, top, width, height, y_min, y_max)
  local points = sample(item.points or {}, COLUMNS)
  if #points < 2 then return end
  local span = math.max(0.0001, y_max - y_min)
  local column_w = width / COLUMNS
  local opacity = item.opacity or 0.58
  for column = 1, #points do
    local value = clamp(points[column], y_min, y_max)
    local bar_h = (value - y_min) / span * height
    if bar_h > 0 then
      surface:rect(item.id .. "-" .. column,
        x + (column - 1) * column_w, top + height - bar_h,
        column_w + 0.6, bar_h, item.color, opacity, 0)
    end
  end
end

local function panel(parent, width, height, spec, x, y, w, h, prefix)
  local pw, ph = w * width - 12, h * height - 12
  local surface = ui.subsurface(parent, x * width, y * height, pw, ph, prefix)
  surface:rect("panel", 0, 0, pw, ph, C.panel, 0.94, 10, -0.1)
  surface:text("title", spec.title, 14, 11, 14, C.text)
  surface:text("subtitle", spec.subtitle or "", 14, 29, 9, C.muted)
  surface:text("live", "LIVE", pw - text_width("LIVE", 8) - 13, 12, 8, C.green)

  local left, top, right, bottom = 44, 48, 12, 56
  local plot_w, plot_h = math.max(16, pw - left - right), math.max(16, ph - top - bottom)
  surface:rect("plot", left, top, plot_w, plot_h, C.plot, 0.76, 7)

  local y_min, y_max = spec.y_min or 0, spec.y_max or 1
  if y_max == y_min then y_max = y_min + 1 end
  for i = 0, 2 do
    local t = i / 2
    local py = top + plot_h - t * plot_h
    surface:rect("grid-y-" .. i, left, py, plot_w, 1, C.muted, i == 0 and 0.13 or 0.07, 0)
    local value = y_min + (y_max - y_min) * t
    local label = string.format(spec.y_format or "%.0f", value)
    surface:text("yl-" .. i, label, math.max(2, left - text_width(label, 8) - 7),
      py - 4, 8, C.muted)
  end
  for _, value in ipairs({ 0, 30, 59 }) do
    local px = left + value / 59 * plot_w
    surface:text("xl-" .. value, tostring(value), px - text_width(value, 8) * 0.5,
      top + plot_h + 6, 8, C.muted)
  end

  for _, item in ipairs(spec.series or {}) do
    draw_series(surface, item, left, top, plot_w, plot_h, y_min, y_max)
  end

  local lx = 16
  for _, item in ipairs(spec.series or {}) do
    surface:text(item.id .. "-label", item.label or item.id, lx, ph - 20, 9, item.color)
    lx = lx + 30 + text_width(item.label or item.id, 9)
  end
end

function M.render(snapshot)
  snapshot = snapshot or {}
  -- Author in a stable 1200x840 coordinate space. Canvas is a compositor: it
  -- scales the retained scene to the surface. Reflowing to the surface's pixel
  -- size makes labels microscopic in a 1800px dock panel and changes panel
  -- geometry between the browser and native hosts.
  local width, height = 1200, 840
  local surface = ui.surface(width, height, ui.theme())
  surface:background(C.bg)
  local latency = snapshot.latency or {}
  local throughput = snapshot.throughput or {}
  local resources = snapshot.resources or {}
  local errors = snapshot.errors or {}
  local connections = snapshot.connections or {}

  panel(surface, width, height, {
    title = "Response latency",
    subtitle = "P50 / P95 / P99 · incident replay",
    y_max = 700,
    series = {
      { id = "p99", label = "P99", points = latency.p99 or {}, color = C.red },
      { id = "p95", label = "P95", points = latency.p95 or {}, color = C.yellow },
      { id = "p50", label = "P50", points = latency.p50 or {}, color = C.green },
    },
  }, 0, 0, 0.62, 0.5, "latency-")

  panel(surface, width, height, {
    title = "Throughput",
    subtitle = "req/s · degraded by connection pressure",
    y_max = 1400,
    series = {
      { id = "requests", label = "Requests", points = throughput.requests or {}, color = C.blue },
    },
  }, 0.62, 0, 0.38, 0.5, "throughput-")

  panel(surface, width, height, {
    title = "CPU / memory",
    subtitle = "% · leak onset to recovery",
    y_max = 100,
    y_format = "%.0f%%",
    series = {
      { id = "memory", label = "Memory", points = resources.memory or {}, color = C.violet },
      { id = "cpu", label = "CPU", points = resources.cpu or {}, color = C.orange },
    },
  }, 0, 0.5, 0.34, 0.5, "resources-")

  panel(surface, width, height, {
    title = "Errors",
    subtitle = "errors/s · 4xx baseline / 5xx cascade",
    y_max = 24,
    y_format = "%.1f/s",
    series = {
      { id = "e4xx", label = "4xx", points = errors.e4xx or {}, color = C.yellow },
      { id = "e5xx", label = "5xx", points = errors.e5xx or {}, color = C.red },
    },
  }, 0.34, 0.5, 0.33, 0.5, "errors-")

  panel(surface, width, height, {
    title = "Connections",
    subtitle = "conns · pool saturation",
    y_max = 220,
    series = {
      { id = "active", label = "Active", points = connections.active or {}, color = C.cyan },
      { id = "waiting", label = "Waiting", points = connections.waiting or {}, color = C.pink },
    },
  }, 0.67, 0.5, 0.33, 0.5, "connections-")
end

return M
