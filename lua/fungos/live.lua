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

--- Optional palette overrides. Unspecified roles fall back to the host theme.
function live.theme(opts)
  opts = opts or {}
  return {
    background = opts.background,
    surface = opts.surface,
    text = opts.text,
    muted = opts.muted,
    primary = opts.primary,
    success = opts.success,
    warning = opts.warning,
    danger = opts.danger,
    info = opts.info,
    body = tonumber(opts.body),
  }
end

--- An optional automatic panel grid. Layer `rect` values are ignored when a
-- grid is present.
function live.grid(opts)
  opts = opts or {}
  return {
    columns = tonumber(opts.columns),
    rows = tonumber(opts.rows),
    gap = tonumber(opts.gap),
    padding = tonumber(opts.padding),
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
    grid = opts.grid,
    theme = opts.theme,
    layers = opts.layers or {},
  }
end

--- A chart layer. Series `source` names a resident Rust stream.
function live.chart(opts)
  opts = opts or {}
  local out = layer("chart", opts)
  out.series = opts.series or {}
  out.annotations = opts.annotations or {}
  out.legend = opts.legend ~= false
  out.style = opts.style or {}
  out.y_min = opts.y_min
  out.y_max = opts.y_max
  out.y_lerp = opts.y_lerp
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
    ink = opts.ink,
    color2 = opts.color2,
    width = opts.width,
    fill_opacity = opts.fill_opacity,
    smooth = opts.smooth == true,
    interpolate = opts.interpolate == true,
    step = opts.step == true,
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

--- A vertical event marker at cycle time `at`.
function live.event(opts)
  opts = opts or {}
  return {
    kind = "line",
    at = tonumber(opts.at) or 0,
    label = opts.label,
    color = opts.color,
    opacity = opts.opacity,
  }
end

--- A key point marked on the X axis. `line = false` keeps only the marker and
-- label.
function live.x_event(opts)
  opts = opts or {}
  return {
    kind = "x_event",
    at = tonumber(opts.at) or 0,
    label = opts.label,
    color = opts.color,
    opacity = opts.opacity,
    line = opts.line ~= false,
  }
end

--- A shaded time band from `from` to `to`.
function live.band_annotation(opts)
  opts = opts or {}
  return {
    kind = "band",
    from = tonumber(opts.from or opts.at) or 0,
    to = tonumber(opts.to) or 0,
    label = opts.label,
    color = opts.color,
    opacity = opts.opacity,
  }
end

--- A horizontal data-space threshold.
function live.threshold(opts)
  opts = opts or {}
  return {
    kind = "threshold",
    value = tonumber(opts.value) or 0,
    label = opts.label,
    color = opts.color,
    opacity = opts.opacity,
  }
end

--- A distribution histogram of one resident source.
function live.histogram(opts)
  opts = opts or {}
  local out = layer("histogram", opts)
  out.source = opts.source
  out.bins = tonumber(opts.bins) or 24
  out.min = opts.min
  out.max = opts.max
  out.color = opts.color
  out.ink = opts.ink
  out.opacity = opts.opacity
  out.bar_radius = opts.bar_radius
  return out
end

--- A resident dense series with CPU LTTB decimation.
function live.dense(opts)
  opts = opts or {}
  local out = layer("dense", opts)
  out.points = tonumber(opts.points) or 1000000
  out.seed = tonumber(opts.seed) or 0
  out.threshold = tonumber(opts.threshold) or 4000
  out.mode = opts.mode or opts.kind or "line"
  return out
end

--- A generated 3D point cloud, projected by the native host.
function live.pointcloud3d(opts)
  opts = opts or {}
  local out = layer("pointcloud3d", opts)
  out.points = tonumber(opts.points) or 20000
  out.seed = tonumber(opts.seed) or 0
  out.pitch = tonumber(opts.pitch)
  out.size = tonumber(opts.size)
  return out
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
