-- Tests for the theme a Lua module receives.
--
-- The contract is the key set and the types, mirroring ModuleThemeTokens in
-- Canvas. Values are stand-ins, so these cases assert shape and strictness
-- rather than exact colours: a palette change must not fail the suite, but a
-- dropped or renamed token must.

return function(T, root)
  local theme = dofile(root .. "/lua/fungos/theme.lua")

  -- Exactly what canvas/src/lua_module.rs theme_to_lua sets.
  local CANVAS_TOKENS = {
    "accent", "background", "body", "danger", "display", "hero", "large",
    "micro", "mode", "muted", "primary", "radius", "small", "space_2",
    "success", "surface", "text", "title", "warning",
  }

  local COLOUR_TOKENS = {
    "background", "danger", "muted", "primary", "success", "surface", "text", "warning",
  }

  local function key_list(table_value)
    local list = {}
    for key in pairs(table_value) do list[#list + 1] = key end
    table.sort(list)
    return list
  end

  local function same_list(actual, expected, label)
    T.equal(#actual, #expected, label .. " count")
    for index = 1, #expected do
      if actual[index] ~= expected[index] then
        error(string.format("%s %d: expected %s, got %s",
          label, index, expected[index], tostring(actual[index])), 2)
      end
    end
  end

  return {
    name = "theme",
    cases = {
      { name = "exposes exactly the tokens Canvas sets", fn = function()
        same_list(key_list(theme.tokens), CANVAS_TOKENS, "token")
      end },

      { name = "theme.keys is the same complete sorted list", fn = function()
        same_list(theme.keys, CANVAS_TOKENS, "key")
      end },

      { name = "colour tokens are the documented eight", fn = function()
        same_list(theme.colour_keys, COLOUR_TOKENS, "colour token")
      end },

      { name = "mode and accent are the documented enum strings", fn = function()
        T.truthy(theme.tokens.mode == "light" or theme.tokens.mode == "dark",
          "mode is " .. tostring(theme.tokens.mode))
        local accents = { brand = true, info = true, success = true }
        T.truthy(accents[theme.tokens.accent] == true,
          "accent is " .. tostring(theme.tokens.accent))
      end },

      { name = "colour tokens are 0..255 rgb triples", fn = function()
        for _, key in ipairs(COLOUR_TOKENS) do
          local value = theme.tokens[key]
          T.equal(#value, 3, key .. " component count")
          for index = 1, 3 do
            local component = value[index]
            T.truthy(type(component) == "number", key .. " component type")
            T.truthy(component >= 0 and component <= 255 and component % 1 == 0,
              key .. " component range")
          end
        end
      end },

      { name = "metric tokens are positive numbers", fn = function()
        for _, key in ipairs(theme.keys) do
          if type(theme.tokens[key]) == "number" then
            T.truthy(theme.tokens[key] > 0, key .. " should be positive")
          end
        end
      end },

      { name = "strict returns a known token", fn = function()
        local strict = theme.strict(theme.tokens)
        T.equal(strict.body, theme.tokens.body, "body")
        T.equal(strict.mode, "dark", "mode")
      end },

      { name = "strict names an unknown token instead of returning nil", fn = function()
        local strict = theme.strict(theme.tokens)
        T.error_matches(function() return strict.bogus end, "unknown theme token: bogus")
      end },

      { name = "strict lists the available tokens in the error", fn = function()
        local strict = theme.strict({ body = 14 })
        T.error_matches(function() return strict.nope end, "available: body")
      end },

      { name = "strict still allows iteration", fn = function()
        -- A __index that errors must not break pairs(); helpers walk themes.
        local strict = theme.strict({ body = 14, radius = 8 })
        local count = 0
        for _ in pairs(strict) do count = count + 1 end
        T.equal(count, 2, "iterated keys")
      end },
    },
  }
end
