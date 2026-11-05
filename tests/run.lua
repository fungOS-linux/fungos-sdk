-- Minimal Lua tests for the SDK. No external test framework.

local function load_module(path)
  local chunk = assert(loadfile(path))
  return chunk()
end

local ui = load_module("lua/fungos/ui.lua")
local config = load_module("lua/fungos/config.lua")
local compose = load_module("lua/fungos/compose.lua")
local action = load_module("lua/fungos/action.lua")

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

-- config hide/order
local hidden = config.hidden({ hide = { "rail.tags", "rail.footer" } })
ok(hidden["rail.tags"] and hidden["rail.footer"], "hide set should contain entries")
local children = { { id = "b" }, { id = "a" }, { id = "c" } }
config.order_children(children, { "a", "b" })
ok(children[1].id == "a" and children[2].id == "b" and children[3].id == "c", "order should rank listed ids first")

print(string.format("sdk lua: %d assertions passed", passed))
