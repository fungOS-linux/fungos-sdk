-- Golden-scene tests: does tend still produce the scene it produced before?
--
-- tend's fake host is a second implementation of the host contract, so the
-- failure mode that matters is drift: a node that quietly stops being emitted,
-- a renamed id, a lost hit target. This suite pins the structure of a real
-- capture so that shows up as a failing test instead of a blank panel.
--
-- Scope, stated plainly: it compares node ids and hit ids, not pixels or
-- geometry. Geometry is layout-engine dependent, and a byte comparison would
-- break on interpreter differences rather than on real regressions. The full
-- scene is committed at tests/golden/inbox.scene.json for a *host-side* test to
-- consume; that half is what proves the imitation still matches the original.

return function(T, root)
  local NOW = 1794014400000 -- fixed epoch ms; see --now in tools/tend.lua

  local function read(path)
    local file = assert(io.open(path, "rb"), "cannot read " .. path)
    local text = file:read("*a")
    file:close()
    return text
  end

  local function exists(path)
    local file = io.open(path, "rb")
    if file then file:close() return true end
    return false
  end

  local function lines(text)
    local list = {}
    for line in text:gmatch("[^\n]+") do list[#list + 1] = line end
    return list
  end

  local function ids(text)
    local list = {}
    for id in text:gmatch('"id":"(.-)"') do list[#list + 1] = id end
    return list
  end

  -- Use the interpreter running this suite, so a capture never silently runs a
  -- different Lua than the tests do.
  local function interpreter()
    return os.getenv("LUA") or (arg and arg[-1]) or "lua"
  end

  local function capture(destination)
    local command = string.format(
      "cd %q && TZ=UTC %s tools/tend.lua --scene %q --now %d "
        .. "examples/inbox.lua examples/inbox_snapshot.lua >/dev/null 2>&1",
      root, interpreter(), destination, NOW)
    local ok = os.execute(command)
    return ok == true or ok == 0
  end

  local function cleanup(path)
    os.remove(path)
    os.remove(path .. ".hits.json")
  end

  local function compare_ids(actual, expected, label)
    T.equal(#actual, #expected, label .. " count")
    for index = 1, #expected do
      if actual[index] ~= expected[index] then
        error(string.format("%s %d: expected %s, got %s",
          label, index, expected[index], tostring(actual[index])), 2)
      end
    end
  end

  return {
    name = "scene",
    cases = {
      { name = "the golden fixture is committed and non-trivial", fn = function()
        local path = root .. "/tests/golden/inbox.scene.json"
        T.truthy(exists(path), "missing " .. path)
        T.truthy(#read(path) > 1000, "fixture looks empty")
      end },

      { name = "capture writes both a scene and a hits file", fn = function()
        local path = os.tmpname() .. ".scene.json"
        T.truthy(capture(path), "capture failed")
        local scene, hits = exists(path), exists(path .. ".hits.json")
        cleanup(path)
        T.truthy(scene, "scene file missing")
        T.truthy(hits, "hits file missing")
      end },

      { name = "scene node ids still match the golden fixture", fn = function()
        local path = os.tmpname() .. ".scene.json"
        T.truthy(capture(path), "capture failed")
        local actual = ids(read(path))
        cleanup(path)
        local expected = lines(read(root .. "/tests/golden/inbox.scene.ids.txt"))
        compare_ids(actual, expected, "node")
      end },

      { name = "hit target ids still match the golden fixture", fn = function()
        local path = os.tmpname() .. ".scene.json"
        T.truthy(capture(path), "capture failed")
        local actual = ids(read(path .. ".hits.json"))
        cleanup(path)
        local expected = lines(read(root .. "/tests/golden/inbox.hits.ids.txt"))
        compare_ids(actual, expected, "hit")
      end },

      { name = "capture is byte-identical across runs", fn = function()
        -- Determinism is the property the whole fixture rests on. It broke
        -- before --now existed: every run embedded the wall clock.
        local first = os.tmpname() .. ".a.json"
        local second = os.tmpname() .. ".b.json"
        T.truthy(capture(first), "first capture failed")
        T.truthy(capture(second), "second capture failed")
        local same = read(first) == read(second)
        cleanup(first)
        cleanup(second)
        T.truthy(same, "two captures of the same view disagree")
      end },
    },
  }
end
