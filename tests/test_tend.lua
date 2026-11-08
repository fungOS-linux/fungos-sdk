-- Tests for fungos.tend: argv parsing, comment stripping, API-doc checks.
--
-- These cover the parts of the development loop that used to be untested
-- because they lived inside the CLI. Each case names the behaviour, not the
-- implementation, so a refactor that keeps the contract keeps the tests.

return function(T, root)
  local tend = dofile(root .. "/lua/fungos/tend.lua")

  return {
    name = "tend",
    cases = {
      -- parse -------------------------------------------------------------
      { name = "parse takes a positional view", fn = function()
        local o = tend.parse({ "ui/inbox.lua" }, {})
        T.equal(o.view, "ui/inbox.lua", "view")
        T.equal(o.snapshot, nil, "no snapshot")
      end },

      { name = "parse takes a positional snapshot", fn = function()
        local o = tend.parse({ "ui/inbox.lua", "examples/snap.lua" }, {})
        T.equal(o.view, "ui/inbox.lua", "view")
        T.equal(o.snapshot, "examples/snap.lua", "snapshot")
      end },

      { name = "parse accepts --snapshot as a flag", fn = function()
        local o = tend.parse({ "ui/inbox.lua", "--snapshot", "snap.lua" }, {})
        T.equal(o.snapshot, "snap.lua", "snapshot from flag")
      end },

      { name = "parse collects repeated --component flags", fn = function()
        local o = tend.parse({
          "v.lua", "--component", "a.lua", "--component", "b.lua",
        }, {})
        T.equal(#o.components, 2, "component count")
        T.equal(o.components[1], "a.lua", "first component")
        T.equal(o.components[2], "b.lua", "second component")
      end },

      { name = "parse collects repeated --root flags", fn = function()
        local o = tend.parse({ "--root", "spores", "--root", "examples" }, {})
        T.equal(#o.roots, 2, "root count")
        T.equal(o.roots[2], "examples", "second root")
      end },

      { name = "parse keeps defaults the argv never mentions", fn = function()
        local o = tend.parse({ "v.lua" }, {
          name = "tend-preview", reload = true, check_api = true, sdk = "/sdk",
        })
        T.equal(o.name, "tend-preview", "name")
        T.equal(o.reload, true, "reload")
        T.equal(o.check_api, true, "check_api")
        T.equal(o.sdk, "/sdk", "sdk")
      end },

      { name = "parse maps --no-reload to reload=false", fn = function()
        local o = tend.parse({ "v.lua", "--no-reload" }, { reload = true })
        T.equal(o.reload, false, "reload")
      end },

      { name = "parse maps --allow-undocumented to check_api=false", fn = function()
        local o = tend.parse({ "v.lua", "--allow-undocumented" }, { check_api = true })
        T.equal(o.check_api, false, "check_api")
      end },

      { name = "parse snake_cases unknown long flags", fn = function()
        local o = tend.parse({ "v.lua", "--strict-baseline", "--read-auth", "token" }, {})
        T.equal(o.strict_baseline, true, "boolean flag")
        T.equal(o.read_auth, "token", "valued flag")
      end },

      { name = "parse never mutates the defaults table", fn = function()
        -- A leaked default is the kind of bug that only shows up on the second
        -- invocation, in a loop, after everything else has gone green.
        local defaults = { reload = true, check_api = true, components = { "kept.lua" } }
        local o = tend.parse({"v.lua", "--no-reload", "--component", "new.lua"}, defaults)
        T.equal(defaults.reload, true, "defaults.reload untouched")
        T.equal(#defaults.components, 1, "defaults.components untouched")
        T.equal(o.reload, false, "result reload")
        T.equal(#o.components, 2, "result components include the default")
        T.equal(o.components[1], "kept.lua", "default component survives")
      end },

      { name = "parse fails loudly when --component has no value", fn = function()
        T.error_matches(function() tend.parse({ "v.lua", "--component" }, {}) end,
          "--component requires a path")
      end },

      -- strip_comments ----------------------------------------------------
      { name = "strip_comments drops a trailing comment", fn = function()
        T.equal(tend.strip_comments("local a = 1 -- note\nlocal b = 2"),
          "local a = 1\nlocal b = 2")
      end },

      { name = "strip_comments drops a whole-line comment", fn = function()
        T.equal(tend.strip_comments("-- just a note"), "")
      end },

      { name = "strip_comments keeps -- inside a double-quoted string", fn = function()
        T.equal(tend.strip_comments('local s = "a -- b"'), 'local s = "a -- b"')
      end },

      { name = "strip_comments keeps -- inside a single-quoted string", fn = function()
        T.equal(tend.strip_comments("local s = 'a -- b'"), "local s = 'a -- b'")
      end },

      { name = "strip_comments respects an escaped quote", fn = function()
        -- Without escape handling the string closes early and the rest of the
        -- line is eaten as a comment.
        T.equal(tend.strip_comments('local s = "a\\" -- b"'), 'local s = "a\\" -- b"')
      end },

      { name = "strip_comments keeps -- inside a long-bracket string", fn = function()
        T.equal(tend.strip_comments("local s = [[a -- b]]"), "local s = [[a -- b]]")
      end },

      { name = "strip_comments keeps -- inside a levelled long string", fn = function()
        T.equal(tend.strip_comments("local s = [==[a -- b]==]"), "local s = [==[a -- b]==]")
      end },

      { name = "strip_comments removes a long comment", fn = function()
        T.equal(tend.strip_comments("--[[ npm install ]] return 1"), "return 1")
      end },

      { name = "strip_comments removes a levelled long comment", fn = function()
        T.equal(tend.strip_comments("--[==[ x ]] still a comment ]==]return 1"), "return 1")
      end },

      { name = "strip_comments trims and drops blank lines", fn = function()
        T.equal(tend.strip_comments("   a   \n\n\n  b  \n"), "a\nb")
      end },

      -- missing_sections --------------------------------------------------
      { name = "missing_sections is empty when every heading is present", fn = function()
        local text = table.concat({
          "## Entrypoint", "## Snapshot", "## Actions", "## Slots",
          "## Components", "## Theme/config", "## Stable ids", "## Authority",
        }, "\n")
        T.equal(#tend.missing_sections(text), 0, "nothing missing")
        return
      end },

      { name = "missing_sections lists everything for empty text", fn = function()
        local missing = tend.missing_sections("")
        T.equal(#missing, #tend.api_sections, "count")
        T.equal(missing[1], "entrypoint", "canonical order")
        T.equal(missing[#missing], "authority", "canonical order tail")
      end },

      { name = "missing_sections matches headings case-insensitively", fn = function()
        local text = table.concat({
          "## ENTRYPOINT", "## snapshot", "## Actions", "## slots",
          "## Components", "## THEME/CONFIG", "## Stable IDs", "## authority",
        }, "\n")
        T.equal(#tend.missing_sections(text), 0, "nothing missing")
      end },

      { name = "missing_sections reports only the gap", fn = function()
        local text = table.concat({
          "## Entrypoint", "## Snapshot", "## Actions", "## Slots",
          "## Components", "## Theme/config", "## Stable ids",
        }, "\n")
        local missing = tend.missing_sections(text)
        T.equal(#missing, 1, "one gap")
        T.equal(missing[1], "authority", "the gap is authority")
      end },

      { name = "missing_sections ignores top-level headings", fn = function()
        -- `# Entrypoint` is the document title, not a section. Accepting it
        -- would let a one-line file pass the gate.
        T.equal(#tend.missing_sections("# Entrypoint\n## Snapshot"), 7, "only the h2 counts")
      end },

      -- documented_actions -------------------------------------------------
      { name = "documented_actions reads the text block under Actions", fn = function()
        local ids = tend.documented_actions(table.concat({
          "## Actions", "", "```text", "notes.save", "mail.archive", "```",
        }, "\n"))
        T.equal(#ids, 2, "id count")
        T.equal(ids[1], "notes.save", "first")
        T.equal(ids[2], "mail.archive", "second")
      end },

      { name = "documented_actions ignores fenced blocks in other sections", fn = function()
        -- The Snapshot and Theme sections are full of code; only the Actions
        -- block is the machine-checked list, or every example snippet becomes
        -- an action id.
        local ids = tend.documented_actions(table.concat({
          "## Snapshot", "```text", "snapshot.field", "```",
          "## Actions", "```text", "notes.save", "```",
          "## Theme/config", "```text", "theme.key", "```",
        }, "\n"))
        T.equal(#ids, 1, "id count")
        T.equal(ids[1], "notes.save", "only the Actions block")
      end },

      { name = "documented_actions ignores a non-text fence inside Actions", fn = function()
        local ids = tend.documented_actions(table.concat({
          "## Actions",
          "```lua", "action.intent(\"notes.save\")", "```",
          "```text", "notes.archive", "```",
        }, "\n"))
        T.equal(#ids, 1, "id count")
        T.equal(ids[1], "notes.archive", "only the text fence counts")
      end },

      { name = "documented_actions deduplicates and keeps file order", fn = function()
        local ids = tend.documented_actions(table.concat({
          "## Actions", "```text", "b.second", "a.first", "b.second", "", "```",
        }, "\n"))
        T.equal(#ids, 2, "id count")
        T.equal(ids[1], "b.second", "first seen first")
        T.equal(ids[2], "a.first", "file order, not sorted")
      end },

      { name = "documented_actions stops at the next heading", fn = function()
        local ids = tend.documented_actions(table.concat({
          "## Actions", "```text", "notes.save", "```",
          "## Slots", "```text", "toolbar.end", "```",
        }, "\n"))
        T.equal(#ids, 1, "id count")
        T.equal(ids[1], "notes.save", "slot names are not actions")
      end },

      { name = "documented_actions is empty without an Actions section", fn = function()
        -- Most API.md files predate the convention. "Not documented this way"
        -- must mean "nothing to check", never "this spore documents no actions".
        local ids = tend.documented_actions("## Snapshot\n```text\nsnapshot.field\n```\n")
        T.equal(#ids, 0, "id count")
      end },

      { name = "documented_actions does not treat a heading inside a fence as one", fn = function()
        -- A verbatim sample can contain markdown. Ending the section there
        -- would silently truncate the documented actions.
        local ids = tend.documented_actions(table.concat({
          "## Actions", "```text", "## not a heading", "notes.save", "```",
        }, "\n"))
        T.equal(#ids, 2, "id count")
        T.equal(ids[2], "notes.save", "id after the fake heading")
      end },

      { name = "documented_actions accepts a longer Actions heading", fn = function()
        local ids = tend.documented_actions("## Actions emitted\n```text\nnotes.save\n```")
        T.equal(#ids, 1, "id count")
        T.equal(ids[1], "notes.save", "id")
      end },

      -- emitted_actions ----------------------------------------------------
      { name = "emitted_actions finds literal action.intent ids", fn = function()
        local ids = tend.emitted_actions(table.concat({
          'local action = require("fungos.action")',
          'action.intent("notes.save", { path = "a.md" })',
          'action.intent( "mail.archive" )',
        }, "\n"))
        T.equal(#ids, 2, "id count")
        T.equal(ids[1], "notes.save", "first")
        T.equal(ids[2], "mail.archive", "second")
      end },

      { name = "emitted_actions finds the alias and the ui helper", fn = function()
        local ids = tend.emitted_actions(table.concat({
          'action.call("notes.save")',
          'ui.action_intent("mail.archive")',
        }, "\n"))
        T.equal(#ids, 2, "id count")
        T.equal(ids[1], "notes.save", "alias")
        T.equal(ids[2], "mail.archive", "ui helper")
      end },

      { name = "emitted_actions ignores a commented-out intent", fn = function()
        local ids = tend.emitted_actions(table.concat({
          '-- action.intent("notes.delete")',
          'action.intent("notes.save")',
        }, "\n"))
        T.equal(#ids, 1, "id count")
        T.equal(ids[1], "notes.save", "only the live intent")
      end },

      { name = "emitted_actions ignores a call with no literal id", fn = function()
        -- The scan is static: an id it cannot read is not an id it can claim.
        local ids = tend.emitted_actions('action.intent(action_id, { id = 1 })')
        T.equal(#ids, 0, "id count")
      end },

      { name = "emitted_actions deduplicates in source order", fn = function()
        -- `z` before `a`, so a scan that sorts instead of keeping source order
        -- fails here rather than looking lucky.
        local ids = tend.emitted_actions(table.concat({
          'ui.action_intent("z.first")',
          'action.intent("a.second")',
          'action.intent("z.first")',
        }, "\n"))
        T.equal(#ids, 2, "id count")
        T.equal(ids[1], "z.first", "first")
        T.equal(ids[2], "a.second", "second")
      end },

      -- action_gaps --------------------------------------------------------
      { name = "action_gaps separates undocumented from unused", fn = function()
        local gaps = tend.action_gaps({ "notes.save", "notes.delete" }, { "notes.save", "mail.send" })
        T.equal(#gaps.undocumented, 1, "undocumented count")
        T.equal(gaps.undocumented[1], "mail.send", "emitted but undocumented")
        T.equal(#gaps.unused, 1, "unused count")
        T.equal(gaps.unused[1], "notes.delete", "documented but unused")
      end },

      { name = "action_gaps sorts both lists", fn = function()
        local gaps = tend.action_gaps(
          { "z.late", "m.mid", "a.early" },
          { "y.emitted", "n.mid", "b.emitted" })
        T.equal(gaps.undocumented[1], "b.emitted", "undocumented first")
        T.equal(gaps.undocumented[2], "n.mid", "undocumented second")
        T.equal(gaps.unused[1], "a.early", "unused first")
        T.equal(gaps.unused[2], "m.mid", "unused second")
      end },

      -- ui_entry -----------------------------------------------------------
      { name = "ui_entry reads the entry under [ui]", fn = function()
        local toml = table.concat({
          "[module]", 'path = "module.wasm"', "", "[ui]", 'entry = "ui/hello.lua"',
        }, "\n")
        T.equal(tend.ui_entry(toml), "ui/hello.lua", "entry")
      end },

      { name = "ui_entry ignores an entry outside [ui]", fn = function()
        -- [module].entry is the wasm path. Confusing it with the view would
        -- scan a binary as Lua and report nothing.
        local toml = table.concat({
          "[module]", 'entry = "module.wasm"', "", "[grants]", 'entry = "grant"',
        }, "\n")
        T.equal(tend.ui_entry(toml), nil, "no ui entry")
      end },

      -- the contract itself ----------------------------------------------
      { name = "api_sections is the documented eight in order", fn = function()
        T.equal(#tend.api_sections, 8, "section count")
        T.equal(tend.api_sections[1], "entrypoint", "first")
        T.equal(tend.api_sections[8], "authority", "last")
      end },

      { name = "api-check is a registered command", fn = function()
        T.truthy(tend.commands["api-check"], "api-check")
      end },

      { name = "watch is a registered command", fn = function()
        T.truthy(tend.commands["watch"], "watch")
      end },

      -- baseline_entries --------------------------------------------------
      { name = "baseline_entries is empty for empty text", fn = function()
        local entries = tend.baseline_entries("")
        local count = 0
        for _ in pairs(entries) do count = count + 1 end
        T.equal(count, 0, "no entries")
      end },

      { name = "baseline_entries ignores comments and blank lines", fn = function()
        local entries = tend.baseline_entries(
          "# a header\n\nspores/crm\n   \n# trailing note\n")
        T.equal(entries["spores/crm"], true, "crm tolerated")
        local count = 0
        for _ in pairs(entries) do count = count + 1 end
        T.equal(count, 1, "one real entry")
      end },

      { name = "baseline_entries trims surrounding whitespace", fn = function()
        local entries = tend.baseline_entries("   spores/crm   \n")
        T.equal(entries["spores/crm"], true, "trimmed")
      end },

      { name = "baseline_entries keeps paths verbatim", fn = function()
        -- Paths are not identifiers: a retired entry with a typo must not
        -- silently match the real one.
        local entries = tend.baseline_entries("spores/CRm\n")
        T.equal(entries["spores/CRm"], true, "case preserved")
        T.equal(entries["spores/crm"], nil, "no case folding")
      end },
    },
  }
end
