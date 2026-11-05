-- Minimal Lua tests for the SDK. No external test framework.

local function load_module(path)
  local chunk = assert(loadfile(path))
  return chunk()
end

local ui = load_module("lua/fungos/ui.lua")
local config = load_module("lua/fungos/config.lua")
local compose = load_module("lua/fungos/compose.lua")
local action = load_module("lua/fungos/action.lua")
local validate = load_module("lua/fungos/validate.lua")
package.loaded["fungos.ui"] = ui
local chart = load_module("lua/fungos/chart.lua")
local viz = load_module("lua/fungos/viz.lua")
local graph = load_module("lua/fungos/graph.lua")
local map = load_module("lua/fungos/map.lua")
local atlas = load_module("lua/fungos/atlas.lua")

local passed = 0
local function ok(value, message)
  if not value then error(message or "assertion failed", 2) end
  passed = passed + 1
end

-- profile precedence: global < app < explicit
local profile = config.normalize({
  density = "compact",
  theme = { radius = 6 },
  apps = { ["dev.fungos.unibus"] = { density = "spacious", theme = { radius = 12 } } },
})
local resolved = config.for_app(profile, "dev.fungos.unibus")
ok(resolved.density == "spacious", "app density should win")
ok(resolved.theme.radius == 12, "app theme should merge")
ok(profile.density == "compact", "normalize should not mutate the source")

-- slots/components
local registry = compose.registry()
registry:add({
  name = "test.components",
  components = {
    ["test.row"] = function(ctx, props) return ui.text("row", props.label, { size = 12 }) end,
  },
  slots = {
    ["toolbar.end"] = function(ctx) return ui.text("slot", "custom", { size = 10 }) end,
  },
  theme = { radius = 14 },
})
local tree = ui.column("root", {}, {
  ui.component("test.row", { label = "hello" }),
  ui.slot("toolbar.end", ui.text("fallback", "fallback", { size = 10 })),
})
local resolved_tree = compose.apply(tree, registry, {})
ok(resolved_tree.children[1].id == "row", "component should resolve")
ok(resolved_tree.children[2].id == "slot", "slot should resolve")
ok(registry:resolve_theme({ radius = 2 }).radius == 14, "rice theme should merge")

-- missing component falls back
local fallback = ui.text("fallback", "fallback", { size = 10 })
local missing = compose.apply(ui.component("missing.row", { id = "x" }, nil, fallback), registry, {})
ok(missing.id == "fallback", "missing component should use fallback")

-- action intent shape
local intent = action.intent("mail.archive", { thread_id = "x" })
ok(action.valid(intent), "action intent should be valid")
ok(not action.valid({ action = "" }), "empty action id should be invalid")

-- action bar accessibility contract
local bar = ui.action_bar("app-actions", {
  { id = "run", label = "Run", shortcut = "ctrl+enter", action = action.intent("elmers.run", { workflow_id = "crm/leads" }) },
  { separator = true },
  { id = "approve", label = "Approve", confirm = true, disabled = true, disabled_reason = "No pending approval" },
  { spacer = true },
  { id = "refresh", label = "Refresh", action = action.intent("elmers.refresh") },
}, { label = "Elmers actions" })
ok(bar.role == "toolbar", "action bar should be a toolbar")
ok(bar.a11y.role == "toolbar", "action bar should expose a11y role")
ok(bar.a11y.label == "Elmers actions", "action bar should expose a11y label")
ok(bar.children[1].role == "button", "action should be a button")
ok(bar.children[1].shortcut == "ctrl+enter", "shortcut should be retained")
ok(bar.children[1].action.action == "elmers.run", "action intent should be retained")
ok(bar.children[3].confirm == true, "confirm hint should be retained")
ok(bar.children[3].a11y.disabled == true, "disabled state should be exposed")
ok(bar.children[3].a11y.disabled_reason == "No pending approval", "disabled reason should be exposed")
ok(bar.children[4].kind == "spacer", "spacer should be preserved")

-- action bar from a Canvas/DCP catalog
local catalog_bar = ui.action_bar_from_catalog("catalog-actions", {
  { id = "lights.on", label = "Lights on", description = "Turn lab lights on",
    input_schema = "{}", requires_input = false, effect = "write",
    idempotency = "idempotent", confirmation = "none", available = true,
    provider = "unibus-hue", catalog_revision = "cat-1", state_revision = "state-1" },
  { id = "lights.level", label = "Set level", input_schema = "{\"type\":\"object\",\"properties\":{\"level\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":100}}}",
    requires_input = true, effect = "write", idempotency = "keyed",
    confirmation = "none", available = true },
  { id = "mail.send", label = "Send mail", input_schema = "{}", requires_input = false,
    effect = "external", idempotency = "unsafe", confirmation = "destructive",
    available = false, reason = "No account" },
}, { label = "Available actions" })
ok(catalog_bar.role == "toolbar", "catalog bar should be a toolbar")
ok(catalog_bar.children[1].action.action == "lights.on", "catalog action should become an intent")
ok(catalog_bar.children[1].source == "unibus-hue", "provider should be retained")
ok(catalog_bar.children[2].needs_input == true, "parameter action should request input")
ok(catalog_bar.children[2].input_schema:find("maximum", 1, true) ~= nil, "input schema should be retained")
ok(catalog_bar.children[3].disabled == true, "unavailable action should be disabled")
ok(catalog_bar.children[3].disabled_reason == "No account", "unavailable reason should be retained")
ok(catalog_bar.children[3].confirm == true, "destructive action should confirm")
ok(catalog_bar.children[3].danger == true, "external action should be marked dangerous")

-- config hide/order
local hidden = config.hidden({ hide = { "rail.tags", "rail.footer" } })
ok(hidden["rail.tags"] and hidden["rail.footer"], "hide set should contain entries")
local children = { { id = "b" }, { id = "a" }, { id = "c" } }
config.order_children(children, { "a", "b" })
ok(children[1].id == "a" and children[2].id == "b" and children[3].id == "c", "order should rank listed ids first")


-- Chart DSL is a normal scene producer: pure input, no host chart API.
local fleet = chart.new { title = "Fleet", width = 400, height = 300 }
fleet:line { id = "p50", ink = "success", points = { { 0, 40 }, { 1, 44 }, { 2, 41 } } }
local chart_present, chart_hits = fleet:present()
ok(chart_present.kind == "scene", "chart returns a scene present")
ok(#chart_present.nodes > 12, "chart emits title, axes, grid and line nodes")
ok(#chart_hits == 0, "chart has no hidden hit targets")
local line_nodes = {}
for _, node in ipairs(chart_present.nodes) do
  if node.type == "polyline" then line_nodes[#line_nodes + 1] = node end
end
ok(#line_nodes == 1, "line series emits one polyline")
ok(line_nodes[1].join == "round", "lines default to round joins")

-- LTTB keeps endpoints and the dominant shape point without a TypeScript runtime.
local dense = {}
for index = 1, 5000 do
  local x = index / 5000
  dense[index] = { x = x, y = math.sin(x * 20) + (index == 2500 and 4 or 0) }
end
local reduced = chart.lttb(dense, 200)
ok(#reduced == 200, "lttb should honor the threshold")
ok(reduced[1] == dense[1] and reduced[#reduced] == dense[#dense], "lttb keeps endpoints")
local spike = false
for _, point in ipairs(reduced) do
  if point == dense[2500] then spike = true end
end
ok(spike, "lttb keeps a dominant spike")
ok(#chart.lttb(dense, 6000) == 5000, "lttb leaves small series alone")

local catalog = chart.new {
  title = "Catalog", width = 500, height = 340,
  crosshair = { x = 1, y = 2 },
  annotations = { { x = 1, y = 3, label = "note" } },
}
catalog:scatter { id = "cloud", points = { { 0, 1 }, { 1, 2 }, { 2, 1 } }, size = 4 }
catalog:heatmap { id = "field", rows = 2, cols = 2, values = { 0, 1, 2, 3 } }
catalog:candles { id = "ohlc", candles = {
  { x = 1, open = 2, high = 4, low = 1, close = 3 },
  { x = 2, open = 3, high = 5, low = 2, close = 2.5 },
} }
local catalog_present = catalog:present()
local catalog_types = {}
for _, node in ipairs(catalog_present.nodes) do catalog_types[node.type] = true end
ok(catalog_types.points, "scatter emits one points primitive")
ok(catalog_types.heatmap, "heatmap emits one heatmap primitive")
ok(catalog_types.candles, "candles emit one candles primitive")
ok(catalog_types.rect, "crosshair and annotations use ordinary scene primitives")
local windowed = chart.window({ { 1 }, { 2 }, { 3 }, { 4 } }, 2)
ok(#windowed == 2 and windowed[1][1] == 3 and windowed[2][1] == 4, "window keeps the newest points")

-- Chart navigator is pure viewport math: host input in, data domains out.
local nav = chart.navigator():set_bounds(0, 100, 0, 50)
local xdom, ydom = nav:view()
ok(xdom.min == 0 and xdom.max == 100, "navigator starts at full x bounds")
nav:feed { kind = "scroll", x = 0.5, y = 0.5, dy = -200 }
xdom, ydom = nav:view()
ok(xdom.max - xdom.min < 100, "wheel zooms in")
nav:feed { kind = "key", key = "r" }
xdom = nav:view()
ok(math.abs((xdom.max - xdom.min) - 100) < 0.001, "r resets zoom")
nav:feed { kind = "pointer", phase = "press", x = 0.2, y = 0.2, shift = true, at_ms = 10 }
nav:feed { kind = "pointer", phase = "move", x = 0.6, y = 0.6, shift = true, at_ms = 20 }
nav:feed { kind = "pointer", phase = "release", x = 0.6, y = 0.6, shift = true, at_ms = 30 }
xdom, ydom = nav:view()
ok(xdom.max - xdom.min < 60, "shift-drag zooms to the selected x range")
ok(ydom.max - ydom.min < 50, "shift-drag zooms to the selected y range")
nav:feed { kind = "pointer", phase = "press", x = 0.5, y = 0.5, at_ms = 1000 }
nav:feed { kind = "pointer", phase = "press", x = 0.5, y = 0.5, at_ms = 1200 }
xdom = nav:view()
ok(math.abs((xdom.max - xdom.min) - 100) < 0.001, "double press resets the view")
nav:feed { kind = "pointer", phase = "press", x = 0.5, y = 0.5, at_ms = 2000 }
nav:feed { kind = "pointer", phase = "move", x = 0.7, y = 0.5, at_ms = 2010 }
nav:feed { kind = "pointer", phase = "release", x = 0.7, y = 0.5, at_ms = 2020 }
xdom = nav:view()
ok(math.abs((xdom.max - xdom.min) - 100) < 0.001, "plain drag pans without changing span")

-- Charts compose as Lua components: a dashboard places ordinary chart objects
-- in cells without a second renderer or host ABI.
local dash = chart.dashboard { columns = 2, gap = 8, width = 800, height = 500, charts = {
  chart.new({ title = "left", width = 400, height = 250, padding = { top = 28, right = 12, bottom = 24, left = 36 } })
    :line { id = "l", points = { { 0, 1 }, { 1, 3 }, { 2, 2 } } },
  chart.new({ title = "right", width = 400, height = 250, padding = { top = 28, right = 12, bottom = 24, left = 36 } })
    :line { id = "r", points = { { 0, 2 }, { 1, 1 }, { 2, 3 } } },
} }
local dash_present = dash:present()
ok(dash_present.kind == "scene", "dashboard returns one scene")
ok(#dash_present.nodes > 30, "dashboard combines both chart trees")
local dash_rects = 0
for _, node in ipairs(dash_present.nodes) do
  if node.type == "rect" then dash_rects = dash_rects + 1 end
end
ok(dash_rects > 20, "dashboard keeps child primitives")

-- Runtime layer composition: chart, graph, map and atlas do not know about each
-- other, but share one scene and one subsurface prefix.
local compose_scene = viz.scene { width = 800, height = 600, gap = 6 }
compose_scene:add(chart.new { title = "c" }:line { id = "l", points = { { 0, 1 }, { 1, 2 }, { 2, 1 } } },
  { x = 0, y = 0, width = 0.5, height = 0.5 })
compose_scene:add(graph.new {
  nodes = { { id = "a", x = 0, y = 0 }, { id = "b", x = 1, y = 1, label = "B" } },
  edges = { { source = "a", target = "b" } },
}, { x = 0.5, y = 0, width = 0.5, height = 0.5 })
compose_scene:add(map.new {
  zoom = 1,
  features = { { type = "Feature", properties = { name = "p" }, geometry = { type = "Point", coordinates = { 0, 0 } } } },
}, { x = 0, y = 0.5, width = 0.5, height = 0.5 })
compose_scene:add(atlas.new {
  points = { { 0.2, 0.3, ink = "info" }, { 0.8, 0.7, ink = "success" } },
}, { x = 0.5, y = 0.5, width = 0.5, height = 0.5 })
local compose_present = compose_scene:present()
ok(compose_present.kind == "scene", "viz scene returns one scene")
ok(#compose_present.nodes > 40, "viz scene contains all four layers")
local compose_ids = {}
for _, node in ipairs(compose_present.nodes) do
  ok(not compose_ids[node.id], "viz layer ids are unique: " .. tostring(node.id))
  compose_ids[node.id] = true
end
ok((compose_ids["chart-1-chart-title"] or compose_ids["layer-1-chart-title"]) ~= nil, "chart layer is namespaced")

-- A view that calls ui.surface can be captured as a portable soil_scene
-- payload without calling canvas.rect/text or widget.hit.
_G.canvas = {
  layout = function(_, width, height)
    return {
      nodes = {
        { id = "title", kind = "text", text = "Captured", style = { size = 16 },
          rect = { x = 10, y = 12, width = 160, height = 20 } },
        { id = "underline", kind = "rule", rect = { x = 10, y = 36, width = 160, height = 1 } },
      },
    }
  end,
}
_G.widget = { hit = function() error("capture must not call widget.hit") end }
local present, hits = ui.capture(800, 600, { body = 16 }, function(surface)
  surface = surface or ui.surface(800, 600, { body = 16 })
  surface:background("background")
  local laid = ui.layout({ id = "root", kind = "container" }, 800, 600)
  ui.paint_text(surface, laid)
  surface:rect("accent", 20, 20, 30, 30, "primary", 0.5, 4)
  surface:hit("accent", { x = 20, y = 20, width = 30, height = 30 })
end)
ok(present.kind == "scene", "capture should return a scene present")
ok(present.schema == 1, "capture should use the soil scene schema")
ok(#present.nodes == 3, "capture should include background, text and rect")
ok(present.nodes[1].type == "rect" and present.nodes[1].ink == "background", "background is a rect node")
ok(present.nodes[2].type == "text" and present.nodes[2].text == "Captured", "text is a text node")
ok(present.nodes[2].transform.scale[1] > 0, "text carries a scale, not a font size")
ok(present.nodes[3].type == "rect" and present.nodes[3].opacity == 0.5, "rect carries opacity")
ok(#hits == 1 and hits[1].id == "accent", "hit targets are captured beside the scene")
ok(hits[1].x < 0 and hits[1].width > 0, "hit target is in normalized space")

-- validator catches the failures Canvas would reject
local function fails(fn, needle)
  local passed, err = pcall(fn)
  ok(not passed, "expected validation failure: " .. tostring(needle))
  if needle then
    ok(tostring(err):find(needle, 1, true), "expected error containing " .. needle .. ", got " .. tostring(err))
  end
end

local valid = ui.column("root", {}, {
  ui.text("body", "ok", { size = 12 }),
})
validate.tree(valid)

local workspace = ui.workspace("ws", { width = 800, height = 600 }, {
  ui.sidebar("side", { width = 160 }, {
    ui.sidebar_group("groups", "SPLIT", {
      { id = "important", label = "Important", count = 3, selected = true },
    }),
  }),
  ui.pane("main", { pane_id = "main", focused = true }, {
    ui.tabbar("tabs", {
      { id = "important", label = "Important", unread = 3, selected = true },
      { id = "other", label = "Other", unread = 8 },
    }),
    ui.command_palette("palette", {}, {
      ui.command_item("archive", "Archive", { keys = "E" }),
    }),
  }),
})
validate.tree(workspace)

fails(function()
  validate.tree({ id = "root", kind = "container", children = { { id = "a", kind = "text", text = "", style = { size = 12 } } } })
end, "empty or whitespace")

fails(function()
  validate.tree({ id = "root", kind = "container", children = { { id = "a", kind = "text", text = "ok", style = { size = 12 } }, { id = "a", kind = "text", text = "again", style = { size = 12 } } } })
end, "duplicate node id")

fails(function()
  local sparse = { id = "root", kind = "container", children = {} }
  sparse.children[2] = { id = "a", kind = "text", text = "ok", style = { size = 12 } }
  validate.tree(sparse)
end, "sparse")

fails(function()
  validate.tree({ id = "root", kind = "container", children = { { id = "a", kind = "text", text = "bad\ntext", style = { size = 12 } } } })
end, "control character")

print(string.format("sdk lua: %d assertions passed", passed))
