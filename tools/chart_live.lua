#!/usr/bin/env lua
-- Generate live ChartGPU demo scenes without a TypeScript runtime.
--
--   lua tools/chart_live.lua --out /tmp/fungos-chart-demo --fps 30
--
-- Writes one scene per chart into --out. `soil-scene-gpu --watch` renders each
-- file and publishes new frames to Canvas at the requested frame rate. Pointer
-- and scroll events written by the GPU producer are drained from
-- `live-<name>.input`; drag pans, wheel zooms, and move drives the crosshair.

local function script_dir()
  local source = debug.getinfo(1, "S").source:sub(2)
  return source:match("^(.*)[/\\][^/\\]+$") or "."
end

local ROOT = script_dir() .. "/.."
package.path = ROOT .. "/lua/?.lua;" .. ROOT .. "/lua/?/init.lua;" .. package.path

local chart = require("fungos.chart")
local ui = require("fungos.ui")

local options = { out = "/tmp/fungos-chart-demo", fps = 30, width = 900, height = 520 }
local index = 1
while index <= #arg do
  local key = arg[index]
  if key == "--out" then index = index + 1; options.out = arg[index]
  elseif key == "--fps" then index = index + 1; options.fps = tonumber(arg[index]) or 30
  elseif key == "--width" then index = index + 1; options.width = tonumber(arg[index]) or 900
  elseif key == "--height" then index = index + 1; options.height = tonumber(arg[index]) or 520
  else error("unknown argument " .. tostring(key)) end
  index = index + 1
end

_G.module = {
  viewport = { width = options.width, height = options.height },
  theme = { body = 16 },
}

local function json_escape(value)
  return '"' .. tostring(value):gsub('[%z\1-\31\\"]', function(char)
    local map = { ['"'] = '\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }
    return map[char] or string.format('\\u%04x', char:byte())
  end) .. '"'
end

local function json(value, array_hint)
  local kind = type(value)
  if kind == "nil" then return "null" end
  if kind == "boolean" then return value and "true" or "false" end
  if kind == "number" then
    if value ~= value or value == math.huge or value == -math.huge then error("non-finite JSON number") end
    return string.format("%.6g", value)
  end
  if kind == "string" then return json_escape(value) end
  if kind ~= "table" then error("cannot encode " .. kind .. " as JSON") end
  local array = true
  local count = 0
  for key in pairs(value) do
    count = count + 1
    if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then array = false end
  end
  if array and (count > 0 or array_hint) then
    local out = {}
    for position = 1, count do out[position] = json(value[position]) end
    return "[" .. table.concat(out, ",") .. "]"
  end
  local keys = {}
  for key in pairs(value) do keys[#keys + 1] = tostring(key) end
  table.sort(keys)
  local out = {}
  for _, key in ipairs(keys) do
    local child_hint = key == "children" or key == "nodes" or key == "hits"
    out[#out + 1] = json_escape(key) .. ":" .. json(value[key], child_hint)
  end
  return "{" .. table.concat(out, ",") .. "}"
end

local function write_atomic(path, text)
  local temporary = path .. ".tmp"
  local file = assert(io.open(temporary, "wb"))
  file:write(text)
  file:close()
  assert(os.rename(temporary, path))
end

local function wave(x, t, phase)
  return 50 + math.sin(x * 0.17 + t * 0.9 + phase) * 18
    + math.cos(x * 0.061 - t * 0.4 + phase) * 7
end

local navigators = {}

local function navigator(name)
  navigators[name] = navigators[name] or chart.navigator()
  return navigators[name]
end

local function number_field(line, key)
  return tonumber(line:match('"' .. key .. '"%s*:%s*([%-%d%.eE]+)'))
end

local function string_field(line, key)
  return line:match('"' .. key .. '"%s*:%s*"([^"]+)"')
end

local function bool_field(line, key)
  return line:match('"' .. key .. '"%s*:%s*(%a+)') == "true"
end

local function parse_event(line)
  return {
    kind = string_field(line, "kind"),
    phase = string_field(line, "phase"),
    key = string_field(line, "key"),
    x = number_field(line, "x"),
    y = number_field(line, "y"),
    dx = number_field(line, "dx"),
    dy = number_field(line, "dy"),
    at_ms = number_field(line, "at_ms"),
    shift = bool_field(line, "shift"),
  }
end

local function drain_inputs(name, bounds)
  local nav = navigator(name)
  nav:set_bounds(bounds[1], bounds[2], bounds[3], bounds[4])
  local s = navigators[name]
  local path = options.out .. "/live-" .. name .. ".input"
  local file = io.open(path, "rb")
  if not file then return end
  local text = file:read("*a") or ""
  file:close()
  local lines = {}
  for line in text:gmatch("[^\n]+") do lines[#lines + 1] = line end
  if #lines < (s.processed or 0) then s.processed = 0 end
  for index = (s.processed or 0) + 1, #lines do
    nav:feed(parse_event(lines[index]))
  end
  s.processed = #lines
end

local function view(name, xlo, xhi, ylo, yhi)
  drain_inputs(name, { xlo, xhi, ylo, yhi })
  return navigator(name):view()
end

local function scene_options(name, title, subtitle, bounds, crosshair)
  local x, y, cross, selection = view(name, bounds[1], bounds[2], bounds[3], bounds[4])
  return {
    title = title,
    subtitle = subtitle,
    width = options.width,
    height = options.height,
    x = x,
    y = y,
    crosshair = crosshair or cross,
    selection = selection,
  }
end

local function points_bounds(series)
  local xlo, xhi, ylo, yhi = math.huge, -math.huge, math.huge, -math.huge
  for _, points in ipairs(series) do
    for _, point in ipairs(points) do
      xlo, xhi = math.min(xlo, point[1]), math.max(xhi, point[1])
      ylo, yhi = math.min(ylo, point[2]), math.max(yhi, point[2])
    end
  end
  return { xlo, xhi, ylo, yhi }
end

local function line_scene(t)
  local p50, p95 = {}, {}
  for index = 0, 239 do
    local x = t * 4 + index - 180
    p50[#p50 + 1] = { x, wave(x, t, 0) }
    p95[#p95 + 1] = { x, wave(x, t, 1.7) + 22 + math.sin(x * 0.4 + t) * 5 }
  end
  local c = chart.new(scene_options("line", "Live line",
    "drag pan · wheel zoom · shift-drag range · double-click reset",
    points_bounds({ p50, p95 })))
  local cross = c.opts.crosshair
  if cross then
    c.opts.annotations = {
      { x = cross.x, y = cross.y + 24, label = "p50 live", ink = "warning" },
    }
  end
  c:area { id = "p95", label = "p95", ink = "primary", fill_opacity = 0.10, points = p95, width = 2 }
  c:line { id = "p50", label = "p50", ink = "success", points = p50, width = 2 }
  return c:present()
end

local function scatter_scene(t)
  local points = {}
  local xlo, xhi, ylo, yhi = math.huge, -math.huge, math.huge, -math.huge
  for index = 1, 700 do
    local x = (index / 700) * 60
    local noise = math.sin(index * 12.9898 + t * 0.7) * 43758.5453
    noise = noise - math.floor(noise)
    local y = 50 + math.sin(x * 0.33 + t) * 20 + (noise - 0.5) * 14
    points[#points + 1] = { x, y }
    xlo, xhi = math.min(xlo, x), math.max(xhi, x)
    ylo, yhi = math.min(ylo, y), math.max(yhi, y)
  end
  local opts = scene_options("scatter", "Live scatter",
    "drag pan · wheel zoom · shift-drag range", { xlo, xhi, ylo, yhi })
  return chart.new(opts):scatter {
    id = "cloud", label = "cloud", ink = "info", size = 4, opacity = 0.72, points = points,
  }:present()
end

local function heatmap_scene(t)
  local rows, cols = 24, 48
  local values = {}
  for row = 0, rows - 1 do
    for col = 0, cols - 1 do
      local x, y = col / cols, row / rows
      values[#values + 1] = math.sin(x * 14 + t * 1.3) + math.cos(y * 18 - t * 0.9)
        + 0.5 * math.sin((x + y) * 10 + t)
    end
  end
  local opts = scene_options("heatmap", "Live heatmap",
    "drag pan · wheel zoom · shift-drag range · GPU heat ramp", { 0, cols - 1, 0, rows - 1 })
  return chart.new(opts):heatmap { id = "field", rows = rows, cols = cols, values = values }:present()
end

local function dense_scene(t)
  local points = {}
  local xlo, xhi, ylo, yhi = math.huge, -math.huge, math.huge, -math.huge
  for index = 0, 1999 do
    local x = index / 1999 * 120 + t * 3
    local spike = (index % 911 == 0) and 16 or 0
    local y = 50 + math.sin(x * 0.25 + t) * 14 + spike
    points[#points + 1] = { x, y }
    xlo, xhi = math.min(xlo, x), math.max(xhi, x)
    ylo, yhi = math.min(ylo, y), math.max(yhi, y)
  end
  local opts = scene_options("dense", "Live dense",
    "2,000 samples · LTTB · drag pan · wheel zoom", { xlo, xhi, ylo, yhi })
  opts.max_points = 900
  return chart.new(opts):area {
    id = "dense", label = "dense", ink = "warning", fill_opacity = 0.10, points = points, width = 2,
  }:present()
end

local function candle_scene(t)
  local candles = {}
  local price = 100
  local ylo, yhi = math.huge, -math.huge
  for index = 1, 80 do
    local x = index
    local open = price
    local close = open + math.sin(x * 0.4 + t) * 3 + math.sin(x * 1.7 - t * 0.8) * 1.5
    local high = math.max(open, close) + 1 + math.abs(math.sin(x * 0.9 + t)) * 2
    local low = math.min(open, close) - 1 - math.abs(math.cos(x * 1.1 + t)) * 2
    candles[#candles + 1] = { x = x, open = open, high = high, low = low, close = close }
    ylo, yhi = math.min(ylo, low), math.max(yhi, high)
    price = close
  end
  local last = candles[#candles]
  local opts = scene_options("candle", "Live candles",
    "OHLC · drag pan · wheel zoom · double-click reset", { 1, #candles, ylo, yhi },
    { x = last.x, y = last.close })
  return chart.new(opts):candles {
    id = "ohlc", label = "OHLC", up_ink = "success", down_ink = "danger", candles = candles,
  }:present()
end

local scenes = {
  line = line_scene,
  scatter = scatter_scene,
  heatmap = heatmap_scene,
  dense = dense_scene,
  candle = candle_scene,
}

for name in pairs(scenes) do
  os.remove(options.out .. "/live-" .. name .. ".input")
end

local frame = 0
while true do
  local t = frame / math.max(1, options.fps)
  for name, build in pairs(scenes) do
    local present = build(t)
    write_atomic(options.out .. "/live-" .. name .. ".json", json(present))
  end
  frame = frame + 1
  os.execute(string.format("sleep %.3f", 1 / math.max(1, options.fps)))
end
