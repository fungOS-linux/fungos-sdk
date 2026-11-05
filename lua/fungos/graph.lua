-- fungos.graph — a composable graph layer over the scene vocabulary.
--
-- Positions are data. Layout engines live outside this module; a snapshot may
-- provide x/y directly, or a host can run Barnes-Hut/GPU layout and feed the
-- result back. Rendering groups nodes by ink so a graph costs one points node
-- per colour instead of one node per node.

local ui = require("fungos.ui")

local graph = {}
graph.version = "0.1.0"

local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for key, item in pairs(value) do out[key] = copy(item) end
  return out
end

graph.defaults = {
  padding = 20,
  node_size = 6,
  edge_width = 1.4,
  edge_ink = "muted",
  edge_opacity = 0.28,
  node_ink = "primary",
  node_opacity = 0.9,
  labels = true,
}

function graph.new(opts)
  opts = opts or {}
  local out = copy(graph.defaults)
  for key, value in pairs(opts) do out[key] = value end
  return setmetatable({
    opts = out,
    nodes = opts.nodes or {},
    edges = opts.edges or {},
  }, { __index = graph.methods })
end

graph.methods = {}

function graph.methods:bounds()
  local xlo, xhi, ylo, yhi = math.huge, -math.huge, math.huge, -math.huge
  for _, node in ipairs(self.nodes) do
    local x, y = tonumber(node.x) or 0, tonumber(node.y) or 0
    xlo, xhi = math.min(xlo, x), math.max(xhi, x)
    ylo, yhi = math.min(ylo, y), math.max(yhi, y)
  end
  if xlo == math.huge then return 0, 1, 0, 1 end
  local span = math.max(xhi - xlo, yhi - ylo, 0.0001)
  local cx, cy = (xlo + xhi) / 2, (ylo + yhi) / 2
  return cx - span, cx + span, cy - span, cy + span
end

function graph.methods:render(surface, width, height)
  local viewport_w, viewport_h = ui.viewport(self.opts.width, self.opts.height)
  width, height = width or viewport_w, height or viewport_h
  surface = surface or ui.surface(width, height, ui.theme(self.opts.theme))
  local pad = self.opts.padding
  local plot_w, plot_h = math.max(1, width - pad * 2), math.max(1, height - pad * 2)
  local xlo, xhi, ylo, yhi = self:bounds()
  local sx = function(x) return pad + (x - xlo) / (xhi - xlo) * plot_w end
  local sy = function(y) return pad + (1 - (y - ylo) / (yhi - ylo)) * plot_h end
  local by_id = {}
  for _, node in ipairs(self.nodes) do by_id[tostring(node.id)] = node end

  for index, edge in ipairs(self.edges) do
    local a, b = by_id[tostring(edge.source)], by_id[tostring(edge.target)]
    if a and b then
      surface:polyline("graph-edge-" .. index, {
        { sx(tonumber(a.x) or 0), sy(tonumber(a.y) or 0) },
        { sx(tonumber(b.x) or 0), sy(tonumber(b.y) or 0) },
      }, self.opts.edge_width, edge.ink or self.opts.edge_ink, self.opts.edge_opacity, "round")
    end
  end

  local groups, labels = {}, {}
  for _, node in ipairs(self.nodes) do
    local ink = node.ink or self.opts.node_ink
    groups[ink] = groups[ink] or {}
    local x, y = sx(tonumber(node.x) or 0), sy(tonumber(node.y) or 0)
    groups[ink][#groups[ink] + 1] = { x, y }
    if self.opts.labels and node.label and node.label ~= "" then
      labels[#labels + 1] = { x = x, y = y, text = tostring(node.label) }
    end
  end
  for ink, points in pairs(groups) do
    surface:points("graph-nodes-" .. ink, points, self.opts.node_size, ink, self.opts.node_opacity)
  end
  for index, label in ipairs(labels) do
    surface:text("graph-label-" .. index, label.text, label.x + 7, label.y - 6, 9, "text")
  end
end

function graph.methods:present()
  local width, height = ui.viewport(self.opts.width, self.opts.height)
  local theme = ui.theme(self.opts.theme)
  return ui.capture(width, height, theme, function(surface) self:render(surface) end)
end

return graph
