-- fungos.chart — declarative charts on the same scene surface as every Spore.
--
--   local chart = require("fungos.chart")
--   local c = chart.new { title = "Latency", width = 900, height = 520 }
--   c:line { id = "p95", points = points, ink = "primary", width = 2 }
--   c:render()
--
-- The module is pure: the caller supplies points and the host supplies viewport,
-- theme and layout. Lines are emitted as bounded scene primitives today; a
-- native chart pipeline can replace the painter without changing this API.

local ui = require("fungos.ui")

local chart = {}
chart.version = "0.1.0"

local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for key, item in pairs(value) do out[key] = copy(item) end
  return out
end

local function merge(base, override)
  if type(override) ~= "table" then return base end
  for key, value in pairs(override) do
    if type(value) == "table" and type(base[key]) == "table" then
      merge(base[key], value)
    else
      base[key] = copy(value)
    end
  end
  return base
end

chart.copy = copy
chart.merge = merge

chart.defaults = {
  width = 900,
  height = 520,
  padding = { top = 38, right = 20, bottom = 36, left = 52 },
  grid = 5,
  legend = true,
  max_points = 1200,
  title = nil,
  subtitle = nil,
  x = { label = nil, min = nil, max = nil, format = nil },
  y = { label = nil, min = nil, max = nil, format = nil },
}

local methods = {}
chart.methods = methods

--- Create a chart. `opts` is copied, never mutated.
function chart.new(opts)
  opts = merge(copy(chart.defaults), opts or {})
  return setmetatable({
    opts = opts,
    series = {},
  }, { __index = methods })
end

local function point_xy(point)
  if type(point) == "table" then
    return tonumber(point.x or point[1]) or 0, tonumber(point.y or point[2]) or 0
  end
  return 0, 0
end

local function series_points(item)
  local out = {}
  for _, point in ipairs(item.points or {}) do
    local x, y = point_xy(point)
    out[#out + 1] = { x = x, y = y }
  end
  return out
end

--- Largest-Triangle-Three-Buckets downsampling.
--
-- Keeps endpoints and the visually dominant point in each bucket. The returned
-- points are references to the input, so callers must not mutate them.
local function lttb(data, threshold)
  local count = #data
  if threshold >= count or threshold < 3 then return data end
  local sampled = { data[1] }
  local every = (count - 2) / (threshold - 2)
  local anchor = 1
  for bucket = 1, threshold - 2 do
    local range_start = math.floor((bucket - 1) * every) + 2
    local range_end = math.min(math.floor(bucket * every) + 2, count - 1)
    local avg_start = math.floor(bucket * every) + 2
    local avg_end = math.min(math.floor((bucket + 1) * every) + 2, count)
    local avg_x, avg_y, avg_n = 0, 0, 0
    for index = avg_start, avg_end do
      avg_x = avg_x + data[index].x
      avg_y = avg_y + data[index].y
      avg_n = avg_n + 1
    end
    if avg_n > 0 then avg_x, avg_y = avg_x / avg_n, avg_y / avg_n end
    local ax, ay = data[anchor].x, data[anchor].y
    local best_area, best_index = -1, range_start
    for index = range_start, range_end do
      local area = math.abs((ax - avg_x) * (data[index].y - ay)
        - (ax - data[index].x) * (avg_y - ay)) * 0.5
      if area > best_area then best_area, best_index = area, index end
    end
    sampled[#sampled + 1] = data[best_index]
    anchor = best_index
  end
  sampled[#sampled + 1] = data[count]
  return sampled
end

chart.lttb = lttb

--- Add a line series. `points` is `{ {x=,y=}, ... }` or `{ {x,y}, ... }`.
function methods:line(opts)
  opts = copy(opts or {})
  opts.kind = "line"
  opts.ink = opts.ink or "primary"
  opts.width = opts.width or 2
  opts.join = opts.join or "round"
  opts.miter_limit = opts.miter_limit or 4.0
  opts.points = series_points(opts)
  self.series[#self.series + 1] = opts
  return self
end

--- Add a filled area series. The line is drawn over the fill by render().
function methods:area(opts)
  opts = copy(opts or {})
  opts.kind = "area"
  opts.ink = opts.ink or "primary"
  opts.width = opts.width or 2
  opts.fill_opacity = opts.fill_opacity or 0.16
  opts.join = opts.join or "round"
  opts.miter_limit = opts.miter_limit or 4.0
  opts.points = series_points(opts)
  self.series[#self.series + 1] = opts
  return self
end

--- Add a scatter series.
function methods:scatter(opts)
  opts = copy(opts or {})
  opts.kind = "scatter"
  opts.ink = opts.ink or "primary"
  opts.size = opts.size or 3
  opts.points = series_points(opts)
  self.series[#self.series + 1] = opts
  return self
end

--- Add a bar series. `values` is `{ number, ... }`; `labels` is optional.
function methods:bar(opts)
  opts = copy(opts or {})
  opts.kind = "bar"
  opts.ink = opts.ink or "primary"
  opts.values = opts.values or {}
  self.series[#self.series + 1] = opts
  return self
end

--- Add a heatmap. `values` is row-major, `rows * cols` entries.
function methods:heatmap(opts)
  opts = copy(opts or {})
  opts.kind = "heatmap"
  opts.rows = opts.rows or 1
  opts.cols = opts.cols or #(opts.values or {})
  opts.values = opts.values or {}
  self.series[#self.series + 1] = opts
  return self
end

local function finite(value)
  return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function bounds(series, axis)
  local lo, hi
  for _, item in ipairs(series) do
    if item.kind == "heatmap" then
      lo, hi = 0, math.max(1, (item.rows or 1) - 1)
    elseif item.kind == "bar" then
      for index, value in ipairs(item.values or {}) do
        value = tonumber(value) or 0
        lo = lo and math.min(lo, math.min(0, value)) or math.min(0, value)
        hi = hi and math.max(hi, value) or value
        lo = lo and math.min(lo, index) or index
        hi = hi and math.max(hi, index) or index
      end
    else
      for _, point in ipairs(item.points or {}) do
        local value = axis == "x" and point.x or point.y
        if finite(value) then
          lo = lo and math.min(lo, value) or value
          hi = hi and math.max(hi, value) or value
        end
      end
    end
  end
  if not lo or not hi or lo == hi then
    lo, hi = lo or 0, hi or 1
    if lo == hi then hi = lo + 1 end
  end
  return lo, hi
end

local function nice_ticks(lo, hi, count)
  local span = hi - lo
  if span <= 0 then return { lo } end
  local raw = span / math.max(1, count)
  local magnitude = 10 ^ math.floor(math.log(raw, 10))
  local step = magnitude
  for _, candidate in ipairs({ 1, 2, 2.5, 5, 10 }) do
    if raw <= candidate * magnitude then step = candidate * magnitude break end
  end
  local first = math.floor(lo / step) * step
  local last = math.ceil(hi / step) * step
  local out = {}
  local value = first
  while value <= last + step * 0.5 and #out < 64 do
    out[#out + 1] = value
    value = value + step
  end
  return out
end

local function format_number(value)
  if not finite(value) then return "" end
  local abs = math.abs(value)
  if abs >= 1000000 then return string.format("%.1fM", value / 1000000) end
  if abs >= 1000 then return string.format("%.1fk", value / 1000) end
  if abs >= 10 then return string.format("%.0f", value) end
  if abs >= 1 then return string.format("%.1f", value) end
  return string.format("%.2f", value)
end

local function ink_for(item, value, lo, hi)
  if item.ink then return item.ink end
  local t = ((tonumber(value) or 0) - lo) / math.max(0.0001, hi - lo)
  if t >= 0.75 then return "danger" end
  if t >= 0.5 then return "warning" end
  if t >= 0.25 then return "primary" end
  return "success"
end

--- Paint the chart into `surface`. This is what a view calls from render().
function methods:render(surface)
  local width, height = ui.viewport(self.opts.width, self.opts.height)
  local theme = ui.theme(self.opts.theme)
  surface = surface or ui.surface(width, height, theme)
  local o = self.opts
  local pad = o.padding
  local left = pad.left
  local top = pad.top
  local plot_w = math.max(16, width - pad.left - pad.right)
  local plot_h = math.max(16, height - pad.top - pad.bottom)

  surface:background("background")
  surface:text("chart-title", o.title or "", left, 10, 18, "text")
  if o.subtitle then surface:text("chart-subtitle", o.subtitle, left, 29, 10, "muted") end

  local xlo, xhi = o.x.min, o.x.max
  local ylo, yhi = o.y.min, o.y.max
  if not xlo or not xhi then xlo, xhi = bounds(self.series, "x") end
  if not ylo or not yhi then ylo, yhi = bounds(self.series, "y") end
  xlo, xhi = tonumber(xlo) or 0, tonumber(xhi) or 1
  ylo, yhi = tonumber(ylo) or 0, tonumber(yhi) or 1
  if xlo == xhi then xhi = xlo + 1 end
  if ylo == yhi then yhi = ylo + 1 end

  local function sx(x) return left + (x - xlo) / (xhi - xlo) * plot_w end
  local function sy(y) return top + plot_h - (y - ylo) / (yhi - ylo) * plot_h end

  surface:rect("chart-plot", left, top, plot_w, plot_h, "surface", 0.18, 8)
  local yticks = nice_ticks(ylo, yhi, o.grid)
  local xticks = nice_ticks(xlo, xhi, o.grid)
  for _, value in ipairs(yticks) do
    local y = sy(value)
    if y >= top - 0.5 and y <= top + plot_h + 0.5 then
      surface:rect("chart-grid-y-" .. tostring(value), left, y, plot_w, 1, "muted", 0.12, 0)
      surface:text("chart-y-" .. tostring(value), format_number(value), 6, y - 6, 9, "muted")
    end
  end
  for _, value in ipairs(xticks) do
    local x = sx(value)
    if x >= left - 0.5 and x <= left + plot_w + 0.5 then
      surface:rect("chart-grid-x-" .. tostring(value), x, top, 1, plot_h, "muted", 0.08, 0)
      surface:text("chart-x-" .. tostring(value), format_number(value), x + 3, top + plot_h + 6, 9, "muted")
    end
  end

  for index, item in ipairs(self.series) do
    local key = item.id or ("series-" .. index)
    if item.kind == "line" or item.kind == "area" then
      local points = item.points
      local threshold = item.max_points or o.max_points
      if threshold and #points > threshold then
        points = lttb(points, math.max(3, math.floor(threshold)))
      end
      local screen = {}
      for _, point in ipairs(points) do
        local x, y = sx(point.x), sy(point.y)
        if x >= left - 1 and x <= left + plot_w + 1 then
          screen[#screen + 1] = { x, y }
        end
      end
      if item.kind == "area" and surface.area then
        surface:area(key .. "-fill", screen, sy(math.min(0, ylo)), item.ink, item.fill_opacity)
      end
      if surface.polyline then
        surface:polyline(key, screen, item.width, item.ink, 1.0, item.join, item.miter_limit)
      else
        for segment = 2, #screen do
          local a, b = screen[segment - 1], screen[segment]
          surface:line(key .. "-" .. segment, a[1], a[2], b[1], b[2], item.width, item.ink, 1.0)
        end
      end
    elseif item.kind == "scatter" then
      for point_index, point in ipairs(item.points) do
        local x, y = sx(point.x), sy(point.y)
        if x >= left and x <= left + plot_w and y >= top and y <= top + plot_h then
          surface:rect(key .. "-" .. point_index, x - item.size * 0.5, y - item.size * 0.5,
            item.size, item.size, item.ink, 0.9, item.size)
        end
      end
    elseif item.kind == "bar" then
      local count = math.max(1, #item.values)
      local slot = plot_w / count
      for value_index, value in ipairs(item.values) do
        value = tonumber(value) or 0
        local x = left + (value_index - 1) * slot + slot * 0.15
        local y = sy(math.max(0, value))
        local zero = sy(math.min(0, value))
        local bar_h = math.max(1, math.abs(zero - y))
        surface:rect(key .. "-" .. value_index, x, math.min(y, zero), slot * 0.7, bar_h, item.ink, 0.85, 2)
      end
    elseif item.kind == "heatmap" then
      local rows, cols = math.max(1, item.rows), math.max(1, item.cols)
      local cw, ch = plot_w / cols, plot_h / rows
      local lo, hi = math.huge, -math.huge
      for _, value in ipairs(item.values) do
        value = tonumber(value) or 0
        lo, hi = math.min(lo, value), math.max(hi, value)
      end
      if lo == hi then hi = lo + 1 end
      for row = 1, rows do
        for col = 1, cols do
          local value = tonumber(item.values[(row - 1) * cols + col]) or 0
          surface:rect(key .. "-" .. row .. "-" .. col,
            left + (col - 1) * cw, top + (row - 1) * ch, cw + 0.5, ch + 0.5,
            ink_for(item, value, lo, hi), 0.9, 0)
        end
      end
    end
  end

  if o.legend ~= false and #self.series > 0 then
    local x = left
    for index, item in ipairs(self.series) do
      local label = item.label or item.id or ("Series " .. index)
      surface:rect("chart-legend-" .. index, x, height - 16, 8, 8, item.ink or "primary", 1.0, 2)
      surface:text("chart-legend-label-" .. index, label, x + 12, height - 19, 10, "muted")
      x = x + 24 + #label * 5.5
    end
  end
end

--- Capture the chart as a portable `soil_scene` present.
function methods:present()
  local width, height = ui.viewport(self.opts.width, self.opts.height)
  local theme = ui.theme(self.opts.theme)
  return ui.capture(width, height, theme, function(surface) self:render(surface) end)
end

return chart
