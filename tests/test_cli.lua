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
    },
  }
end
