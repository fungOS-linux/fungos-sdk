-- fungos.viz — runtime composition for visualization layers.
--
-- A layer is any table with `render(surface, width, height)`. Charts, graphs,
-- maps, atlases and plain `fungos.ui` components all fit that shape. The scene
-- owns placement and sub-surfaces; it does not know what the layers mean.

local ui = require("fungos.ui")

local viz = {}

local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for key, item in pairs(value) do out[key] = copy(item) end
  return out
end

local function rect(value)
  value = value or {}
  return {
    x = tonumber(value.x) or 0,
    y = tonumber(value.y) or 0,
    width = tonumber(value.width or value.w) or 1,
    height = tonumber(value.height or value.h) or 1,
  }
end

--- Wrap a render function as a layer.
function viz.layer(id, render, opts)
  if type(render) ~= "function" then error("viz.layer needs a render function", 2) end
  opts = opts or {}
  return {
    id = id,
    render = render,
    rect = rect(opts.rect or opts),
  }
end

--- A runtime layer stack on one Canvas surface.
function viz.scene(opts)
  opts = copy(opts or {})
  local scene = {
    opts = opts,
    layers = {},
  }

  function scene:add(component, placement)
    if type(component) ~= "table" or type(component.render) ~= "function" then
      error("viz.scene:add needs a layer with render(surface, width, height)", 2)
    end
    local layer = component
    if placement then layer.rect = rect(placement) end
    layer.rect = layer.rect or rect()
    layer.id = layer.id or ("layer-" .. (#self.layers + 1))
    self.layers[#self.layers + 1] = layer
    return self
  end

  function scene:render(surface)
    local width, height = ui.viewport(self.opts.width, self.opts.height)
    surface = surface or ui.surface(width, height, ui.theme(self.opts.theme))
    local gap = tonumber(self.opts.gap) or 0
    for _, layer in ipairs(self.layers) do
      local r = layer.rect
      local x = r.x * width
      local y = r.y * height
      local w = math.max(1, r.width * width - gap)
      local h = math.max(1, r.height * height - gap)
      local sub = ui.subsurface(surface, x, y, w, h, (layer.id or "layer") .. "-")
      layer:render(sub, w, h)
    end
  end

  function scene:present()
    local width, height = ui.viewport(self.opts.width, self.opts.height)
    local theme = ui.theme(self.opts.theme)
    return ui.capture(width, height, theme, function(surface) self:render(surface) end)
  end

  return scene
end

return viz
