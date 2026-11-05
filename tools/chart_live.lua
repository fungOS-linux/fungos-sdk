#!/usr/bin/env lua
-- Generate live ChartGPU demo scenes without a TypeScript runtime.
--
--   lua tools/chart_live.lua --out /tmp/fungos-chart-demo --fps 30
--
-- Writes one scene per chart into --out. `soil-scene-gpu --watch` renders each
-- file and publishes new frames to Canvas at the requested frame rate.

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

local function line_scene(t)
  local p50, p95 = {}, {}
  for index = 0, 239 do
    local x = t * 4 + index - 180
    p50[#p50 + 1] = { x, wave(x, t, 0) }
    p95[#p95 + 1] = { x, wave(x, t, 1.7) + 22 + math.sin(x * 0.4 + t) * 5 }
  end
  local c = chart.new {
    title = "Live line",
    subtitle = "rolling sin data · crosshair + annotation",
    width = options.width,
    height = options.height,
    max_points = 240,
    crosshair = { x = t * 4, y = wave(t * 4, t, 0) },
    annotations = {
      { x = t * 4, y = wave(t * 4, t, 0) + 24, label = "p50 live", ink = "warning" },
    },
  }
  c:area { id = "p95", label = "p95", ink = "primary", fill_opacity = 0.10, points = p95, width = 2 }
  c:line { id = "p50", label = "p50", ink = "success", points = p50, width = 2 }
  return c:present()
end

local function scatter_scene(t)
  local points = {}
  for index = 1, 700 do
    local x = (index / 700) * 60
    local noise = math.sin(index * 12.9898 + t * 0.7) * 43758.5453
    noise = noise - math.floor(noise)
    points[#points + 1] = { x, 50 + math.sin(x * 0.33 + t) * 20 + (noise - 0.5) * 14 }
  end
  return chart.new {
    title = "Live scatter",
    subtitle = "700 points · one GPU points primitive",
    width = options.width,
    height = options.height,
  }:scatter { id = "cloud", label = "cloud", ink = "info", size = 4, opacity = 0.72, points = points }:present()
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
  return chart.new {
    title = "Live heatmap",
    subtitle = "24 x 48 scalar field · GPU heat ramp",
    width = options.width,
    height = options.height,
  }:heatmap { id = "field", rows = rows, cols = cols, values = values }:present()
end

local function dense_scene(t)
  local points = {}
  for index = 0, 1999 do
    local x = index / 1999 * 120
    local spike = (index % 911 == 0) and 16 or 0
    points[#points + 1] = { x + t * 3, 50 + math.sin(x * 0.25 + t) * 14 + spike }
  end
  return chart.new {
    title = "Live dense",
    subtitle = "2,000 samples · LTTB to 900",
    width = options.width,
    height = options.height,
    max_points = 900,
  }:area { id = "dense", label = "dense", ink = "warning", fill_opacity = 0.10, points = points, width = 2 }:present()
end

local function candle_scene(t)
  local candles = {}
  local price = 100
  for index = 1, 80 do
    local x = index
    local open = price
    local close = open + math.sin(x * 0.4 + t) * 3 + math.sin(x * 1.7 - t * 0.8) * 1.5
    local high = math.max(open, close) + 1 + math.abs(math.sin(x * 0.9 + t)) * 2
    local low = math.min(open, close) - 1 - math.abs(math.cos(x * 1.1 + t)) * 2
    candles[#candles + 1] = { x = x, open = open, high = high, low = low, close = close }
    price = close
  end
  local last = candles[#candles]
  return chart.new {
    title = "Live candles",
    subtitle = "OHLC · native candle primitive",
    width = options.width,
    height = options.height,
    crosshair = { x = last.x, y = last.close },
  }:candles { id = "ohlc", label = "OHLC", up_ink = "success", down_ink = "danger", candles = candles }:present()
end

local scenes = {
  line = line_scene,
  scatter = scatter_scene,
  heatmap = heatmap_scene,
  dense = dense_scene,
  candle = candle_scene,
}

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
