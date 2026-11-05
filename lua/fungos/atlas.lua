-- fungos.atlas — dense embedding / point-cloud layer.
--
-- The atlas is a density field plus points, which is the useful shape from
-- Apple's Embedding Atlas without importing its TypeScript runtime. Contours and
-- clustering can arrive as another layer; this one owns the scatter and KDE.

local ui = require("fungos.ui")

local atlas = {}
atlas.version = "0.1.0"

local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for key, item in pairs(value) do out[key] = copy(item) end
  return out
end

atlas.defaults = {
  padding = 18,
  point_size = 3,
  point_ink = "info",
  point_opacity = 0.65,
  density = true,
  density_rows = 32,
  density_cols = 48,
  density_opacity = 0.55,
  labels = true,
}

function atlas.new(opts)
  opts = opts or {}
  local out = copy(atlas.defaults)
  for key, value in pairs(opts) do out[key] = value end
  return setmetatable({
    opts = out,
    points = opts.points or {},
  }, { __index = atlas.methods })
end

atlas.methods = {}

function atlas.methods:bounds()
  local xlo, xhi, ylo, yhi = math.huge, -math.huge, math.huge, -math.huge
  for _, p in ipairs(self.points) do
    local x, y = tonumber(p.x or p[1]) or 0, tonumber(p.y or p[2]) or 0
    xlo, xhi = math.min(xlo, x), math.max(xhi, x)
    ylo, yhi = math.min(ylo, y), math.max(yhi, y)
  end
  if xlo == math.huge then return 0, 1, 0, 1 end
  if xlo == xhi then xhi = xlo + 1 end
  if ylo == yhi then yhi = ylo + 1 end
  return xlo, xhi, ylo, yhi
end

function atlas.methods:render(surface, width, height)
  local viewport_w, viewport_h = ui.viewport(self.opts.width, self.opts.height)
  width, height = width or viewport_w, height or viewport_h
  surface = surface or ui.surface(width, height, ui.theme(self.opts.theme))
  surface:background("background")
  local pad = self.opts.padding
  local plot_w, plot_h = math.max(1, width - pad * 2), math.max(1, height - pad * 2)
  local xlo, xhi, ylo, yhi = self:bounds()
  local sx = function(x) return pad + (x - xlo) / (xhi - xlo) * plot_w end
  local sy = function(y) return pad + (1 - (y - ylo) / (yhi - ylo)) * plot_h end

  if self.opts.density then
    local rows, cols = self.opts.density_rows, self.opts.density_cols
    local values = {}
    for i = 1, rows * cols do values[i] = 0 end
    for _, p in ipairs(self.points) do
      local x, y = sx(tonumber(p.x or p[1]) or 0), sy(tonumber(p.y or p[2]) or 0)
      local col = math.floor((x - pad) / plot_w * cols) + 1
      local row = math.floor((y - pad) / plot_h * rows) + 1
      col, row = math.max(1, math.min(cols, col)), math.max(1, math.min(rows, row))
      values[(row - 1) * cols + col] = values[(row - 1) * cols + col] + 1
    end
    surface:heatmap("atlas-density", values, rows, cols, pad, pad, plot_w, plot_h,
      0, math.max(1, #self.points / 8), self.opts.density_opacity)
  end

  local groups = {}
  local labels = {}
  for _, p in ipairs(self.points) do
    local ink = p.ink or self.opts.point_ink
    groups[ink] = groups[ink] or {}
    local x, y = sx(tonumber(p.x or p[1]) or 0), sy(tonumber(p.y or p[2]) or 0)
    groups[ink][#groups[ink] + 1] = { x, y }
    if self.opts.labels and p.label then labels[#labels + 1] = { x = x, y = y, text = p.label } end
  end
  for ink, points in pairs(groups) do
    surface:points("atlas-points-" .. ink, points, self.opts.point_size, ink, self.opts.point_opacity)
  end
  for index, label in ipairs(labels) do
    surface:text("atlas-label-" .. index, label.text, label.x + 5, label.y - 5, 9, "text")
  end
end

function atlas.methods:present()
  local width, height = ui.viewport(self.opts.width, self.opts.height)
  local theme = ui.theme(self.opts.theme)
  return ui.capture(width, height, theme, function(surface) self:render(surface) end)
end

return atlas
