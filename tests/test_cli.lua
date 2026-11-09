-- End-to-end CLI behaviour that only shows up with a real filesystem.
--
-- These are the failures nobody notices locally: a workspace under a path with
-- a space, where pattern expansion silently returns nothing and `tend list`
-- prints an empty workspace that looks perfectly fine.

return function(T, root)
  local function read(path)
    local file = assert(io.open(path, "rb"), "cannot read " .. path)
    local text = file:read("*a")
    file:close()
    return text
  end

  local function write(path, text)
    local file = assert(io.open(path, "w"), "cannot write " .. path)
    file:write(text)
    file:close()
  end

  local function interpreter()
    return os.getenv("LUA") or (arg and arg[-1]) or "lua"
  end

  -- The cases below cd elsewhere, so a relative root would resolve against the
  -- wrong directory. Pin it once, absolutely.
  local function absolute_root()
    local pipe = assert(io.popen("pwd"), "cannot read cwd")
    local cwd = pipe:read("*l")
    pipe:close()
    return cwd .. "/" .. root
  end

  --- Make a directory whose path contains a space. os.tmpname gives a file, so
  --- use its parent and append a spaced name.
  local function temp_dir(label)
    local base = os.tmpname()
    os.remove(base)
    local path = base .. " " .. label
    local ok = os.execute("mkdir -p " .. string.format("%q", path))
    assert(ok == true or ok == 0, "cannot create " .. path)
    return path
  end

  local function run(command)
    local ok = os.execute(command)
    return ok == true or ok == 0
  end

  --- A complete ui/API.md. `actions` is the body under `## Actions`, so a case
  --- can leave the section out entirely ("None.") or give it a text block.
  local function api_doc(actions)
    return table.concat({
      "# Test spore UI API",
      "## Entrypoint", "`ui/view.lua` exports `M.render(snapshot)`.",
      "## Snapshot", "```lua\n{ title: string }\n```",
      "## Actions", actions,
      "## Slots", "None.",
      "## Components", "None.",
      "## Theme/config", "None.",
      "## Stable ids", "`test-root`.",
      "## Authority", "None.",
      "",
    }, "\n")
  end

  local function spore(dir, actions)
    write(dir .. "/spore.toml", table.concat({
      "schema = 1", "", "[spore]", 'id = "user.test"', "",
      "[module]", 'path = "module.wasm"', "",
      "[ui]", 'entry = "ui/view.lua"', "",
    }, "\n"))
    os.execute("mkdir -p " .. string.format("%q", dir .. "/ui"))
    write(dir .. "/ui/API.md", api_doc(actions))
    write(dir .. "/ui/view.lua", table.concat({
      'local ui = require("fungos.ui")',
      'local action = require("fungos.action")',
      'local M = {}',
      'function M.render(snapshot)',
      '  return ui.action_button("test-save", "Save", {',
      '    action = action.intent("notes.save", { path = "a.md" }),',
      '  })',
      'end',
      'return M',
      '',
    }, "\n"))
  end

  --- Run `tend api-check --root dir`, returning ok, exit code and combined output.
  local function api_check(dir)
    local out_path = os.tmpname() .. ".out"
    local ok, _, code = os.execute(string.format(
      "cd %q && %s %q api-check --root %q > %q 2>&1",
      absolute_root(), interpreter(), absolute_root() .. "/tools/tend.lua",
      dir, out_path))
    local output = read(out_path)
    os.remove(out_path)
    return ok == true or ok == 0, code, output
  end

  return {
    name = "cli",
    cases = {
      { name = "workspace discovery finds members under a path with a space", fn = function()
        -- The failure mode: leaving the directory bare splits the path into two
        -- operands and the glob silently matches nothing. Note this only shows up
        -- when the *root* carries the space, so the case passes --workspace
        -- rather than cd-ing in and letting the root be ".".
        local dir = temp_dir("ws")
        local out_path = os.tmpname() .. ".out"
        write(dir .. "/tend.lua", 'return { members = { "*.lua" } }\n')
        write(dir .. "/member.lua", 'return {}\n')
        local ok = run(string.format(
          "cd %q && %s %q list --workspace %q > %q 2>&1",
          absolute_root(), interpreter(), absolute_root() .. "/tools/tend.lua",
          dir, out_path))
        local output = read(out_path)
        os.execute("rm -rf " .. string.format("%q", dir) .. " " .. string.format("%q", out_path))
        T.truthy(ok, "tend list failed")
        T.contains(output, "member.lua", "member not listed")
      end },

      { name = "check prints every preflight problem, not just the first", fn = function()
        -- Both mistakes are in one tree. First-error-only made the developer fix
        -- one, rerun, and only then discover the other, which is one edit cycle
        -- per mistake for no reason.
        local dir = temp_dir("preflight")
        write(dir .. "/view.lua", table.concat({
          'local ui = require("fungos.ui")',
          'local M = {}',
          'function M.render(snapshot)',
          '  local tree = ui.column("root", {}, {',
          '    ui.text("dup", "one", { size = 12 }),',
          '    ui.text("dup", "two", { size = 12 }),',
          '    { id = "broken", kind = "bogus" },',
          '  })',
          '  return ui.layout(tree, 800, 600)',
          'end',
          'return M',
          '',
        }, "\n"))
        local out_path = os.tmpname() .. ".out"
        local ok, _, code = os.execute(string.format(
          "cd %q && %s %q check %q --snapshot examples/inbox_snapshot.lua "
            .. "--allow-undocumented > %q 2>&1",
          absolute_root(), interpreter(), absolute_root() .. "/tools/tend.lua",
          dir .. "/view.lua", out_path))
        local output = read(out_path)
        os.execute("rm -rf " .. string.format("%q", dir) .. " " .. string.format("%q", out_path))
        T.truthy(not (ok == true or ok == 0), "a broken tree should fail preflight")
        T.equal(code, 2, "exit code")
        T.contains(output, "tree.children[2] duplicate node id dup", "duplicate reported")
        T.contains(output, "tree.children[3].kind is invalid: bogus", "invalid kind reported")
      end },

      { name = "api-check fails on an action the view emits but nobody documented", fn = function()
        -- The view's save is wired; the docs never mention it, so no other
        -- Spore, rice or host projection can know the action exists.
        local dir = temp_dir("spore")
        spore(dir, "```text\nnotes.delete\n```\n")
        local ok, code, output = api_check(dir)
        os.execute("rm -rf " .. string.format("%q", dir))
        T.truthy(not ok, "api-check should fail")
        T.equal(code, 1, "exit code")
        T.contains(output, "undocumented actions: notes.save", "undocumented action")
        T.contains(output, "documented but never emitted: notes.delete", "unused warning")
      end },

      { name = "api-check passes when every emitted action is documented", fn = function()
        local dir = temp_dir("spore")
        spore(dir, "```text\nnotes.save\n```\n")
        local ok, _, output = api_check(dir)
        os.execute("rm -rf " .. string.format("%q", dir))
        T.truthy(ok, "api-check should pass: " .. output)
        T.contains(output, "api-check ok", "ok line")
      end },

      { name = "api-check leaves a spore without an Actions block alone", fn = function()
        -- Most API.md files predate the convention. Treating "no Actions text
        -- block" as "no actions documented" would fail every one of them.
        local dir = temp_dir("spore")
        spore(dir, "None. This UI emits no actions.")
        local ok, _, output = api_check(dir)
        os.execute("rm -rf " .. string.format("%q", dir))
        T.truthy(ok, "api-check should pass: " .. output)
      end },

      { name = "api-check asks nothing of a Spore with no Lua view", fn = function()
        -- A command-line Spore's whole surface is its arguments. The rule is
        -- about the Lua API, so a package with no `ui/` has nothing to document
        -- and nothing to fail.
        local dir = temp_dir("spore")
        os.execute("mkdir -p " .. string.format("%q", dir))
        write(dir .. "/spore.toml", table.concat({
          "schema = 1", "", "[spore]", 'id = "user.hue"', "",
          "[module]", 'path = "module.wasm"', "",
        }, "\n"))
        local ok, _, output = api_check(dir)
        os.execute("rm -rf " .. string.format("%q", dir))
        T.truthy(ok, "api-check should pass: " .. output)
        T.contains(output, "api-check ok", "ok line")
      end },

      { name = "api-check fails a Spore that ships a view without docs", fn = function()
        -- The other half of the rule: a `ui/` puts the Spore inside it, whether
        -- or not the manifest has declared `[ui] entry` yet.
        local dir = temp_dir("spore")
        os.execute("mkdir -p " .. string.format("%q", dir .. "/ui"))
        write(dir .. "/spore.toml", table.concat({
          "schema = 1", "", "[spore]", 'id = "user.dragshift"', "",
          "[module]", 'path = "module.wasm"', "",
        }, "\n"))
        write(dir .. "/ui/view.lua", "return {}\n")
        local ok, code, output = api_check(dir)
        os.execute("rm -rf " .. string.format("%q", dir))
        T.truthy(not ok, "api-check should fail")
        T.equal(code, 1, "exit code")
        T.contains(output, "missing ui/API.md", "missing doc reported")
      end },
    },
  }
end
