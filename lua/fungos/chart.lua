-- fungos.chart — declarative charts on the same scene surface as every Spore.
--
--   local chart = require("fungos.chart")
--   local c = chart.new { title = "Latency", width = 900, height = 520 }
--   c:line { id = "p95", points = points, ink = "primary", width = 2 }
--   c:render()
--
-- The module is pure: the caller supplies points and the host supplies viewport,
-- theme and layout. Lines, areas, points, heatmaps and candles are emitted as
-- bounded scene primitives; the GPU renderer draws them without a second ABI.

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
  crosshair = nil,
  annotations = nil,
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

--- Keep the most recent `count` points. Streaming belongs to the snapshot; this
-- is the pure windowing helper a live view calls before handing points to a chart.
function chart.window(points, count)
  points = points or {}
  count = math.max(1, math.floor(count or 240))
  local out = {}
  local first = math.max(1, #points - count + 1)
  for index = first, #points do out[#out + 1] = points[index] end
  return out
end

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

--- Add OHLC candles. Each entry is `{x=,open=,high=,low=,close=}`.
function methods:candles(opts)
  opts = copy(opts or {})
  opts.kind = "candles"
  opts.up_ink = opts.up_ink or "success"
  opts.down_ink = opts.down_ink or "danger"
  opts.candles = opts.candles or {}
  self.series[#self.series + 1] = opts
  return self
end

local function nav_clamp(value, lo, hi)
  return math.max(lo, math.min(hi, value))
end

--- A pure chart viewport navigator.
--
-- The host supplies `pointer`, `scroll` and `key` events. The navigator owns
-- zoom/pan/selection math and returns data domains; it never reads a clock,
-- a socket, or a host API. Double-click resets, Shift-drag selects a range,
-- wheel zooms around the pointer, and `r`/`+`/`-` work when a host routes keys.
function chart.navigator(opts)
  opts = opts or {}
  local nav = {
    zoom_x = 1,
    zoom_y = 1,
    pan_x = 0,
    pan_y = 0,
    bounds = { 0, 1, 0, 1 },
    pointer = nil,
    dragging = false,
    selecting = false,
    sel_start = nil,
    sel_end = nil,
    last_press_at = nil,
    last_press_x = nil,
    last_press_y = nil,
    reset_zoom = opts.reset_zoom or 1,
    min_zoom = opts.min_zoom or 0.2,
    max_zoom = opts.max_zoom or 24,
  }
  function nav:set_bounds(xlo, xhi, ylo, yhi)
    if type(xlo) == "table" then
      xlo, xhi, ylo, yhi = xlo[1] or xlo.xlo, xlo[2] or xlo.xhi, xlo[3] or xlo.ylo, xlo[4] or xlo.yhi
    end
    if not xhi or xhi <= xlo then xhi = xlo + 1 end
    if not yhi or yhi <= ylo then yhi = ylo + 1 end
    self.bounds = { xlo, xhi, ylo, yhi }
    return self
  end

  function nav:reset()
    self.zoom_x, self.zoom_y = self.reset_zoom, self.reset_zoom
    self.pan_x, self.pan_y = 0, 0
    self.selecting = false
    self.sel_start, self.sel_end = nil, nil
    return self
  end

  function nav:zoom(factor, anchor_x, anchor_y)
    local xlo, xhi, ylo, yhi = table.unpack(self.bounds)
    anchor_x = anchor_x or 0.5
    anchor_y = anchor_y or 0.5
    local old_sx = (xhi - xlo) / self.zoom_x
    local old_cx = (xlo + xhi) / 2 + self.pan_x * old_sx
    local pointer_x = old_cx + (anchor_x - 0.5) * old_sx
    local new_zoom_x = nav_clamp(self.zoom_x * factor, self.min_zoom, self.max_zoom)
    local new_sx = (xhi - xlo) / new_zoom_x
    local new_cx = pointer_x - (anchor_x - 0.5) * new_sx
    self.zoom_x = new_zoom_x
    self.pan_x = (new_cx - (xlo + xhi) / 2) / new_sx

    local old_sy = (yhi - ylo) / self.zoom_y
    local old_cy = (ylo + yhi) / 2 + self.pan_y * old_sy
    local pointer_y = old_cy + (0.5 - anchor_y) * old_sy
    local new_zoom_y = nav_clamp(self.zoom_y * factor, self.min_zoom, self.max_zoom)
    local new_sy = (yhi - ylo) / new_zoom_y
    local new_cy = pointer_y - (0.5 - anchor_y) * new_sy
    self.zoom_y = new_zoom_y
    self.pan_y = (new_cy - (ylo + yhi) / 2) / new_sy
    return self
  end

  function nav:view()
    local xlo, xhi, ylo, yhi = table.unpack(self.bounds)
    local sx = (xhi - xlo) / self.zoom_x
    local sy = (yhi - ylo) / self.zoom_y
    local cx = (xlo + xhi) / 2 + self.pan_x * sx
    local cy = (ylo + yhi) / 2 + self.pan_y * sy
    local xdom = { min = cx - sx / 2, max = cx + sx / 2 }
    local ydom = { min = cy - sy / 2, max = cy + sy / 2 }
    local crosshair
    if self.pointer then
      crosshair = {
        x = xdom.min + self.pointer.x * (xdom.max - xdom.min),
        y = ydom.max - self.pointer.y * (ydom.max - ydom.min),
      }
    end
    local selection
    if self.sel_start and self.sel_end then
      local x0 = xdom.min + math.min(self.sel_start.x, self.sel_end.x) * (xdom.max - xdom.min)
      local x1 = xdom.min + math.max(self.sel_start.x, self.sel_end.x) * (xdom.max - xdom.min)
      local y0 = ydom.max - math.max(self.sel_start.y, self.sel_end.y) * (ydom.max - ydom.min)
      local y1 = ydom.max - math.min(self.sel_start.y, self.sel_end.y) * (ydom.max - ydom.min)
      selection = { x0 = x0, x1 = x1, y0 = y0, y1 = y1 }
    end
    return xdom, ydom, crosshair, selection
  end

  function nav:apply_selection()
    if not self.sel_start or not self.sel_end then return self end
    local dx = math.abs(self.sel_end.x - self.sel_start.x)
    local dy = math.abs(self.sel_end.y - self.sel_start.y)
    if dx < 0.015 and dy < 0.015 then return self end
    local xdom, ydom = self:view()
    local xlo, xhi, ylo, yhi = table.unpack(self.bounds)
    if dx >= 0.015 then
      local x0 = xdom.min + math.min(self.sel_start.x, self.sel_end.x) * (xdom.max - xdom.min)
      local x1 = xdom.min + math.max(self.sel_start.x, self.sel_end.x) * (xdom.max - xdom.min)
      local span = math.max(0.000001, x1 - x0)
      self.zoom_x = nav_clamp((xhi - xlo) / span, self.min_zoom, self.max_zoom)
      self.pan_x = (((x0 + x1) / 2) - (xlo + xhi) / 2) / span
    end
    if dy >= 0.015 then
      local y0 = ydom.max - math.max(self.sel_start.y, self.sel_end.y) * (ydom.max - ydom.min)
      local y1 = ydom.max - math.min(self.sel_start.y, self.sel_end.y) * (ydom.max - ydom.min)
      local span = math.max(0.000001, y1 - y0)
      self.zoom_y = nav_clamp((yhi - ylo) / span, self.min_zoom, self.max_zoom)
      self.pan_y = (((y0 + y1) / 2) - (ylo + yhi) / 2) / span
    end
    self.selecting = false
    self.sel_start, self.sel_end = nil, nil
    return self
  end

  function nav:feed(event)
    if type(event) ~= "table" then return self end
    local kind = event.kind
    if kind == "pointer" then
      local x, y = tonumber(event.x), tonumber(event.y)
      if not x or not y then return self end
      self.pointer = { x = x, y = y }
      if event.phase == "leave" then
        self.pointer = nil
        self.dragging = false
        self.selecting = false
      elseif event.phase == "press" then
        local at = tonumber(event.at_ms)
        if at and self.last_press_at and at - self.last_press_at <= 350
          and math.abs(x - (self.last_press_x or -1)) <= 0.03
          and math.abs(y - (self.last_press_y or -1)) <= 0.03 then
          self:reset()
          self.last_press_at = nil
          self.dragging = false
          self.selecting = false
          return self
        end
        self.last_press_at, self.last_press_x, self.last_press_y = at, x, y
        if event.shift then
          self.selecting = true
          self.dragging = false
          self.sel_start = { x = x, y = y }
          self.sel_end = { x = x, y = y }
        else
          self.dragging = true
          self.selecting = false
          self.sel_start, self.sel_end = nil, nil
          self.last_x, self.last_y = x, y
        end
      elseif event.phase == "move" then
        if self.selecting then
          self.sel_end = { x = x, y = y }
        elseif self.dragging then
          self.pan_x = self.pan_x - (x - (self.last_x or x))
          self.pan_y = self.pan_y + (y - (self.last_y or y))
          self.last_x, self.last_y = x, y
        end
      elseif event.phase == "release" then
        if self.selecting then self:apply_selection() end
        self.dragging = false
      end
    elseif kind == "scroll" then
      local x, y = tonumber(event.x) or 0.5, tonumber(event.y) or 0.5
      local dy = tonumber(event.dy) or 0
      self:zoom(math.exp(-dy * 0.002), x, y)
    elseif kind == "key" then
      local name = tostring(event.key or ""):lower()
      if name == "r" or name == "0" or name == "home" then
        self:reset()
      elseif name == "+" or name == "=" then
        self:zoom(1.25)
      elseif name == "-" or name == "_" then
        self:zoom(0.8)
      elseif name == "left" or name == "arrowleft" then
        self.pan_x = self.pan_x - 0.08
      elseif name == "right" or name == "arrowright" then
        self.pan_x = self.pan_x + 0.08
      elseif name == "up" or name == "arrowup" then
        self.pan_y = self.pan_y - 0.08
      elseif name == "down" or name == "arrowdown" then
        self.pan_y = self.pan_y + 0.08
      end
    end
    return self
  end

  return setmetatable(nav, {
    __index = function(_, key) return rawget(nav, key) end,
  })
end

local function finite(value)
  return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function bounds(series, axis)
  local lo, hi
  for _, item in ipairs(series) do
    if item.kind == "heatmap" then
      if axis == "x" then
        lo, hi = 0, math.max(1, (item.cols or 1) - 1)
      else
        lo, hi = 0, math.max(1, (item.rows or 1) - 1)
      end
    elseif item.kind == "bar" then
      for index, value in ipairs(item.values or {}) do
        value = tonumber(value) or 0
        lo = lo and math.min(lo, math.min(0, value)) or math.min(0, value)
        hi = hi and math.max(hi, value) or value
        lo = lo and math.min(lo, index) or index
        hi = hi and math.max(hi, index) or index
      end
    elseif item.kind == "candles" then
      for _, candle in ipairs(item.candles or {}) do
        local value
        if axis == "x" then
          value = tonumber(candle.x) or 0
        else
          local low = tonumber(candle.low) or 0
          local high = tonumber(candle.high) or 0
          lo = lo and math.min(lo, low) or low
          hi = hi and math.max(hi, high) or high
        end
        if value then
          lo = lo and math.min(lo, value) or value
          hi = hi and math.max(hi, value) or value
        end
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
      local screen = {}
      for _, point in ipairs(item.points) do
        local x, y = sx(point.x), sy(point.y)
        if x >= left and x <= left + plot_w and y >= top and y <= top + plot_h then
          screen[#screen + 1] = { x, y }
        end
      end
      surface:points(key, screen, item.size, item.ink, item.opacity or 0.9)
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
      local values = {}
      local lo, hi = math.huge, -math.huge
      for _, value in ipairs(item.values) do
        value = tonumber(value) or 0
        values[#values + 1] = value
        lo, hi = math.min(lo, value), math.max(hi, value)
      end
      if lo == hi then hi = lo + 1 end
      surface:heatmap(key, values, rows, cols, left, top, plot_w, plot_h,
        item.min or lo, item.max or hi, item.opacity or 0.9)
    elseif item.kind == "candles" then
      local screen = {}
      local slot = plot_w / math.max(1, #item.candles)
      for _, candle in ipairs(item.candles) do
        local x = sx(tonumber(candle.x) or 0)
        if x >= left - slot and x <= left + plot_w + slot then
          screen[#screen + 1] = {
            x = x,
            open = sy(tonumber(candle.open) or 0),
            high = sy(tonumber(candle.high) or 0),
            low = sy(tonumber(candle.low) or 0),
            close = sy(tonumber(candle.close) or 0),
          }
        end
      end
      surface:candles(key, screen, math.max(2, slot * 0.62), item.up_ink, item.down_ink, item.opacity or 1.0)
    end
  end

  if o.selection then
    local s = o.selection
    local x0, x1 = sx(s.x0), sx(s.x1)
    local y0, y1 = sy(s.y0), sy(s.y1)
    local left_x, right_x = math.min(x0, x1), math.max(x0, x1)
    local top_y, bottom_y = math.min(y0, y1), math.max(y0, y1)
    surface:rect("chart-selection", left_x, top_y, math.max(1, right_x - left_x),
      math.max(1, bottom_y - top_y), "primary", 0.14, 2)
    surface:rect("chart-selection-top", left_x, top_y, math.max(1, right_x - left_x), 1, "primary", 0.8, 0)
    surface:rect("chart-selection-bottom", left_x, bottom_y, math.max(1, right_x - left_x), 1, "primary", 0.8, 0)
    surface:rect("chart-selection-left", left_x, top_y, 1, math.max(1, bottom_y - top_y), "primary", 0.8, 0)
    surface:rect("chart-selection-right", right_x, top_y, 1, math.max(1, bottom_y - top_y), "primary", 0.8, 0)
  end

  if o.crosshair then
    local cx, cy = o.crosshair.x, o.crosshair.y
    if finite(cx) then
      local x = sx(cx)
      surface:rect("chart-crosshair-x", x, top, 1, plot_h, "text", 0.28, 0)
      local label = o.crosshair.x_label or format_number(cx)
      surface:text("chart-crosshair-x-label", label, x + 4, top + 4, 9, "text")
    end
    if finite(cy) then
      local y = sy(cy)
      surface:rect("chart-crosshair-y", left, y, plot_w, 1, "text", 0.28, 0)
      local label = o.crosshair.y_label or format_number(cy)
      surface:text("chart-crosshair-y-label", label, left + plot_w - 38, y - 12, 9, "text")
    end
  end

  for index, note in ipairs(o.annotations or {}) do
    local x, y = sx(tonumber(note.x) or 0), sy(tonumber(note.y) or 0)
    surface:rect("chart-note-" .. index, x - 2, y - 2, 4, 4, note.ink or "warning", 1.0, 2)
    if note.label then
      surface:text("chart-note-label-" .. index, note.label, x + 6, y - 14, 9, note.ink or "warning")
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
