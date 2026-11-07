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

      -- the contract itself ----------------------------------------------
      { name = "api_sections is the documented eight in order", fn = function()
        T.equal(#tend.api_sections, 8, "section count")
        T.equal(tend.api_sections[1], "entrypoint", "first")
        T.equal(tend.api_sections[8], "authority", "last")
      end },

      { name = "api-check is a registered command", fn = function()
        T.truthy(tend.commands["api-check"], "api-check")
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
