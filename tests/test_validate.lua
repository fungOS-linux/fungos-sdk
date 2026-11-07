-- Tests for fungos.validate — the preflight that runs before every reload.
--
-- The tool's whole claim is that it catches these classes of mistake in the
-- edit loop instead of letting Canvas reject them at runtime. Each case is one
-- documented class, so a rule that stops firing fails here rather than in a
-- Spore author's afternoon.

return function(T, root)
  local validate = dofile(root .. "/lua/fungos/validate.lua")

  local function text_node(id, text)
    return { id = id, kind = "text", text = text, style = { size = 14 } }
  end

  local function box(id, children)
    return { id = id, kind = "container", children = children }
  end

  local function rejects(node, needle)
    return function() T.error_matches(function() validate.tree(node) end, needle) end
  end

  return {
    name = "validate",
    cases = {
      -- shape -------------------------------------------------------------
      { name = "tree rejects a non-table", fn = function()
        T.error_matches(function() validate.tree(nil) end, "tree must be a table")
      end },

      { name = "tree rejects a node that is not a table", fn = function()
        T.error_matches(function() validate.tree(box("root", { 42 })) end,
          "must be a table, got number")
      end },

      { name = "tree rejects a cycle", fn = function()
        local root = box("root")
        root.children = { root }
        T.error_matches(function() validate.tree(root) end, "cycle or reused table")
      end },

      { name = "tree rejects a table reused in two branches", fn = function()
        -- Reusing one table is how a Spore accidentally ships the same widget
        -- twice with the same id; catching it here names the real cause.
        local shared = box("shared")
        T.error_matches(function()
          validate.tree(box("root", { shared, shared }))
        end, "cycle or reused table")
      end },

      { name = "tree rejects an empty id", fn = function()
        T.error_matches(function() validate.tree({ id = "", kind = "container" }) end,
          "non-empty string id")
      end },

      { name = "tree rejects a non-string id", fn = function()
        T.error_matches(function() validate.tree({ id = 7, kind = "container" }) end,
          "non-empty string id")
      end },

      { name = "tree rejects an overlong id", fn = function()
        T.error_matches(function()
          validate.tree({ id = string.rep("x", 161), kind = "container" })
        end, "too long")
      end },

      { name = "tree rejects a duplicate id", fn = function()
        T.error_matches(function()
          validate.tree(box("root", { box("dup"), box("dup") }))
        end, "duplicate node id dup")
      end },

      { name = "tree rejects an unknown kind", fn = function()
        T.error_matches(function()
          validate.tree({ id = "root", kind = "bogus" })
        end, "kind is invalid: bogus")
      end },

      -- children ----------------------------------------------------------
      { name = "tree rejects a sparse children array", fn = function()
        T.error_matches(function()
          validate.tree({ id = "root", kind = "container",
            children = { [1] = box("a"), [3] = box("c") } })
        end, "is sparse")
      end },

      { name = "tree rejects a non-array key in children", fn = function()
        T.error_matches(function()
          validate.tree({ id = "root", kind = "container",
            children = { first = box("a") } })
        end, "non-array key")
      end },

      { name = "tree rejects children that are not a table", fn = function()
        T.error_matches(function()
          validate.tree({ id = "root", kind = "container", children = "nope" })
        end, "must be an array")
      end },

      -- layout ------------------------------------------------------------
      { name = "tree rejects a non-table layout", fn = function()
        T.error_matches(function()
          validate.tree({ id = "root", kind = "container", layout = 3 })
        end, "layout must be a table")
      end },

      { name = "tree rejects a non-finite layout number", fn = function()
        T.error_matches(function()
          validate.tree({ id = "root", kind = "container", layout = { width = math.huge } })
        end, "width must be a finite number")
      end },

      { name = "tree rejects a negative width", fn = function()
        T.error_matches(function()
          validate.tree({ id = "root", kind = "container", layout = { width = -1 } })
        end, "width must be non-negative")
      end },

      { name = "tree rejects negative padding", fn = function()
        T.error_matches(function()
          validate.tree({ id = "root", kind = "container",
            layout = { padding = { top = -2 } } })
        end, "padding.top must be a finite non-negative number")
      end },

      { name = "tree rejects a layout that is not a table", fn = function()
        T.error_matches(function()
          validate.tree({ id = "root", kind = "container", layout = "wide" })
        end, "layout must be a table")
      end },

      -- text --------------------------------------------------------------
      { name = "text requires a style", fn = function()
        T.error_matches(function()
          validate.tree({ id = "t", kind = "text", text = "hello" })
        end, "style is required for text")
      end },

      { name = "text requires style.size", fn = function()
        T.error_matches(function()
          validate.tree({ id = "t", kind = "text", text = "hello", style = {} })
        end, "style.size is required for text")
      end },

      { name = "text rejects an empty string", fn = function()
        T.error_matches(function() validate.tree(text_node("t", "")) end,
          "must not be empty or whitespace")
      end },

      { name = "text rejects whitespace only", fn = function()
        T.error_matches(function() validate.tree(text_node("t", "   ")) end,
          "must not be empty or whitespace")
      end },

      { name = "text rejects a control character", fn = function()
        T.error_matches(function() validate.tree(text_node("t", "a\tb")) end,
          "non-printable control character")
      end },

      { name = "text rejects invalid UTF-8", fn = function()
        T.error_matches(function() validate.tree(text_node("t", "a\255b")) end,
          "must be valid UTF-8")
      end },

      { name = "a container needs no style", fn = function()
        validate.tree(box("root"))
      end },

      -- text_input -------------------------------------------------------
      { name = "text_input requires a string value", fn = function()
        T.error_matches(function()
          validate.tree({ id = "i", kind = "text_input", value = 1, style = { size = 12 } })
        end, "value must be a string")
      end },

      { name = "text_input rejects NUL", fn = function()
        T.error_matches(function()
          validate.tree({ id = "i", kind = "text_input", value = "a\0b", style = { size = 12 } })
        end, "value contains NUL")
      end },

      { name = "text_input requires a boolean multiline", fn = function()
        T.error_matches(function()
          validate.tree({ id = "i", kind = "text_input", value = "ok",
            multiline = "yes", style = { size = 12 } })
        end, "multiline must be a boolean")
      end },

      { name = "text_input requires a style", fn = function()
        T.error_matches(function()
          validate.tree({ id = "i", kind = "text_input", value = "ok" })
        end, "style is required for text_input")
      end },

      -- component -------------------------------------------------------
      { name = "component requires a name", fn = function()
        T.error_matches(function()
          validate.tree({ id = "c", kind = "component" })
        end, "name is required for component")
      end },

      -- host objects ----------------------------------------------------
      { name = "tree rejects a function in a node", fn = function()
        T.error_matches(function()
          validate.tree({ id = "root", kind = "container", render = function() end })
        end, "contains a function")
      end },

      -- limits ----------------------------------------------------------
      { name = "tree rejects nesting past the depth limit", fn = function()
        local root_node = { id = "n1", kind = "container" }
        local cursor = root_node
        for i = 2, 70 do
          local child = { id = "n" .. i, kind = "container" }
          cursor.children = { child }
          cursor = child
        end
        T.error_matches(function() validate.tree(root_node) end, "exceeds max depth")
      end },

      { name = "tree returns the tree it validated", fn = function()
        local tree = box("root", { text_node("t", "hi") })
        T.equal(validate.tree(tree), tree, "same table back")
      end },

      -- validate.errors ---------------------------------------------------
      { name = "errors stays quiet for a valid tree", fn = function()
        local problems, capped = validate.errors(box("root", { text_node("t", "hi") }))
        T.equal(#problems, 0, "problem count")
        T.equal(capped, false, "not capped")
      end },

      { name = "errors reports every independent problem in one pass", fn = function()
        -- The failure this prevents: two mistakes, two edit-and-rerun cycles,
        -- because the second one only appears after the first is fixed.
        local tree = box("root", {
          box("left", { text_node("dup", "ok"), text_node("dup", "again") }),
          box("right", { { id = "broken", kind = "bogus" } }),
        })
        local problems = validate.errors(tree)
        T.equal(#problems, 2, "problem count")
        T.equal(problems[1].path, "tree.children[1].children[2]", "duplicate path")
        T.equal(problems[1].message, "duplicate node id dup", "duplicate message")
        T.equal(problems[2].path, "tree.children[2].children[1].kind", "kind path")
        T.equal(problems[2].message, "is invalid: bogus", "kind message")
      end },

      { name = "errors refuses to recurse into a cycle", fn = function()
        local root = box("root")
        root.children = { root }
        local problems = validate.errors(root)
        T.equal(#problems, 1, "problem count")
        T.equal(problems[1].path, "tree.children[1]", "cycle path")
        T.equal(problems[1].message, "contains a cycle or reused table", "cycle message")
      end },

      { name = "errors stops at the cap instead of dumping a whole tree", fn = function()
        local children = {}
        for index = 1, 80 do
          children[index] = { id = "n" .. index, kind = "bogus" }
        end
        local problems, capped = validate.errors(box("root", children))
        T.equal(#problems, 50, "problem count")
        T.equal(capped, true, "cap reported")
      end },

      { name = "tree still raises the first problem", fn = function()
        -- validate.tree is the host's compatibility surface: it must keep
        -- refusing a tree, not start returning a list.
        local tree = box("root", {
          text_node("dup", "ok"), text_node("dup", "again"),
          { id = "broken", kind = "bogus" },
        })
        T.error_matches(function() validate.tree(tree) end,
          "duplicate node id dup", "first problem")
      end },

      -- validate.report ---------------------------------------------------
      { name = "report renders one problem as the sentence tree would raise", fn = function()
        local problems = validate.errors(box("root", { { id = "broken", kind = "bogus" } }))
        T.equal(validate.report(problems, false),
          "tree.children[1].kind is invalid: bogus", "rendered report")
      end },

      { name = "report renders several problems one per line with their paths", fn = function()
        local problems = validate.errors(box("root", {
          { id = "broken", kind = "bogus" },
          { id = "dup", kind = "container" },
          { id = "dup", kind = "container" },
        }))
        T.equal(validate.report(problems, false), table.concat({
          "2 problems in the UI tree:",
          "tree.children[1].kind is invalid: bogus",
          "tree.children[3] duplicate node id dup",
        }, "\n"), "rendered report")
      end },

      { name = "report says when the cap stopped the walk", fn = function()
        local children = {}
        for index = 1, 80 do children[index] = { id = "n" .. index, kind = "bogus" } end
        local problems, capped = validate.errors(box("root", children))
        T.contains(validate.report(problems, capped), "(stopped after 50 problems)",
          "cap notice")
      end },

      -- canvas.rect -----------------------------------------------------
      { name = "rect rejects a non-table", fn = function()
        T.error_matches(function() validate.rect(nil) end, "canvas.rect needs a table")
      end },

      { name = "rect requires an id", fn = function()
        T.error_matches(function() validate.rect({ ink = "ink" }) end,
          "rect.id must be a non-empty string id")
      end },

      { name = "rect requires ink", fn = function()
        T.error_matches(function() validate.rect({ id = "r" }) end,
          "rect.ink must be a non-empty string")
      end },

      { name = "rect bounds opacity to 0..1", fn = function()
        T.error_matches(function() validate.rect({ id = "r", ink = "ink", opacity = 2 }) end,
          "rect.opacity must be 0..1")
      end },

      { name = "rect rejects a negative radius", fn = function()
        T.error_matches(function() validate.rect({ id = "r", ink = "ink", radius = -1 }) end,
          "rect.radius must be non-negative")
      end },

      { name = "rect requires a 3-element translation", fn = function()
        T.error_matches(function()
          validate.rect({ id = "r", ink = "ink", translation = { 0, 0 } })
        end, "translation must be a 3-element array")
      end },

      { name = "rect rejects a non-finite translation", fn = function()
        T.error_matches(function()
          validate.rect({ id = "r", ink = "ink", translation = { 0, 0, math.huge } })
        end, "translation[3] must be a finite number")
      end },

      { name = "rect accepts a valid call", fn = function()
        local args = { id = "r", ink = "ink", opacity = 0.5, radius = 2,
          translation = { 0, 0, 0 }, scale = { 1, 1, 1 } }
        T.equal(validate.rect(args), args, "same table back")
      end },

      -- canvas.text -----------------------------------------------------
      { name = "text call rejects a non-table", fn = function()
        T.error_matches(function() validate.text(nil) end, "canvas.text needs a table")
      end },

      { name = "text call rejects whitespace", fn = function()
        T.error_matches(function() validate.text({ id = "t", text = "  ", ink = "ink" }) end,
          "must not be empty or whitespace")
      end },

      { name = "text call requires ink", fn = function()
        T.error_matches(function() validate.text({ id = "t", text = "ok" }) end,
          "text.ink must be a non-empty string")
      end },

      { name = "text call accepts a valid call", fn = function()
        local args = { id = "t", text = "hello", ink = "ink",
          translation = { 0, 0, 0 }, scale = { 1, 1, 1 } }
        T.equal(validate.text(args), args, "same table back")
      end },
    },
  }
end
