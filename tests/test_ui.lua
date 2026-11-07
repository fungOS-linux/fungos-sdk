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
    },
  }
end
