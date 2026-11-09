-- fungos.dashboard — reusable Canvas dashboard primitives.
--
-- These are scene painters, not Canvas capabilities and not host state. Every
-- function takes a `fungos.ui` surface plus a pixel rectangle and emits only
-- ordinary rect/text nodes. A Spore view can use them directly or compose them
-- with fungos.chart, fungos.live, and semantic fungos.ui trees.
--
-- The primitive set is deliberately small:
--
--   dashboard.panel(surface, id, x, y, w, h, opts) -> content rect
--   dashboard.stat(...)    value + unit + delta + status
--   dashboard.gauge(...)   segmented threshold meter
--   dashboard.table(...)   headers, status cells, zebra rows
--   dashboard.chart(...)   compact axes, legend, selection and threshold
--
-- All status/threshold colors are semantic inks. Canvas keeps the theme; raw
-- RGB belongs to a GPU scene host, not this module.

local dashboard = { version = "0.1.0" }

local function text_width(surface, value, size)
  local measured = surface:measure_text(value, size)
  if type(measured) == "table" and type(measured.width) == "number" then
    return measured.width
  end
  return #tostring(value or "") * (tonumber(size) or 10) * 0.58
end

local function finite(value, fallback)
  value = tonumber(value)
  if value == nil or value ~= value or value == math.huge or value == -math.huge then
    return fallback
  end
  return value
end

local function clamp(value, lo, hi)
  if value < lo then return lo end
  if value > hi then return hi end
  return value
end

local function present(value)
  if value == nil then return false end
  value = tostring(value)
  return value:match("%S") ~= nil
end

function dashboard.format(value, decimals, unit)
  local number = tonumber(value)
  local out
  if number == nil then
    out = tostring(value or "")
  else
    out = string.format("%." .. tostring(math.max(0, math.floor(decimals or 0))) .. "f", number)
  end
  if present(unit) then out = out .. tostring(unit) end
  return out
end

function dashboard.status_ink(status)
  local value = tostring(status or ""):lower()
  if value == "ok" or value == "healthy" or value == "live" or value == "ready"
    or value == "success" or value == "active" then
    return "success"
  elseif value == "warn" or value == "warning" or value == "degraded"
    or value == "pending" or value == "lagging" then
    return "warning"
  elseif value == "error" or value == "critical" or value == "crit" or value == "down"
    or value == "failed" or value == "failing" then
    return "danger"
  elseif value == "info" or value == "selected" then
    return "info"
  end
  return "muted"
end

function dashboard.threshold_ink(value, thresholds, base)
  local ink = base or "success"
  for _, step in ipairs(thresholds or {}) do
    local at = finite(step.value, nil)
    if at ~= nil and value >= at then ink = step.ink or ink end
  end
  return ink
end

function dashboard.status(surface, id, x, y, status, opts)
  if not present(status) then return end
  opts = opts or {}
  local label = opts.label or tostring(status)
  if not present(label) then return end
  local ink = opts.ink or dashboard.status_ink(status)
  local size = opts.size or 9
  surface:rect(id .. "-dot", x, y + 2, 6, 6, ink, 1, 3, 0.2)
  surface:text(id .. "-label", label, x + 10, y, size, ink)
end

function dashboard.panel(surface, id, x, y, width, height, opts)
  opts = opts or {}
  local pad = finite(opts.padding, 12)
  surface:rect(id .. "-panel", x, y, width, height,
    opts.ink or "surface", finite(opts.opacity, 0.78), finite(opts.radius, 10), -0.1)
  local top = y + pad
  if present(opts.title) then
    surface:text(id .. "-title", tostring(opts.title), x + pad, y + 9,
      finite(opts.title_size, 13), opts.title_ink or "text")
    top = y + 38
  end
  if present(opts.subtitle) then
    local size = finite(opts.subtitle_size, 9)
    surface:text(id .. "-subtitle", tostring(opts.subtitle), x + pad, top - 2, size, "muted")
    top = top - 2 + size + 6
  end
  if present(opts.status) then
    local label = opts.status_label or tostring(opts.status)
    local ink = opts.status_ink or dashboard.status_ink(opts.status)
    local label_w = text_width(surface, label, 9)
    surface:rect(id .. "-status-dot", x + width - pad - label_w - 11, y + 13,
      6, 6, ink, 1, 3, 0.2)
    surface:text(id .. "-status", label, x + width - pad - label_w, y + 11, 9, ink)
  end
  return {
    x = x + pad,
    y = top + 4,
    width = math.max(1, width - pad * 2),
    height = math.max(1, height - (top - y) - pad - 4),
  }
end

function dashboard.stat(surface, id, x, y, width, height, opts)
  opts = opts or {}
  local content = dashboard.panel(surface, id, x, y, width, height, {
    ink = "surface",
    opacity = 0.78,
    radius = 9,
    status = opts.status,
    status_ink = opts.status_ink,
    status_label = opts.status_label,
    padding = 12,
  })
  local label = tostring(opts.label or "Metric")
  surface:text(id .. "-label", label, content.x, y + 10, 10, "muted")

  local value = opts.display or dashboard.format(opts.value, opts.decimals)
  local value_size = finite(opts.value_size, 26)
  local value_ink = opts.value_ink or "text"
  surface:text(id .. "-value", value, content.x, y + 28, value_size, value_ink)
  if present(opts.unit) then
    -- Keep the unit on its own line. Measured text width varies between the
    -- fake host and Canvas; placing it after the value lets long units collide
    -- with the number at the very moment it is supposed to clarify it.
    surface:text(id .. "-unit", tostring(opts.unit), content.x,
      y + 58, 9, "muted")
  end
  if present(opts.delta) then
    local delta_ink = opts.delta_ink
      or ((finite(opts.delta, 0) >= 0) and "success" or "danger")
    local delta = opts.delta_text or ((finite(opts.delta, 0) >= 0 and "+" or "")
      .. dashboard.format(opts.delta, opts.delta_decimals or 1) .. "%")
    surface:text(id .. "-delta", delta, content.x, y + height - 24, 9, delta_ink)
  end
  if present(opts.caption) then
    surface:text(id .. "-caption", tostring(opts.caption),
      content.x + (present(opts.delta) and (text_width(surface, opts.delta_text or "", 9) + 10) or 0),
      y + height - 24, 9, "muted")
  end
  return content
end

function dashboard.gauge(surface, id, x, y, width, height, opts)
  opts = opts or {}
  local value = finite(opts.value, 0)
  local lo = finite(opts.min, 0)
  local hi = finite(opts.max, 100)
  if hi == lo then hi = lo + 1 end
  local content = dashboard.panel(surface, id, x, y, width, height, {
    title = opts.title or "Gauge",
    subtitle = opts.subtitle,
    status = opts.status,
    status_ink = opts.status_ink,
    status_label = opts.status_label,
    padding = 12,
  })
  local ink = dashboard.threshold_ink(value, opts.thresholds, opts.base_ink)
  local value_text = dashboard.format(value, opts.decimals, opts.unit)
  surface:text(id .. "-value", value_text, content.x, content.y, 22, ink)
  local track_y = y + height - 40
  local track_x = content.x
  local track_w = content.width
  local segments = math.max(2, math.floor(finite(opts.segments, 12)))
  local step = track_w / segments
  surface:rect(id .. "-track", track_x, track_y, track_w, 10, "surface", 0.9, 5, 0.1)
  for index = 1, segments do
    local mid = lo + (hi - lo) * (index - 0.5) / segments
    local filled = mid <= value
    local segment_ink = dashboard.threshold_ink(mid, opts.thresholds, opts.base_ink)
    surface:rect(id .. "-segment-" .. index, track_x + (index - 1) * step,
      track_y, math.max(1, step - 2), 10,
      filled and segment_ink or "muted", filled and 0.92 or 0.12, 3, 0.2)
  end
  surface:text(id .. "-min", dashboard.format(lo, opts.decimals, opts.unit),
    track_x, track_y + 14, 8, "muted")
  local max_text = dashboard.format(hi, opts.decimals, opts.unit)
  surface:text(id .. "-max", max_text, track_x + track_w - text_width(surface, max_text, 8),
    track_y + 14, 8, "muted")
  return content
end

function dashboard.table(surface, id, x, y, width, height, opts)
  opts = opts or {}
  local content = dashboard.panel(surface, id, x, y, width, height, {
    title = opts.title or "Table",
    subtitle = opts.subtitle,
    status = opts.status,
    status_ink = opts.status_ink,
    status_label = opts.status_label,
    padding = 12,
  })
  local columns = opts.columns or {}
  local rows = opts.rows or {}
  if #columns == 0 then return content end
  local weight = 0
  for _, column in ipairs(columns) do weight = weight + finite(column.width, 1) end
  local gap = finite(opts.column_gap, 12)
  local usable = math.max(1, content.width - gap * (#columns - 1))
  local xs, widths = {}, {}
  local cursor = content.x
  for index, column in ipairs(columns) do
    xs[index] = cursor
    widths[index] = usable * finite(column.width, 1) / weight
    cursor = cursor + widths[index] + gap
  end
  local header_y = content.y
  for index, column in ipairs(columns) do
    surface:text(id .. "-header-" .. index, tostring(column.label or column.key or ""),
      xs[index], header_y, 9, "muted")
  end
  surface:rect(id .. "-header-rule", content.x, header_y + 15,
    content.width, 1, "muted", 0.12, 0)
  local row_h = finite(opts.row_height, 23)
  local available = math.max(0, math.floor((content.height - 22) / row_h))
  for row_index = 1, math.min(#rows, available) do
    local row = rows[row_index]
    local ry = header_y + 22 + (row_index - 1) * row_h
    if opts.zebra and row_index % 2 == 0 then
      surface:rect(id .. "-zebra-" .. row_index, content.x - 4, ry - 2,
        content.width + 8, row_h, "surface", 0.34, 4, 0.1)
    end
    for column_index, column in ipairs(columns) do
      local value = row[column.key]
      local cx = xs[column_index]
      if column.kind == "status" then
        dashboard.status(surface, id .. "-row-" .. row_index .. "-" .. column_index,
          cx, ry, tostring(value or ""), { label = tostring(value or "") })
      else
        local text = column.format and column.format(value, row) or tostring(value or "")
        if present(text) then
          if column.align == "right" then
            cx = cx + widths[column_index] - text_width(surface, text, 9) - 8
          end
          surface:text(id .. "-row-" .. row_index .. "-" .. column_index,
            text, cx, ry, 9, column.ink or "text")
        end
      end
    end
  end
  return content
end

local function point_xy(point)
  if type(point) ~= "table" then return nil end
  local x, y = point.x, point.y
  if x == nil then x = point[1] end
  if y == nil then y = point[2] end
  x, y = tonumber(x), tonumber(y)
  if x == nil or y == nil then return nil end
  return x, y
end

local function sample_series(points, columns)
  local out = {}
  local count = #(points or {})
  if count == 0 then return out end
  for column = 1, columns do
    local index = 1
    if columns > 1 and count > 1 then
      index = 1 + math.floor((column - 1) * (count - 1) / (columns - 1) + 0.5)
    end
    local x, y = point_xy(points[index])
    if x ~= nil then out[#out + 1] = { x = x, y = y } end
  end
  return out
end

function dashboard.chart(surface, id, x, y, width, height, opts)
  opts = opts or {}
  local content = dashboard.panel(surface, id, x, y, width, height, {
    title = opts.title or "Time series",
    subtitle = opts.subtitle,
    status = opts.status,
    status_ink = opts.status_ink,
    status_label = opts.status_label,
    padding = 12,
  })
  local series = opts.series or {}
  local legend_y = content.y + content.height - 10
  local plot_x = content.x + 34
  local plot_y = content.y + 3
  local plot_w = math.max(16, content.width - 42)
  local plot_h = math.max(16, legend_y - 22 - plot_y)
  surface:rect(id .. "-plot", plot_x, plot_y, plot_w, plot_h, "background", 0.72, 6)

  local x_min, x_max = finite(opts.x_min, nil), finite(opts.x_max, nil)
  local y_min, y_max = finite(opts.y_min, nil), finite(opts.y_max, nil)
  for _, item in ipairs(series) do
    for _, point in ipairs(item.points or {}) do
      local px, py = point_xy(point)
      if px ~= nil then
        x_min = x_min and math.min(x_min, px) or px
        x_max = x_max and math.max(x_max, px) or px
        y_min = y_min and math.min(y_min, py) or py
        y_max = y_max and math.max(y_max, py) or py
      end
    end
  end
  x_min, x_max = finite(x_min, 0), finite(x_max, 1)
  y_min, y_max = finite(y_min, 0), finite(y_max, 1)
  if x_min == x_max then x_max = x_min + 1 end
  if y_min == y_max then y_max = y_min + 1 end

  local function x_pos(value)
    return plot_x + (value - x_min) / (x_max - x_min) * plot_w
  end
  local function y_pos(value)
    return plot_y + plot_h - (value - y_min) / (y_max - y_min) * plot_h
  end

  for index = 0, 3 do
    local py = plot_y + plot_h * index / 3
    surface:rect(id .. "-grid-" .. index, plot_x, py, plot_w, 1, "muted", 0.07, 0)
  end
  for index = 0, 2 do
    local value = y_min + (y_max - y_min) * index / 2
    local label = dashboard.format(value, opts.y_decimals, opts.unit)
    surface:text(id .. "-y-" .. index, label,
      plot_x - text_width(surface, label, 8) - 7,
      y_pos(value) - 4, 8, "muted")
  end
  for index = 0, 2 do
    local value = x_min + (x_max - x_min) * index / 2
    local label = dashboard.format(value, opts.x_decimals)
    surface:text(id .. "-x-" .. index, label,
      x_pos(value) - text_width(surface, label, 8) / 2,
      plot_y + plot_h + 9, 8, "muted")
  end

  if opts.selection then
    local from = clamp(finite(opts.selection.x0, x_min), x_min, x_max)
    local to = clamp(finite(opts.selection.x1, x_max), x_min, x_max)
    if from > to then from, to = to, from end
    surface:rect(id .. "-selection", x_pos(from), plot_y,
      math.max(1, x_pos(to) - x_pos(from)), plot_h, "primary", 0.07, 0)
  end
  if opts.threshold then
    local value = finite(opts.threshold.value, nil)
    if value ~= nil then
      local py = y_pos(clamp(value, y_min, y_max))
      surface:rect(id .. "-threshold", plot_x, py, plot_w, 1,
        opts.threshold.ink or "warning", 0.72, 0)
      if present(opts.threshold.label) then
        local label = tostring(opts.threshold.label)
        surface:text(id .. "-threshold-label", label,
          plot_x + plot_w - text_width(surface, label, 8) - 3, py - 10, 8,
          opts.threshold.ink or "warning")
      end
    end
  end

  local columns = math.max(2, math.floor(finite(opts.columns, 12)))
  local col_w = plot_w / columns
  for series_index, item in ipairs(series) do
    local points = sample_series(item.points, columns)
    local ink = item.ink or "primary"
    for column, point in ipairs(points) do
      local value = clamp(point.y, y_min, y_max)
      local py = y_pos(value)
      local bar_h = math.max(1, plot_y + plot_h - py)
      surface:rect(id .. "-bar-" .. series_index .. "-" .. column,
        plot_x + (column - 1) * col_w, py, math.max(1, col_w - 1), bar_h,
        ink, finite(item.opacity, 0.26), 0)
      surface:rect(id .. "-cap-" .. series_index .. "-" .. column,
        plot_x + (column - 1) * col_w, py, math.max(1, col_w - 1), 2,
        ink, 1, 1)
    end
  end

  local legend_x = content.x
  for index, item in ipairs(series) do
    local label = tostring(item.label or item.id or ("series " .. index))
    surface:text(id .. "-legend-" .. index, label, legend_x, legend_y, 8,
      item.ink or "primary")
    legend_x = legend_x + text_width(surface, label, 8) + 22
  end
  return content
end

return dashboard
