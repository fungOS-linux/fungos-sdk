#!/usr/bin/env lua
-- Dense ChartGPU scene producer.
--
-- The Lua module path is capped at 256 nodes in the running Canvas build, which
-- is why `compact.lua` samples only 16 columns per series. A Canvas `scene`
-- surface is not a Lua module: it can carry the full 1024-node scene limit and
-- the renderer draws antialiased rounded rects natively. This producer samples
-- the same fixture at 60 columns per series and sends one complete scene patch
-- per frame through canvasctl.
--
--   lua examples/chartgpu/scene_live.lua --once
--   lua examples/chartgpu/scene_live.lua --fps 4
--
-- It replaces the existing `chartgpu` surface content in place; the widget spec
-- in ~/.canvas/widgets/chartgpu.json remains available for restoring the module.

local function script_dir()
  local source = debug.getinfo(1, "S").source:sub(2)
  return source:match("^(.*)[/\\][^/\\]+$") or "."
end
local ROOT = script_dir()

local W, H = 1200, 840
local SURFACE = os.getenv("CANVAS_CHART_SURFACE") or "chartgpu"
local WORKSPACE = os.getenv("CANVAS_WORKSPACE") or "canvas-runtime"
local PATCH_PATH = os.getenv("CANVAS_SCENE_PATCH") or "/tmp/canvas-chartgpu-scene.json"
local CANVASCTL = os.getenv("CANVASCTL") or "canvasctl"

local function escape(value)
  return '"' .. tostring(value):gsub('[%z\1-\31\\"]', function(char)
    local map = { ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b',
      ['\f'] = '\\f', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }
    return map[char] or string.format('\\u%04x', char:byte())
  end) .. '"'
end

local function number(value)
  return string.format("%.5f", value)
end

local function nx(px) return -4 + 8 * px / W end
local function ny(px) return 4 - 8 * px / H end
local function sx(px) return 8 * px / W end
local function sy(px) return 8 * px / H end
local function ts(px) return px / (16 * 1.25) end

local nodes
local function emit(id, content, x, y, z, w, h)
  nodes[#nodes + 1] = string.format(
    '{"id":%s,"content":%s,"transform":{"translation":[%s,%s,%s],"rotation":[0,0,0,1],"scale":[%s,%s,1]}}',
    escape(id), content, number(nx(x)), number(ny(y)), number(z or 0), number(w), number(h))
end

local function rect(id, x, y, w, h, ink, opacity, radius, z)
  emit(id, string.format('{"kind":"rect","ink":%s,"opacity":%s,"radius":%s}',
    escape(ink), number(opacity or 1), number(radius or 0)), x, y, z or 0, sx(w), sy(h))
end

local function text(id, value, x, y, size, ink, z)
  local scale = ts(size)
  emit(id, string.format('{"kind":"text","ink":%s,"opacity":1.0,"text":%s}',
    escape(ink), escape(value)), x, y, z or 0.2, scale, scale)
end

local COLORS = {
  success = "success", warning = "warning", danger = "danger",
  primary = "primary", info = "info", muted = "muted",
}
local function series_ink(name)
  return COLORS[name] or "primary"
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

local function panel(index, x, y, w, h, spec)
  rect("panel-" .. index, x, y, w, h, "surface", 0.92, 10, -0.1)
  text("title-" .. index, spec.title, x + 14, y + 11, 14, "text")
  text("subtitle-" .. index, spec.subtitle, x + 14, y + 33, 9, "muted")
  text("live-" .. index, "LIVE", x + w - 40, y + 11, 8, "success")

  local plot_x, plot_y = x + 44, y + 58
  local plot_w, plot_h = w - 56, h - 58 - 34
  rect("plot-" .. index, plot_x, plot_y, plot_w, plot_h, "background", 0.78, 6, 0)
  for grid = 0, 2 do
    local gy = plot_y + plot_h * grid / 2
    rect("grid-" .. index .. "-" .. grid, plot_x, gy, plot_w, 1, "muted",
      grid == 2 and 0.14 or 0.07, 0, 0.1)
    local value = (spec.y_max or 1) * (1 - grid / 2)
    text("yl-" .. index .. "-" .. grid, string.format(spec.y_format or "%.0f", value),
      x + 4, gy - 4, 8, "muted")
  end
  for step = 0, 2 do
    local value = step == 2 and (spec.columns or 60) - 1 or step * 30
    text("xl-" .. index .. "-" .. step, tostring(value),
      plot_x + plot_w * step / 2 - (step == 0 and 0 or 8), plot_y + plot_h + 3, 8, "muted")
  end

  local columns = spec.columns or 60
  local col_w = plot_w / columns
  local span = math.max(0.0001, (spec.y_max or 1) - (spec.y_min or 0))
  for series_index, series in ipairs(spec.series) do
    local values = sample(series.points or {}, columns)
    local ink = series_ink(series.ink or "primary")
    for column = 1, #values do
      local value = math.max(spec.y_min or 0, math.min(spec.y_max or 1, values[column]))
      local bar_h = (value - (spec.y_min or 0)) / span * plot_h
      if bar_h > 0 then
        rect("bar-" .. index .. "-" .. series_index .. "-" .. column,
          plot_x + (column - 1) * col_w, plot_y + plot_h - bar_h,
          col_w + 0.5, bar_h, ink, 0.58, 0, 0)
      end
    end
    local lx = plot_x + (series_index - 1) * 96
    text("legend-" .. index .. "-" .. series_index, series.label or series.ink,
      lx, plot_y + plot_h + 20, 9, ink)
  end
end

local function render()
  nodes = {}
  rect("surface-bg", 0, 0, W, H, "background", 1, 0, -1)
  local now = os.time() * 1000 + math.floor((os.clock() % 1) * 1000)
  _G.module = { event = { kind = "reload" }, now = { epoch_ms = now } }
  local snapshot = assert(loadfile(ROOT .. "/snapshot.lua"))()
  local latency = snapshot.latency or {}
  local throughput = snapshot.throughput or {}
  local resources = snapshot.resources or {}
  local errors = snapshot.errors or {}
  local connections = snapshot.connections or {}

  panel(1, 0, 0, 744, 420, {
    title = "Response latency", subtitle = "P50 / P95 / P99 · incident replay",
    y_max = 700, columns = 60,
    series = {
      { label = "P99", ink = "danger", points = latency.p99 },
      { label = "P95", ink = "warning", points = latency.p95 },
      { label = "P50", ink = "success", points = latency.p50 },
    },
  })
  panel(2, 756, 0, 444, 420, {
    title = "Throughput", subtitle = "req/s · connection pressure",
    y_max = 1400, columns = 48,
    series = { { label = "Requests", ink = "primary", points = throughput.requests } },
  })
  panel(3, 0, 432, 400, 408, {
    title = "CPU / memory", subtitle = "% · leak onset", y_max = 100, columns = 44,
    series = {
      { label = "Memory", ink = "primary", points = resources.memory },
      { label = "CPU", ink = "warning", points = resources.cpu },
    },
  })
  panel(4, 412, 432, 388, 408, {
    title = "Errors", subtitle = "errors/s", y_max = 24, columns = 40,
    series = {
      { label = "4xx", ink = "warning", points = errors.e4xx },
      { label = "5xx", ink = "danger", points = errors.e5xx },
    },
  })
  panel(5, 812, 432, 388, 408, {
    title = "Connections", subtitle = "conns · pool saturation", y_max = 220, columns = 40,
    series = {
      { label = "Active", ink = "info", points = connections.active },
      { label = "Waiting", ink = "danger", points = connections.waiting },
    },
  })

  local scene = table.concat(nodes, ",")
  local patch = string.format(
    '{"schema_version":1,"workspace_id":%s,"base_revision":0,"revision":1,"operations":[{"op":"upsert_surface","surface":{"id":%s,"title":"ChartGPU · Lua scene","content":{"kind":"scene","scene":{"nodes":[%s]}},"inputs":[]}}]}',
    escape(WORKSPACE), escape(SURFACE), scene)
  local file = assert(io.open(PATCH_PATH, "wb"))
  file:write(patch)
  file:close()
  local ok = os.execute(string.format("printf 'patch %s\\n' | %s >/dev/null 2>&1", PATCH_PATH, CANVASCTL))
  if ok ~= 0 and ok ~= true then
    io.stderr:write("scene_live: canvasctl rejected the patch\n")
    os.exit(1)
  end
  print(string.format("scene_live: %d nodes, %d bytes", #nodes, #patch))
end

local args = { ... }
local fps = 0
local index = 1
while index <= #args do
  if args[index] == "--once" then
    fps = 0
  elseif args[index] == "--fps" then
    index = index + 1
    fps = tonumber(args[index]) or 4
  end
  index = index + 1
end

if fps and fps > 0 then
  local interval = 1 / fps
  while true do
    render()
    os.execute(string.format("sleep %.3f", interval))
  end
else
  render()
end
