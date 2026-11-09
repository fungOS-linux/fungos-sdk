-- Tests for the UI kit's non-component helpers.
--
-- `ui.editor` puts `expected_version` on the node; `ui.save_intent` is the only
-- supported way to turn that node into a save intent. The failure this prevents
-- is a view that hand-builds the intent, drops the guard, and ships a save the
-- host cannot check for a conflict.

return function(T, root)
  local ui = dofile(root .. "/lua/fungos/ui.lua")

  local function editor(guard)
    return ui.editor("note-editor", "body", { expected_version = guard })
  end

  return {
    name = "ui",
    cases = {
      { name = "save_intent builds an intent that carries the guard", fn = function()
        local intent = ui.save_intent(editor(7), "notes.save", { path = "notes/a.md" })
        T.equal(intent.action, "notes.save", "action id")
        T.equal(intent.payload.path, "notes/a.md", "payload")
        T.equal(intent.payload.expected_version, 7, "expected_version")
      end },

      { name = "save_intent merges extra keys into the payload", fn = function()
        local intent = ui.save_intent(editor(7), "notes.save",
          { path = "notes/a.md", note = "draft" })
        T.equal(intent.payload.path, "notes/a.md", "path")
        T.equal(intent.payload.note, "draft", "note")
        T.equal(intent.payload.expected_version, 7, "expected_version")
      end },

      { name = "save_intent keeps the editor's guard over a conflicting extra", fn = function()
        -- The version is the whole point of the helper: an extra table that
        -- carries one must not be able to replace what the node holds.
        local extra = { expected_version = 3 }
        local intent = ui.save_intent(editor(7), "notes.save", extra)
        T.equal(intent.payload.expected_version, 7, "editor wins")
        T.equal(extra.expected_version, 3, "caller's table is untouched")
      end },

      { name = "save_intent refuses an editor with no version guard", fn = function()
        T.error_matches(function() return ui.save_intent(editor(nil), "notes.save") end,
          "has no expected_version", "missing guard")
      end },

      { name = "capture emits a soil scene document and hit targets", fn = function()
        local present, hits = ui.capture(200, 100, { body = 16 }, function(surface)
          surface:background("background")
          surface:rect("card", 10, 10, 40, 20, "surface", 1, 4)
          surface:text("title", "Hello", 10, 40, 12, "text")
          surface:polyline("spark", {{ 0, 0 }, { 10, 10 }}, 2, "primary")
          T.truthy(surface:hit("card-hit", { x = 10, y = 10, width = 40, height = 20 }, "card"),
            "hit inside the surface")
        end)
        T.equal(present.kind, "scene", "present kind")
        T.equal(present.schema, 1, "scene schema")
        T.equal(#present.nodes, 4, "background, rect, text, and polyline are nodes")
        T.equal(#hits, 1, "one hit target")
        T.equal(hits[1].id, "card-hit", "hit id")
      end },

      { name = "present sends the same document through canvas.present", fn = function()
        local presented
        local registered = {}
        _G.canvas = {
          present = function(document)
            presented = document
            return { generation = 3 }
          end,
        }
        _G.widget = { hit = function(spec) registered[#registered + 1] = spec end }
        local state, hits = ui.present(200, 100, { body = 16 }, function(surface)
          surface:rect("card", 10, 10, 40, 20, "surface")
          surface:hit("card-hit", { x = 10, y = 10, width = 40, height = 20 }, "card")
        end)
        T.equal(state.generation, 3, "host state is returned")
        T.equal(presented.kind, "scene", "presented document kind")
        T.equal(#presented.nodes, 1, "presented node count")
        T.equal(#registered, 1, "hit registered with widget.hit")
        T.equal(#hits, 1, "hit target returned to the caller")
      end },

      { name = "present_document passes a prepared soil scene through", fn = function()
        local captured
        _G.canvas = {
          present = function(document)
            captured = document
            return { generation = 5 }
          end,
        }
        local document = { kind = "scene", schema = 1, nodes = {} }
        local state = ui.present_document(document)
        T.truthy(captured == document, "document identity is preserved")
        T.equal(state.generation, 5, "host state is returned")
      end },

      { name = "present falls back to the legacy surface without canvas.present", fn = function()
        local rects, texts = 0, 0
        _G.canvas = {
          rect = function() rects = rects + 1 end,
          text = function() texts = texts + 1 end,
        }
        _G.widget = { hit = function() end }
        ui.present(200, 100, { body = 16 }, function(surface)
          surface:rect("card", 10, 10, 40, 20, "surface")
          surface:text("title", "Hi", 10, 40, 12, "text")
        end)
        T.truthy(rects > 0 and texts > 0, "legacy primitives still draw")
      end },

      { name = "theme() keeps the host's scale and only fills its gaps", fn = function()
        -- A theme token can be a length the host draws *with*, not a suggestion:
        -- Canvas sizes text as `scale * theme.body * depth(z)`, so a default
        -- that overwrote `body` collapsed a 1.5x wall back to one text size.
        local saved = _G.module
        _G.module = { theme = { body = 24, large = 27 } }
        local theme = ui.theme()
        _G.module = saved
        T.equal(theme.body, 24, "the host's body wins over ui.defaults")
        T.equal(theme.large, 27, "the host's large wins")
        T.equal(theme.micro, 10, "a token the host omits comes from defaults")
        T.equal(theme.small, 13, "a token the host omits comes from defaults")
      end },

      { name = "configure() is the one place a token may override the host", fn = function()
        local saved = _G.module
        _G.module = { theme = { body = 24, micro = 15 } }
        ui.configure({ theme = { body = 18 } })
        local theme = ui.theme()
        ui.configure({})
        _G.module = saved
        T.equal(theme.body, 18, "an explicit profile value wins over the host")
        T.equal(theme.micro, 15, "configuring one token leaves the others alone")
      end },

      { name = "viewport survives a theme that answers every token", fn = function()
        -- A host theme is free to answer any key it is asked for, and then
        -- `theme.viewport` is a length rather than a size. Reading `.width` off
        -- that number killed the render before it drew anything.
        local saved = _G.module
        _G.module = { theme = setmetatable({}, { __index = function() return 0.5 end }) }
        local w, h = ui.viewport(1086, 1569)
        _G.module = saved
        T.equal(w, 1086, "falls back to the authoring width")
        T.equal(h, 1569, "falls back to the authoring height")
      end },
    },
  }
end
