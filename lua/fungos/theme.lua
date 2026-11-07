-- The theme a Lua module receives, mirroring ModuleThemeTokens in Canvas
-- (crates/canvas/src/lua_module.rs, theme_to_lua).
--
-- Colour values are deliberate neutral stand-ins, not the brand palette. The
-- palette is generated from Coherence tokens inside canvas-core, and tend is a
-- development tool in another repository, so it cannot own that source of truth.
-- What is load-bearing here is the key set and the types: a view that reads
-- theme.<token> must resolve instead of silently getting nil, because nil is what
-- becomes a blank panel in production. Pass --theme <file.lua> to preflight
-- against a real exported palette instead.

local theme = {}

theme.schema = 1

theme.tokens = {
  mode = "dark",
  accent = "brand",

  background = { 24, 24, 27 },
  surface = { 32, 32, 36 },
  text = { 236, 236, 238 },
  muted = { 138, 138, 146 },
  primary = { 92, 148, 255 },
  success = { 74, 180, 110 },
  warning = { 216, 168, 64 },
  danger = { 214, 84, 84 },

  space_2 = 8,
  radius = 8,

  micro = 10,
  small = 12,
  body = 14,
  large = 18,
  title = 22,
  display = 28,
  hero = 34,
}

--- Every token Canvas sets, sorted. Tests assert this list rather than the
--- values, so a change to the stand-in palette does not break the suite.
theme.keys = {}
for key in pairs(theme.tokens) do theme.keys[#theme.keys + 1] = key end
table.sort(theme.keys)

--- The colour tokens, as opposed to the metric tokens.
theme.colour_keys = {}
for _, key in ipairs(theme.keys) do
  if type(theme.tokens[key]) == "table" then theme.colour_keys[#theme.colour_keys + 1] = key end
end

--- Wrap tokens so an unknown read fails loudly instead of yielding nil.
---
--- Canvas sets every documented key, so a missing one is always a spelling
--- mistake or a stale copy of the contract. Failing in the edit loop names the
--- token and lists the alternatives; failing in production shows a blank panel.
function theme.strict(tokens)
  local available = {}
  for key in pairs(tokens or {}) do available[#available + 1] = key end
  table.sort(available)
  return setmetatable(tokens or {}, {
    __index = function(_, key)
      error("unknown theme token: " .. tostring(key)
        .. " (available: " .. table.concat(available, ", ") .. ")", 2)
    end,
  })
end

return theme
