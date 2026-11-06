-- Lua-owned UI for the resident Rust live viz host.
--
--   tools/viz_live.sh examples/viz_live.lua
--
-- A five-panel incident dashboard in the visual language of chartgpu.io:
-- streaming latency, throughput, resources, errors and connections. The host
-- owns the 5 Hz data generator, delta-time clock and GPU rendering.

local live = require("fungos.live")

return live.scene {
  width = 1200,
  height = 840,
  gap = 12,
  fps = 30,
  layers = {
    live.chart {
      id = "latency",
      rect = { x = 0, y = 0, width = 0.62, height = 0.5 },
      title = "Response latency",
      subtitle = "P50 / P95 / P99 · live 5 Hz · incident replay",
      y_min = 0,
      y_max = 700,
      series = {
        live.series { id = "p50", label = "P50", kind = "area", source = "latency.p50", color = { 34, 197, 94 }, width = 2, fill_opacity = 0.10, smooth = true },
        live.series { id = "p95", label = "P95", source = "latency.p95", color = { 234, 179, 8 }, width = 2, smooth = true },
        live.series { id = "p99", label = "P99", source = "latency.p99", color = { 239, 68, 68 }, width = 2, smooth = true },
      },
      style = { glow = 0.18, glow_width = 7, smooth_steps = 5 },
    },
    live.chart {
      id = "throughput",
      rect = { x = 0.62, y = 0, width = 0.38, height = 0.5 },
      title = "Throughput",
      subtitle = "req/s · degraded by connection pressure",
      y_min = 0,
      y_max = 1400,
      series = {
        live.series { id = "throughput", label = "Requests", kind = "area", source = "throughput", color = { 59, 130, 246 }, color2 = { 6, 182, 212 }, width = 2, fill_opacity = 0.24, smooth = true },
      },
      style = { glow = 0.20, glow_width = 8, smooth_steps = 5 },
    },
    live.chart {
      id = "resources",
      rect = { x = 0, y = 0.5, width = 0.34, height = 0.5 },
      title = "CPU / memory",
      subtitle = "% · leak onset to recovery",
      y_min = 0,
      y_max = 100,
      series = {
        live.series { id = "memory", label = "Memory", source = "memory", color = { 168, 85, 247 }, width = 2, smooth = true },
        live.series { id = "cpu", label = "CPU", source = "cpu", color = { 249, 115, 22 }, width = 2, smooth = true },
      },
      style = { glow = 0.14, glow_width = 6, smooth_steps = 5 },
    },
    live.chart {
      id = "errors",
      rect = { x = 0.34, y = 0.5, width = 0.33, height = 0.5 },
      title = "Errors",
      subtitle = "errors/s · 4xx baseline / 5xx cascade",
      y_min = 0,
      y_max = 24,
      series = {
        live.series { id = "e5xx", label = "5xx", source = "errors.5xx", color = { 239, 68, 68 }, width = 2, smooth = true },
        live.series { id = "e4xx", label = "4xx", source = "errors.4xx", color = { 234, 179, 8 }, width = 1.5, smooth = true },
      },
      style = { glow = 0.18, glow_width = 7, smooth_steps = 5 },
    },
    live.chart {
      id = "connections",
      rect = { x = 0.67, y = 0.5, width = 0.33, height = 0.5 },
      title = "Connections",
      subtitle = "conns · pool saturation",
      y_min = 0,
      y_max = 220,
      series = {
        live.series { id = "active", label = "Active", kind = "area", source = "connections.active", color = { 6, 182, 212 }, width = 2, fill_opacity = 0.18, smooth = true },
        live.series { id = "waiting", label = "Waiting", kind = "area", source = "connections.waiting", color = { 236, 72, 153 }, width = 2, fill_opacity = 0.16, smooth = true },
      },
      style = { glow = 0.16, glow_width = 7, smooth_steps = 5 },
    },
  },
}
