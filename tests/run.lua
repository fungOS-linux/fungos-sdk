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
