-- One runtime scene, four visualization layers.
--
--   chart  top-left
--   graph  top-right
--   map    bottom-left
--   atlas  bottom-right
--
-- Every layer is an ordinary Lua value with render(surface, width, height).
-- No layer knows whether it is the only chart or one cell in a dashboard.

local chart = require("fungos.chart")
local graph = require("fungos.graph")
local map = require("fungos.map")
local atlas = require("fungos.atlas")
local viz = require("fungos.viz")

local M = {}
M.name = "example.viz"
M.version = "0.1.0"

local function chart_layer(spec)
  local c = chart.new {
    title = spec.title,
    subtitle = spec.subtitle,
    padding = { top = 34, right = 12, bottom = 28, left = 42 },
    max_points = 40,
  }
  for _, series in ipairs(spec.series or {}) do
    local kind = series.kind or "line"
    if kind == "area" then c:area(series)
    elseif kind == "scatter" then c:scatter(series)
    elseif kind == "heatmap" then c:heatmap(series)
    elseif kind == "candles" then c:candles(series)
    else c:line(series) end
  end
  return c
end

function M.render(snapshot)
  snapshot = snapshot or {}
  local scene = viz.scene { width = 1000, height = 700, gap = 10 }
  scene:add(chart_layer(snapshot.chart or { title = "Latency", subtitle = "chart layer" }), {
    x = 0, y = 0, width = 0.5, height = 0.5,
  })
  scene:add(graph.new {
    nodes = snapshot.nodes or {},
    edges = snapshot.edges or {},
    padding = 24,
  }, { x = 0.5, y = 0, width = 0.5, height = 0.5 })
  scene:add(map.new {
    center = { -20, 25 },
    zoom = 2,
    features = snapshot.features or {},
    padding = 24,
  }, { x = 0, y = 0.5, width = 0.5, height = 0.5 })
  scene:add(atlas.new {
    points = snapshot.points or {},
    density = true,
    padding = 24,
    labels = true,
  }, { x = 0.5, y = 0.5, width = 0.5, height = 0.5 })
  scene:render()
end

function M.present(snapshot)
  snapshot = snapshot or {}
  local scene = viz.scene { width = 1000, height = 700, gap = 10 }
  scene:add(chart_layer(snapshot.chart or { title = "Latency", subtitle = "chart layer" }), {
    x = 0, y = 0, width = 0.5, height = 0.5,
  })
  scene:add(graph.new { nodes = snapshot.nodes or {}, edges = snapshot.edges or {} },
    { x = 0.5, y = 0, width = 0.5, height = 0.5 })
  scene:add(map.new { center = { -20, 25 }, zoom = 2, features = snapshot.features or {} },
    { x = 0, y = 0.5, width = 0.5, height = 0.5 })
  scene:add(atlas.new { points = snapshot.points or {}, density = true, labels = true },
    { x = 0.5, y = 0.5, width = 0.5, height = 0.5 })
  return scene:present()
end

return M
