-- fungos.map — a composable vector map layer.
--
-- This is the Lua layer, not a tile engine. It projects GeoJSON-ish data and
-- draws graticules, lines, polygons and points through the same scene
-- primitives as every other layer. Raster/vector tile decoding belongs in a
-- host capability or a Rust map layer; it can be added behind the same API.

local ui = require("fungos.ui")

local map = {}
map.version = "0.1.0"

local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for key, item in pairs(value) do out[key] = copy(item) end
  return out
end

map.defaults = {
  padding = 18,
  zoom = 3,
  center = { 0, 20 },
  background = true,
  graticule = true,
  line_ink = "primary",
  point_ink = "warning",
  line_width = 1.5,
  point_size = 5,
}

function map.new(opts)
  opts = opts or {}
  local out = copy(map.defaults)
  for key, value in pairs(opts) do out[key] = value end
  return setmetatable({
    opts = out,
    features = opts.features or {},
    labels = opts.labels or {},
  }, { __index = map.methods })
end

map.methods = {}

local function mercator(lat)
  lat = math.max(-85.05112878, math.min(85.05112878, lat))
  return math.log(math.tan(math.pi / 4 + (lat * math.pi / 180) / 2))
end

function map.methods:projection(width, height)
  local pad = self.opts.padding
  local span = 360 / (2 ^ tonumber(self.opts.zoom))
  local center_lon = tonumber(self.opts.center[1]) or 0
  local center_lat = tonumber(self.opts.center[2]) or 0
  local lon0, lon1 = center_lon - span / 2, center_lon + span / 2
  local my = mercator(center_lat)
  local half = (span * math.pi / 180) / 2
  local my0, my1 = my - half, my + half
  local plot_w, plot_h = width - pad * 2, height - pad * 2
  local function project(lon, lat)
    local x = pad + (lon - lon0) / (lon1 - lon0) * plot_w
    local yy = pad + (1 - (mercator(lat) - my0) / (my1 - my0)) * plot_h
    return x, yy
  end
  return project, lon0, lon1, my0, my1
end

local function point(lon, lat)
  return { tonumber(lon) or 0, tonumber(lat) or 0 }
end

local function ring(points, project)
  local out = {}
  for _, p in ipairs(points or {}) do
    local x, y = project(p[1], p[2])
    out[#out + 1] = { x, y }
  end
  return out
end

function map.methods:render(surface, width, height)
  local viewport_w, viewport_h = ui.viewport(self.opts.width, self.opts.height)
  width, height = width or viewport_w, height or viewport_h
  surface = surface or ui.surface(width, height, ui.theme(self.opts.theme))
  if self.opts.background then surface:background("background") end
  local project = self:projection(width, height)

  if self.opts.graticule then
    local step = self.opts.zoom >= 6 and 1 or self.opts.zoom >= 4 and 5 or 20
    local index = 0
    for lon = -180, 180, step do
      local x = select(1, project(lon, 0))
      surface:rect("map-grid-lon-" .. lon, x, 0, 1, height, "muted", 0.10, 0)
      surface:text("map-label-lon-" .. lon, tostring(lon), x + 3, height - 14, 8, "muted")
      index = index + 1
    end
    for lat = -80, 80, step do
      local _, y = project(0, lat)
      surface:rect("map-grid-lat-" .. lat, 0, y, width, 1, "muted", 0.10, 0)
      surface:text("map-label-lat-" .. lat, tostring(lat), 3, y + 2, 8, "muted")
    end
    local _ = index
  end

  local points = {}
  local labels = {}
  local features = {}
  local function flatten(feature)
    local geometry = feature.geometry or feature
    if geometry.type == "FeatureCollection" then
      for _, nested in ipairs(geometry.features or {}) do flatten(nested) end
    else
      features[#features + 1] = feature
    end
  end
  for _, feature in ipairs(self.features) do flatten(feature) end
  for feature_index, feature in ipairs(features) do
    local geometry = feature.geometry or feature
    local properties = feature.properties or {}
    local kind = geometry.type
    local coordinates = geometry.coordinates or {}
    if kind == "LineString" then
      local screen = ring(coordinates, project)
      surface:polyline("map-line-" .. feature_index, screen, self.opts.line_width,
        properties.ink or self.opts.line_ink, properties.opacity or 0.9, "round")
    elseif kind == "MultiLineString" then
      for part, line in ipairs(coordinates) do
        surface:polyline("map-line-" .. feature_index .. "-" .. part, ring(line, project),
          self.opts.line_width, properties.ink or self.opts.line_ink, properties.opacity or 0.9, "round")
      end
    elseif kind == "Polygon" then
      for part, line in ipairs(coordinates) do
        surface:polyline("map-poly-" .. feature_index .. "-" .. part, ring(line, project),
          self.opts.line_width, properties.ink or self.opts.line_ink, properties.opacity or 0.8, "round")
      end
    elseif kind == "MultiPolygon" then
      for polygon, rings in ipairs(coordinates) do
        for part, line in ipairs(rings) do
          surface:polyline("map-poly-" .. feature_index .. "-" .. polygon .. "-" .. part,
            ring(line, project), self.opts.line_width,
            properties.ink or self.opts.line_ink, properties.opacity or 0.8, "round")
        end
      end
    elseif kind == "Point" then
      local x, y = project(coordinates[1], coordinates[2])
      points[#points + 1] = { x, y }
      if properties.name then labels[#labels + 1] = { x = x, y = y, text = properties.name } end
    end
  end
  if #points > 0 then
    surface:points("map-points", points, self.opts.point_size, self.opts.point_ink, 0.95)
  end
  for index, label in ipairs(labels) do
    surface:text("map-place-" .. index, label.text, label.x + 6, label.y - 6, 9, "text")
  end
end

function map.methods:present()
  local width, height = ui.viewport(self.opts.width, self.opts.height)
  local theme = ui.theme(self.opts.theme)
  return ui.capture(width, height, theme, function(surface) self:render(surface) end)
end

return map
