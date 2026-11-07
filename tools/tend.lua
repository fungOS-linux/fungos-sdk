#!/usr/bin/env lua
-- tend — compose a Spore UI view into a Canvas module and reload one surface.
--
-- This is a development tool, not a host capability. It runs outside the Spore
-- sandbox so it may read files, invoke canvasctl, and write the modules dir.
--
--   tend ui/inbox.lua \
--     --snapshot examples/inbox_snapshot.lua \
--     --app dev.fungos.unibus \
--     --surface inbox
--
--   tend check ui/inbox.lua examples/inbox_snapshot.lua
--   tend doctor ui/inbox.lua --snapshot examples/inbox_snapshot.lua
--   tend --scene /tmp/scene.json ui/inbox.lua examples/inbox_snapshot.lua
--
-- The generated module contains the SDK modules, the view, the snapshot, and
-- the resolved user profile. It uses a tiny require shim because Canvas does
-- not load packages at runtime.

local function script_dir()
  local source = debug.getinfo(1, "S").source:sub(2)
  return source:match("^(.*)[/\\][^/\\]+$") or "."
end

local ROOT = script_dir() .. "/.."

-- The pure half of the tool lives in lua/fungos/tend.lua so tests/run.lua can
-- drive it without spawning a process or touching the filesystem.
local tendlib = dofile(ROOT .. "/lua/fungos/tend.lua")
local themelib = dofile(ROOT .. "/lua/fungos/theme.lua")

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

local function dirname(path)
  return path:match("^(.*)[/\\][^/\\]+$") or "."
end

local function join(a, b)
  if a:sub(-1) == "/" then return a .. b end
  return a .. "/" .. b
end

local function defaults()
  return {
    name = "tend-preview",
    reload = true,
    check_api = true,
    sdk = os.getenv("FUNGOS_SDK") or ROOT,
    config = os.getenv("FUNGOS_CONFIG") or ((os.getenv("HOME") or "") .. "/.config/fungos/ui.lua"),
    modules = os.getenv("FUNGOS_MODULES") or ((os.getenv("HOME") or "") .. "/Library/Application Support/Dock/canvas/modules"),
    components = {},
    workspace = nil,
    no_workspace = false,
  }
end

local function parse(argv)
  return tendlib.parse(argv, defaults())
end

local strip_comments = tendlib.strip_comments

-- (strip_comments lives in lua/fungos/tend.lua so it can be tested directly.)

local function api_path(view)
  local ui_dir = dirname(view)
  return join(ui_dir, "API.md")
end

local function check_api(options)
  if not options.check_api then return true end
  local path = api_path(options.view)
  if not exists(path) then
    io.stderr:write("tend: missing Lua API documentation: " .. path .. "\n")
    io.stderr:write("tend: every Spore UI must ship ui/API.md; see docs/lua-api-contract.md\n")
    return false
  end
  local missing = tendlib.missing_sections(read(path))
  if #missing > 0 then
    io.stderr:write("tend: " .. path .. " is missing: " .. table.concat(missing, ", ") .. "\n")
    return false
  end
  return true
end

local function shell_lines(command)
  local pipe = io.popen(command)
  if not pipe then return {} end
  local out = {}
  for raw in pipe:lines() do
    local line = raw:match("^%s*(.-)%s*$")
    if line ~= "" then out[#out + 1] = line end
  end
  pipe:close()
  return out
end

local function expand_pattern(root, pattern)
  if not pattern or pattern == "" then return {} end
  local absolute = pattern:sub(1, 1) == "/" and pattern or join(root, pattern)
  return shell_lines("ls -d " .. absolute .. " 2>/dev/null")
end

--- Names of baseline entries, one directory per line. `#` starts a comment.
local function read_baseline(path)
  if not path or not exists(path) then return {} end
  return tendlib.baseline_entries(read(path))
end

--- Repo-wide sweep: every Spore with a spore.toml must ship ui/API.md.
---
--- The baseline makes this bind today instead of after a ten-file backfill:
--- known-undocumented Spores are tolerated by path, so a *new* Spore without
--- docs fails the build immediately. Documented Spores drop out of the failure
--- list, and pruning the baseline is what keeps the ratchet turning.
local function api_check(options)
  local roots = options.roots or { "." }
  local baseline = read_baseline(options.baseline)
  local failures, baselined, tolerated = {}, 0, {}

  for _, root in ipairs(roots) do
    local manifests = shell_lines(
      string.format("find %q -name spore.toml -type f 2>/dev/null", root))
    table.sort(manifests)
    for _, manifest in ipairs(manifests) do
      local dir = dirname(manifest)
      local api = join(dir, "ui/API.md")
      local problems
      if not exists(api) then
        problems = "missing ui/API.md"
      else
        local missing = tendlib.missing_sections(read(api))
        if #missing > 0 then
          problems = "missing sections: " .. table.concat(missing, ", ")
        end
      end
      if not problems then
        -- Documented: nothing to report, and a matching baseline line is now
        -- redundant.
      elseif baseline[dir] then
        baselined = baselined + 1
        tolerated[dir] = true
      else
        failures[#failures + 1] = { dir = dir, problems = problems }
      end
    end
  end

  for _, failure in ipairs(failures) do
    io.stderr:write("FAIL " .. failure.dir .. "\n     " .. failure.problems .. "\n")
  end

  local stale = {}
  for dir in pairs(baseline) do
    if not tolerated[dir] then stale[#stale + 1] = dir end
  end
  table.sort(stale)
  if #stale > 0 then
    io.stderr:write("tend: " .. #stale
      .. " baseline entr(ies) no longer needed; prune tools/api-baseline.txt:\n")
    for _, dir in ipairs(stale) do io.stderr:write("     " .. dir .. "\n") end
  end

  if #failures > 0 then
    io.stderr:write(string.format(
      "tend: %d undocumented Spore UI(s); %d tolerated by baseline\n",
      #failures, baselined))
    return false
  end
  if options.strict_baseline and #stale > 0 then
    io.stderr:write("tend: --strict-baseline and the baseline is stale\n")
    return false
  end
  print(string.format("tend: api-check ok (%d tolerated by baseline)", baselined))
  return true
end

local function load_workspace(options)
  if options.no_workspace then return nil end
  local root = options.workspace
  if not root then
    if exists("tend.lua") then root = "." else return nil end
  end
  local config_path = join(root, "tend.lua")
  local config = {}
  if exists(config_path) then
    local chunk, error_message = loadfile(config_path)
    assert(chunk, "cannot load " .. config_path .. ": " .. tostring(error_message))
    local ok, value = pcall(chunk)
    assert(ok, "cannot evaluate " .. config_path .. ": " .. tostring(value))
    if type(value) == "table" then config = value end
  end
  local members = {}
  for _, pattern in ipairs(config.members or {}) do
    for _, path in ipairs(expand_pattern(root, pattern)) do members[#members + 1] = path end
  end
  local components = {}
  for _, pattern in ipairs(config.components or {}) do
    for _, path in ipairs(expand_pattern(root, pattern)) do components[#components + 1] = path end
  end
  for _, member in ipairs(members) do
    if exists(join(member, "spore.toml")) then
      for _, candidate in ipairs({ "ui/components.lua", "components.lua", "ui/index.lua" }) do
        local path = join(member, candidate)
        if exists(path) then components[#components + 1] = path end
      end
    end
  end
  local seen, unique = {}, {}
  for _, path in ipairs(components) do
    if not seen[path] then seen[path] = true; unique[#unique + 1] = path end
  end
  return { root = root, config = config, members = members, components = unique }
end

local function apply_workspace(options)
  local workspace = load_workspace(options)
  if not workspace then return nil end
  options.workspace_data = workspace
  local seen = {}
  for _, path in ipairs(options.components) do seen[path] = true end
  for _, path in ipairs(workspace.components) do
    if not seen[path] then seen[path] = true; options.components[#options.components + 1] = path end
  end
  if not options.out and workspace.config.modules then options.out = join(workspace.root, workspace.config.modules) end
  return workspace
end

local function list_workspace(options)
  local workspace = apply_workspace(options)
  if not workspace then
    print("tend: no workspace (create tend.lua with members/components)")
    return
  end
  print("workspace " .. workspace.root)
  for _, member in ipairs(workspace.members) do
    local name = member:match("([^/]+)$") or member
    print("  member    " .. name .. "  " .. member)
  end
  for _, component in ipairs(workspace.components) do
    print("  component " .. component)
  end
end

local MODULES = {
  ["fungos.ui"] = "lua/fungos/ui.lua",
  ["fungos.config"] = "lua/fungos/config.lua",
  ["fungos.compose"] = "lua/fungos/compose.lua",
  ["fungos.action"] = "lua/fungos/action.lua",
  ["fungos.chart"] = "lua/fungos/chart.lua",
  ["fungos.viz"] = "lua/fungos/viz.lua",
  ["fungos.graph"] = "lua/fungos/graph.lua",
  ["fungos.map"] = "lua/fungos/map.lua",
  ["fungos.atlas"] = "lua/fungos/atlas.lua",
  ["fungos.live"] = "lua/fungos/live.lua",
}

local function module_loaders(sdk)
  local chunks = {}
  for name, path in pairs(MODULES) do
    local source = strip_comments(read(join(sdk, path)))
    chunks[#chunks + 1] = string.format(
      '[%q] = function(require)\n%s\nend',
      name,
      source
    )
  end
  return table.concat(chunks, ",\n")
end

local function flatten(node, x, y, width, height, out)
  if type(node) ~= "table" then return end
  local rect = { x = x, y = y, width = width, height = height }
  out[#out + 1] = {
    id = node.id,
    kind = node.kind,
    text = node.text,
    style = node.style,
    rect = rect,
  }
  for index, child in ipairs(node.children or {}) do
    flatten(child, x, y + (index - 1) * 20, width, 20, out)
  end
end

local function json_escape(value)
  return '"' .. tostring(value):gsub('[%z\1-\31\\"]', function(char)
    local map = { ['"'] = '\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }
    return map[char] or string.format('\\u%04x', char:byte())
  end) .. '"'
end

local function json(value, array_hint)
  local kind = type(value)
  if kind == "nil" then return "null" end
  if kind == "boolean" then return value and "true" or "false" end
  if kind == "number" then
    if value ~= value or value == math.huge or value == -math.huge then error("non-finite JSON number") end
    return tostring(value)
  end
  if kind == "string" then return json_escape(value) end
  if kind ~= "table" then error("cannot encode " .. kind .. " as JSON") end
  local array = true
  local count = 0
  for key in pairs(value) do
    count = count + 1
    if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then array = false end
  end
  if (array and (count > 0 or array_hint)) then
    local out = {}
    for index = 1, count do out[index] = json(value[index]) end
    return "[" .. table.concat(out, ",") .. "]"
  end
  local keys = {}
  for key in pairs(value) do keys[#keys + 1] = tostring(key) end
  table.sort(keys)
  local out = {}
  for _, key in ipairs(keys) do
    local child_hint = key == "children" or key == "nodes" or key == "hits"
    out[#out + 1] = json_escape(key) .. ":" .. json(value[key], child_hint)
  end
  return "{" .. table.concat(out, ",") .. "}"
end

local function host_env(options)
  local width = tonumber(options.width) or 1200
  local height = tonumber(options.height) or 900
  -- `--now` takes epoch milliseconds, matching module.now.epoch_ms. Without it a
  -- captured scene depends on the wall clock, so two runs of the same view
  -- disagree and no golden fixture is possible. Civil time stays local, which
  -- is what a Spore rendering a clock should see; tests pin TZ instead.
  local now = tonumber(options.now) and math.floor(tonumber(options.now) / 1000) or os.time()
  local civil = os.date("*t", now)
  local validate = dofile(join(options.sdk, "lua/fungos/validate.lua"))

  -- A real palette when one is supplied (--theme <file.lua> returning a token
  -- table), otherwise the documented stand-ins. Either way it is wrapped so an
  -- unknown token is an error rather than a nil that renders blank.
  local tokens = themelib.tokens
  if options.theme then
    local supplied = assert(loadfile(options.theme), "cannot load theme " .. options.theme)()
    assert(type(supplied) == "table", "theme " .. options.theme .. " must return a table")
    tokens = supplied
  end

  local env = {
    module = {
      viewport = { width = width, height = height },
      theme = themelib.strict(tokens),
      now = {
        epoch_ms = now * 1000,
        year = civil.year, month = civil.month, day = civil.day,
        hour = civil.hour, minute = civil.min, second = civil.sec,
        weekday = civil.wday,
      },
    },
    canvas = {
      layout = function(tree, available_width, available_height)
        validate.tree(tree)
        local w, h = available_width or width, available_height or height
        local command = os.getenv("SOIL_LAYOUT")
        if command and command ~= "" then
          local input = os.tmpname()
          local file = assert(io.open(input, "wb"), "cannot write layout input")
          file:write(json(tree))
          file:close()
          local pipe = assert(io.popen(string.format("%s --input %q --width %s --height %s --lua", command, input, w, h), "r"))
          local output = pipe:read("*a")
          pipe:close()
          os.remove(input)
          local laid = assert(load(output, "@soil-layout"))()
          return laid
        end
        local nodes = {}
        flatten(tree, 0, 0, w, h, nodes)
        return { root = { x = 0, y = 0, width = w, height = h }, nodes = nodes }
      end,
      measure_text = function(text, style)
        local size = (style and style.size) or 16
        return { width = #tostring(text or "") * size * 0.55, height = (style and style.line_height) or size }
      end,
      rect = function(args) validate.rect(args) end,
      text = function(args) validate.text(args) end,
    },
    widget = {
      hit = function(args)
        if type(args) ~= "table" then error("widget.hit needs a table", 2) end
        if type(args.id) ~= "string" or args.id == "" then error("widget.hit id must be a string", 2) end
        for _, key in ipairs({ "x", "y", "width", "height" }) do
          local value = args[key]
          if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
            error("widget.hit " .. key .. " must be finite", 2)
          end
        end
        if args.width <= 0 or args.height <= 0 then error("widget.hit needs positive size", 2) end
        if args.x < -4 or args.x > 4 or args.y < -4 or args.y > 4
          or args.x + args.width > 4.0001 or args.y + args.height > 4.0001 then
          error("widget.hit geometry is outside the normalized surface", 2)
        end
      end,
    },
  }
  local standard = {
    assert = assert, error = error, getmetatable = getmetatable, ipairs = ipairs,
    next = next, pairs = pairs, pcall = pcall, rawequal = rawequal,
    rawget = rawget, rawlen = rawlen, rawset = rawset, select = select,
    setmetatable = setmetatable, tonumber = tonumber, tostring = tostring,
    type = type, unpack = unpack, xpcall = xpcall,
    math = math, string = string, table = table, utf8 = utf8,
  }
  for key, value in pairs(standard) do env[key] = value end
  env._G = env
  return env
end

local function capture(source, name, options)
  local env = host_env(options)
  local chunk, load_error = load(source, "@" .. name, "t", env)
  if not chunk then
    io.stderr:write("tend: scene load failed: " .. tostring(load_error) .. "\n")
    os.exit(2)
  end
  local ok, present, hits = pcall(chunk)
  if not ok then
    io.stderr:write("tend: scene failed: " .. tostring(present) .. "\n")
    os.exit(2)
  end
  if type(present) ~= "table" or present.kind ~= "scene" then
    io.stderr:write("tend: view did not return a soil_scene present\n")
    os.exit(2)
  end
  local path = options.scene
  local file = assert(io.open(path, "wb"), "cannot write " .. path)
  file:write(json(present))
  file:close()
  local hits_path = path .. ".hits.json"
  file = assert(io.open(hits_path, "wb"), "cannot write " .. hits_path)
  file:write(json(hits or {}, true))
  file:close()
  print(string.format("tend: wrote %s (%d nodes, %d hits)", path, #(present.nodes or {}), #(hits or {})))
end

local function preflight(source, name, options)
  if options.preflight == false then return end
  local validate = dofile(join(options.sdk, "lua/fungos/validate.lua"))
  local env = host_env(options)
  local chunk, load_error = load(source, "@" .. name, "t", env)
  if not chunk then
    io.stderr:write("tend: preflight load failed: " .. tostring(load_error) .. "\n")
    os.exit(2)
  end
  local ok, runtime_error = pcall(chunk)
  if not ok then
    io.stderr:write("tend: preflight failed: " .. tostring(runtime_error) .. "\n")
    os.exit(2)
  end
  print("tend: preflight ok")
end

local function compose(options)
  assert(options.view, "usage: tend <view.lua> [snapshot.lua] [options]")
  assert(exists(options.view), "missing view: " .. options.view)
  if not check_api(options) then os.exit(2) end

  local snapshot_path = options.snapshot
  assert(snapshot_path, "missing --snapshot <file.lua>")
  assert(exists(snapshot_path), "missing snapshot: " .. snapshot_path)

  local config_source = exists(options.config) and read(options.config) or "return {}"
  local view_source = strip_comments(read(options.view))
  local snapshot_source = strip_comments(read(snapshot_path))
  local loaders = module_loaders(options.sdk)
  local app = options.app or ""
  local component_loaders = {}
  for index, path in ipairs(options.components or {}) do
    assert(exists(path), "missing component: " .. path)
    local source = strip_comments(read(path))
    component_loaders[#component_loaders + 1] = string.format(
      "[%d] = { source = %q, factory = function(require)\n%s\nend }",
      index,
      path,
      source
    )
  end

  local composed = table.concat({
    "-- generated by fungos-sdk/tools/tend.lua",
    "-- view: " .. options.view,
    "-- snapshot: " .. snapshot_path,
    "-- app: " .. app,
    "local __modules = {",
    loaders,
    "}",
    "local __cache = {}",
    "local function __require(name)",
    "  if __cache[name] then return __cache[name] end",
    "  local loader = __modules[name]",
    "  if not loader then error('unknown SDK module ' .. tostring(name)) end",
    "  local module = loader(__require)",
    "  __cache[name] = module",
    "  return module",
    "end",
    "local snapshot = (function()",
    snapshot_source,
    "end)()",
    "local user_profile = (function()",
    config_source,
    "end)()",
    "local __ui = __require('fungos.ui')",
    "__ui.configure(user_profile, " .. string.format("%q", app) .. ")",
    "local __component_modules = {",
    table.concat(component_loaders, ",\n"),
    "}",
    "local __compose = __require('fungos.compose')",
    "local __registry = __compose.registry()",
    "for _, item in ipairs(__component_modules) do",
    "  local module = item.factory(__require)",
    "  if type(module) == 'function' then module = module() end",
    "  __registry:add(module, item.source)",
    "end",
    "local __ctx = { snapshot = snapshot, viewport = { width = 1200, height = 900 }, theme = __ui.theme(), now = { epoch_ms = __ui.now_ms() } }",
    "__ui.set_component_resolver(function(tree)",
    "  return __compose.apply(tree, __registry, __ctx, function(name, source)",
    "    print('tend: missing component ' .. tostring(name) .. ' from ' .. tostring(source))",
    "  end)",
    "end)",
    "local view = (function(require)",
    view_source,
    "end)(__require)",
    "if type(view) == 'function' then view = { render = view } end",
    "if type(view) ~= 'table' or type(view.render) ~= 'function' then",
    "  error('view must return a function or a module with render(snapshot)')",
    "end",
    "if __scene_capture then",
    "  local present, hits = __ui.capture(" .. (tonumber(options.width) or 1200) .. ", " .. (tonumber(options.height) or 900) .. ", __ui.theme(), function() view.render(snapshot) end)",
    "  return present, hits",
    "end",
    "view.render(snapshot)",
    "",
  }, "\n")

  local name = options.name
  if options.scene then
    local source = composed:gsub("__scene_capture", "true")
    capture(source, name, options)
    return
  end
  preflight(composed, name, options)
  if options.check then
    print("tend: check ok")
    return
  end
  local output_dir = options.out or options.modules
  os.execute(string.format("mkdir -p %q", output_dir))
  local module_path = join(output_dir, name .. ".lua")
  local manifest_path = join(output_dir, name .. ".json")

  local file = assert(io.open(module_path, "wb"), "cannot write " .. module_path)
  file:write(composed)
  file:close()

  file = assert(io.open(manifest_path, "wb"), "cannot write " .. manifest_path)
  file:write(string.format(
    '{"schema_version":1,"id":"%s","title":"tend preview","inputs":[],"resources":[],"capabilities":{"write_scene":true,"read_inputs":[],"read_theme":true}}',
    name
  ))
  file:close()

  print(string.format("tend: wrote %s (%d bytes)", module_path, #composed))
  return module_path
end

local function reload(options)
  local command = string.format(
    "printf '%s' | canvasctl",
    string.format('{"schema_version":1,"request_id":"tend","command":{"command":"reload_module","surface_id":"%s"}}', options.surface)
  )
  local ok = os.execute(command)
  if ok ~= 0 and ok ~= true then
    io.stderr:write("tend: canvasctl reload failed for surface " .. options.surface .. "\n")
    return false
  end
  print("tend: reloaded surface " .. options.surface)
  return true
end

local function doctor(options)
  local failures = 0
  local function report(ok, message)
    print((ok and "ok   " or "FAIL ") .. message)
    if not ok then failures = failures + 1 end
  end

  report(exists(options.sdk), "SDK at " .. options.sdk)
  for name, path in pairs(MODULES) do
    report(exists(join(options.sdk, path)), name .. " -> " .. path)
  end
  local profile_ok = exists(options.config)
  if profile_ok then
    report(true, "profile " .. options.config)
  else
    print("skip profile " .. options.config .. " (optional)")
  end
  if options.view then
    report(exists(options.view), "view " .. options.view)
    report(not options.check_api or exists(api_path(options.view)),
      "Lua API docs " .. api_path(options.view))
  end
  if options.snapshot then
    report(exists(options.snapshot), "snapshot " .. options.snapshot)
  end
  for _, path in ipairs(options.components or {}) do
    report(exists(path), "component " .. path)
  end
  return failures == 0
end

local argv = arg or {}
local command = nil
if argv[1] and tendlib.commands[argv[1]] then
  command = table.remove(argv, 1)
end

local options = parse(argv)
if command == "api-check" then
  os.exit(api_check(options) and 0 or 1)
elseif command == "check" then
  options.check = true
  options.reload = false
elseif command == "build" then
  options.reload = false
elseif command == "list" then
  list_workspace(options)
  os.exit(0)
elseif command == "doctor" then
  options.doctor = true
end
apply_workspace(options)
if options.doctor then
  os.exit(doctor(options) and 0 or 1)
end

compose(options)
if options.check then
  os.exit(0)
end
if options.reload and options.surface then
  reload(options)
elseif options.reload then
  print("tend: no --surface given; skipped reload")
end
