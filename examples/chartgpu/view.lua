-- ChartGPU visual language, rendered through the same Canvas Lua scene path as
-- every other Spore. This is intentionally the Canvas-compatible counterpart of
-- examples/viz_live.lua: `tend watch` can rebuild and reload it in the browser.

local chart = require("fungos.chart")
local viz = require("fungos.viz")

local M = { name = "example.chartgpu", version = "0.1.0" }

local function chart_layer(opts)
  local c = chart.new {
    title = opts.title,
    subtitle = opts.subtitle,
    padding = { top = 42, right = 12, bottom = 44, left = 42 },
    x = { min = 0, max = 59 },
    y = { min = opts.y_min or 0, max = opts.y_max },
    legend = { position = "bottom", panel = true },
    grid = 5,
    style = {
      plot_opacity = 0.10,
      grid_opacity = 0.07,
      grid_x_opacity = 0.04,
      axis_opacity = 0.20,
      glow = 0.16,
      glow_width = 6,
      smooth_steps = 5,
    },
  }
  for _, item in ipairs(opts.series or {}) do
    if item.kind == "area" then
      c:area(item)
    else
      c:line(item)
    end
  end
  return c
end

local function line(id, label, points, color, kind)
  return {
    id = id,
    label = label,
    points = points,
    color = color,
    kind = kind or "line",
    width = 2,
    smooth = true,
    fill_opacity = 0.18,
    fill_color = color,
  }
end

function M.render(snapshot)
  snapshot = snapshot or {}
  local scene = viz.scene { width = 1200, height = 840, gap = 12 }
  local latency = snapshot.latency or {}
  local throughput = snapshot.throughput or {}
  local resources = snapshot.resources or {}
  local errors = snapshot.errors or {}
  local connections = snapshot.connections or {}

  scene:add(chart_layer {
    title = "Response latency",
    subtitle = "P50 / P95 / P99 · incident replay",
    y_max = 700,
    series = {
      line("p50", "P50", latency.p50, { 34, 197, 94 }),
      line("p95", "P95", latency.p95, { 234, 179, 8 }),
      line("p99", "P99", latency.p99, { 239, 68, 68 }),
    },
  }, { x = 0, y = 0, width = 0.62, height = 0.5 })

  scene:add(chart_layer {
    title = "Throughput",
    subtitle = "req/s · degraded by connection pressure",
    y_max = 1400,
    series = {
      line("requests", "Requests", throughput.requests, { 59, 130, 246 }, "area"),
    },
  }, { x = 0.62, y = 0, width = 0.38, height = 0.5 })

  scene:add(chart_layer {
    title = "CPU / memory",
    subtitle = "% · leak onset to recovery",
    y_max = 100,
    series = {
      line("memory", "Memory", resources.memory, { 168, 85, 247 }),
      line("cpu", "CPU", resources.cpu, { 249, 115, 22 }),
    },
  }, { x = 0, y = 0.5, width = 0.34, height = 0.5 })

  scene:add(chart_layer {
    title = "Errors",
    subtitle = "errors/s · 4xx baseline / 5xx cascade",
    y_max = 24,
    series = {
      line("e5xx", "5xx", errors.e5xx, { 239, 68, 68 }),
      line("e4xx", "4xx", errors.e4xx, { 234, 179, 8 }),
    },
  }, { x = 0.34, y = 0.5, width = 0.33, height = 0.5 })

  scene:add(chart_layer {
    title = "Connections",
    subtitle = "conns · pool saturation",
    y_max = 220,
    series = {
      line("active", "Active", connections.active, { 6, 182, 212 }, "area"),
      line("waiting", "Waiting", connections.waiting, { 236, 72, 153 }),
    },
  }, { x = 0.67, y = 0.5, width = 0.33, height = 0.5 })

  scene:render()
end

return M
