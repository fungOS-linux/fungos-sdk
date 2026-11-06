-- fungos.live — Lua-owned UI/styling for the resident Rust live host.
--
-- A live spec is data. It describes where a layer sits, its title, palette and
-- style; the host owns the streams, delta-time clock and per-frame scene. No Lua
-- runs between frames, and no FFI bridge carries sample data.

local live = {}
live.version = "0.1.0"

local function rect(value)
  value = value or {}
  return {
    x = tonumber(value.x) or 0,
    y = tonumber(value.y) or 0,
    width = tonumber(value.width or value.w) or 1,
    height = tonumber(value.height or value.h) or 1,
  }
end

local function layer(kind, opts)
  opts = opts or {}
  return {
    kind = kind,
    id = opts.id or kind,
    rect = rect(opts.rect or opts),
    title = opts.title,
    subtitle = opts.subtitle,
  }
end

--- A resident live scene. `fps` is a ceiling; the host advances by real dt.
function live.scene(opts)
  opts = opts or {}
  return {
    schema = 1,
    width = tonumber(opts.width) or 1200,
    height = tonumber(opts.height) or 840,
    gap = tonumber(opts.gap) or 10,
    fps = tonumber(opts.fps) or 60,
    fullscreen = opts.fullscreen == true,
    ui_scale = tonumber(opts.ui_scale) or 1,
    layers = opts.layers or {},
  }
end

--- A chart layer. Series `source` names a resident Rust stream.
function live.chart(opts)
  opts = opts or {}
  local out = layer("chart", opts)
  out.series = opts.series or {}
  out.legend = opts.legend ~= false
  out.style = opts.style or {}
  out.y_min = opts.y_min
  out.y_max = opts.y_max
  return out
end

function live.series(opts)
  opts = opts or {}
  return {
    id = opts.id,
    label = opts.label,
    visible = opts.visible,
    kind = opts.kind or "line",
    color = opts.color,
    color2 = opts.color2,
    width = opts.width,
    fill_opacity = opts.fill_opacity,
    smooth = opts.smooth == true,
    source = opts.source,
    band_source = opts.band_source,
    open_source = opts.open_source,
    high_source = opts.high_source,
    low_source = opts.low_source,
    close_source = opts.close_source,
    baseline = opts.baseline,
    bar_width = opts.bar_width,
    bar_radius = opts.bar_radius,
    stride = opts.stride,
    up_color = opts.up_color,
    down_color = opts.down_color,
  }
end

function live.graph(opts)
  opts = opts or {}
  local out = layer("graph", opts)
  out.node_count = tonumber(opts.node_count) or 7
  out.labels = opts.labels or {}
  out.colors = opts.colors or {}
  return out
end

function live.map(opts)
  opts = opts or {}
  local out = layer("map", opts)
  out.routes = opts.routes or {}
  return out
end

function live.atlas(opts)
  opts = opts or {}
  local out = layer("atlas", opts)
  out.labels = opts.labels or {}
  out.colors = opts.colors or {}
  return out
end

return live
