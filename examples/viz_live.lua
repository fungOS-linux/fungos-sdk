-- Lua-owned UI for the resident Rust live viz host.
--
--   tools/viz_live.sh
--
-- This file is configuration, not a frame generator. The host owns the clock
-- and streams; editing this file hot-reloads the composition and styling.

local live = require("fungos.live")

return live.scene {
  width = 1200,
  height = 840,
  gap = 12,
  fps = 60,
  layers = {
    live.chart {
      id = "latency",
      rect = { x = 0, y = 0, width = 0.5, height = 0.5 },
      title = "Live fleet latency",
      subtitle = "resident Rust streams · real delta time",
      series = {
        live.series { id = "p50", label = "p50", kind = "area", source = "latency.p50", color = { 0, 229, 255 }, width = 2, fill_opacity = 0.16, smooth = true },
        live.series { id = "p95", label = "p95", source = "latency.p95", color = { 255, 45, 149 }, width = 2, smooth = true },
        live.series { id = "p99", label = "p99", source = "latency.p99", color = { 176, 38, 255 }, width = 2, smooth = true },
      },
      style = { glow = 0.16, glow_width = 7, smooth_steps = 6 },
    },
    live.graph {
      id = "topology",
      rect = { x = 0.5, y = 0, width = 0.5, height = 0.5 },
      title = "Topology",
      node_count = 7,
      labels = { "Canvas", "Soil", "Spore", "wasmtime", "Unibus", "Taffy", "wgpu" },
      colors = { { 0, 229, 255 }, { 0, 245, 160 }, { 255, 107, 0 } },
    },
    live.map {
      id = "routes",
      rect = { x = 0, y = 0.5, width = 0.5, height = 0.5 },
      title = "Routes",
      routes = {
        { label = "SFO→JFK", color = { 0, 229, 255 } },
        { label = "SFO→MEX", color = { 0, 245, 160 } },
        { label = "JFK→CDG", color = { 255, 211, 0 } },
        { label = "LHR→ARN", color = { 255, 45, 149 } },
      },
    },
    live.atlas {
      id = "atlas",
      rect = { x = 0.5, y = 0.5, width = 0.5, height = 0.5 },
      title = "Embedding atlas",
      labels = { "runtime", "design", "infra" },
      colors = { { 0, 229, 255 }, { 255, 45, 149 }, { 176, 38, 255 } },
    },
  },
}
