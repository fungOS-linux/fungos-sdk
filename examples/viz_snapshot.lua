local points = {}
for index = 1, 180 do
  local x = math.sin(index * 12.9898) * 43758.5453
  x = x - math.floor(x)
  local y = math.cos(index * 7.123) * 43758.5453
  y = y - math.floor(y)
  points[#points + 1] = { x, y, ink = index % 3 == 0 and "success" or "info", label = index % 37 == 0 and "cluster" or nil }
end
local nodes = {
  { id = "a", label = "Canvas", x = -1.0, y = 0.4, ink = "primary" },
  { id = "b", label = "Soil", x = 0.4, y = 1.0, ink = "success" },
  { id = "c", label = "Spore", x = 0.7, y = -0.6, ink = "warning" },
  { id = "d", label = "wasmtime", x = -0.2, y = -1.0, ink = "danger" },
  { id = "e", label = "fungos.chart", x = -1.2, y = -0.7, ink = "info" },
}
local edges = {
  { source = "a", target = "b" }, { source = "b", target = "c" },
  { source = "c", target = "d" }, { source = "d", target = "e" },
  { source = "e", target = "a" }, { source = "a", target = "c" },
}
local features = {
  { type = "Feature", properties = { name = "route", ink = "primary" },
    geometry = { type = "LineString", coordinates = { { -120, 37 }, { -80, 40 }, { -40, 52 }, { 10, 50 } } } },
  { type = "Feature", properties = { name = "ring", ink = "success" },
    geometry = { type = "LineString", coordinates = { { -100, 10 }, { -40, -20 }, { 20, 10 }, { -20, 35 }, { -100, 10 } } } },
  { type = "Feature", properties = { name = "SFO", ink = "warning" },
    geometry = { type = "Point", coordinates = { -122.4, 37.8 } } },
  { type = "Feature", properties = { name = "NYC", ink = "warning" },
    geometry = { type = "Point", coordinates = { -74, 40.7 } } },
}
local function latency_series(offset, amplitude)
  local points = {}
  for index = 0, 119 do
    points[#points + 1] = {
      index,
      offset + math.sin(index * 0.03 + offset) * amplitude
        + math.sin(index * 0.11 + offset) * amplitude * 0.18,
    }
  end
  return points
end
return {
  chart = {
    title = "Fleet latency",
    subtitle = "chart layer · fungos.chart",
    x = { min = 0, max = 119 },
    y = { min = 0, max = 120 },
    series = {
      { id = "p50", label = "p50", color = { 0, 229, 255 }, points = latency_series(50, 16), width = 2 },
      { id = "p95", label = "p95", color = { 255, 45, 149 }, points = latency_series(62, 19), width = 2 },
      { id = "p99", label = "p99", color = { 176, 38, 255 }, points = latency_series(74, 22), width = 2 },
    },
  },
  nodes = nodes,
  edges = edges,
  features = features,
  points = points,
}
