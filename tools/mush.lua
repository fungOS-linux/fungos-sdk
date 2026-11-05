#!/usr/bin/env lua
-- mush — compose a Spore UI view into a Canvas module and reload one surface.
--
-- This is a development tool, not a host capability. It runs outside the Spore
-- sandbox so it may read files, invoke canvasctl, and write the modules dir.
--
--   mush ui/inbox.lua \
--     --snapshot examples/inbox_snapshot.lua \
--     --app dev.fungos.unibus \
--     --surface md
--
-- The generated module contains the SDK modules, the view, the snapshot, and
-- the resolved user profile. It uses a tiny require shim because Canvas does
-- not load packages at runtime.

local function script_dir()
  local source = debug.getinfo(1, "S").source:sub(2)
  return source:match("^(.*)[/\\][^/\\]+$") or "."
end

local ROOT = script_dir() .. "/.."

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

local function parse(argv)
  local options = {
    surface = "md",
    name = "mush-preview",
    reload = true,
    check_api = true,
    sdk = os.getenv("FUNGOS_SDK") or ROOT,
    config = os.getenv("FUNGOS_CONFIG") or ((os.getenv("HOME") or "") .. "/.config/fungos/ui.lua"),
    modules = os.getenv("FUNGOS_MODULES") or ((os.getenv("HOME") or "") .. "/Library/Application Support/Dock/canvas/modules"),
  }
  local positional = {}
  local index = 1
  while index <= #argv do
    local arg = argv[index]
    if arg == "--doctor" then
      options.doctor = true
    elseif arg == "--no-reload" then
      options.reload = false
    elseif arg == "--allow-undocumented" then
      options.check_api = false
    elseif arg:sub(1, 2) == "--" then
      local key = arg:sub(3):gsub("-", "_")
      index = index + 1
      options[key] = argv[index]
    else
      positional[#positional + 1] = arg
    end
    index = index + 1
  end
  options.view = positional[1]
  options.snapshot = positional[2] or options.snapshot
  return options
end

local function strip_comments(source)
  local out = {}
  local index, length = 1, #source
  local quote
  while index <= length do
    local char = source:sub(index, index)
    if quote then
      out[#out + 1] = char
      if char == "\\" then
        index = index + 1
        out[#out + 1] = source:sub(index, index)
      elseif char == quote then
        quote = nil
      end
      index = index + 1
    elseif char == '"' or char == "'" then
      quote = char
      out[#out + 1] = char
      index = index + 1
    elseif char == "-" and source:sub(index + 1, index + 1) == "-" then
      while index <= length and source:sub(index, index) ~= "\n" do index = index + 1 end
    else
      out[#out + 1] = char
      index = index + 1
    end
  end
  local lines = {}
  for raw in table.concat(out):gmatch("([^\n]*)\n?") do
    local line = raw:gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" then lines[#lines + 1] = line end
  end
  return table.concat(lines, "\n")
end

local function api_path(view)
  local ui_dir = dirname(view)
  return join(ui_dir, "API.md")
end

local API_SECTIONS = {
  "entrypoint", "snapshot", "actions", "slots", "components",
  "theme/config", "stable ids", "authority",
}

local function check_api(options)
  if not options.check_api then return true end
  local path = api_path(options.view)
  if not exists(path) then
    io.stderr:write("mush: missing Lua API documentation: " .. path .. "\n")
    io.stderr:write("mush: every Spore UI must ship ui/API.md; see docs/lua-api-contract.md\n")
    return false
  end
  local headings = {}
  for heading in read(path):gmatch("## ([^\n]+)") do
    headings[#headings + 1] = heading:lower()
  end
  local missing = {}
  for _, section in ipairs(API_SECTIONS) do
    local found = false
    for _, heading in ipairs(headings) do
      if heading:find(section, 1, true) then found = true break end
    end
    if not found then missing[#missing + 1] = section end
  end
  if #missing > 0 then
    io.stderr:write("mush: " .. path .. " is missing: " .. table.concat(missing, ", ") .. "\n")
    return false
  end
  return true
end

local MODULES = {
  ["fungos.ui"] = "lua/fungos/ui.lua",
  ["fungos.config"] = "lua/fungos/config.lua",
  ["fungos.compose"] = "lua/fungos/compose.lua",
  ["fungos.action"] = "lua/fungos/action.lua",
}

local function module_loaders(sdk)
  local chunks = {}
  for name, path in pairs(MODULES) do
    local source = strip_comments(read(join(sdk, path)))
    chunks[#chunks + 1] = string.format(
      '[%q] = function()\n%s\nend',
      name,
      source
    )
  end
  return table.concat(chunks, ",\n")
end

local function compose(options)
  assert(options.view, "usage: mush <view.lua> [snapshot.lua] [options]")
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

  local composed = table.concat({
    "-- generated by fungos-sdk/tools/mush.lua",
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
    "  local module = loader()",
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
    "local view = (function(require)",
    view_source,
    "end)(__require)",
    "if type(view) == 'function' then view = { render = view } end",
    "if type(view) ~= 'table' or type(view.render) ~= 'function' then",
    "  error('view must return a function or a module with render(snapshot)')",
    "end",
    "view.render(snapshot)",
    "",
  }, "\n")

  local name = options.name
  local module_path = join(options.modules, name .. ".lua")
  local manifest_path = join(options.modules, name .. ".json")

  local file = assert(io.open(module_path, "wb"), "cannot write " .. module_path)
  file:write(composed)
  file:close()

  file = assert(io.open(manifest_path, "wb"), "cannot write " .. manifest_path)
  file:write(string.format(
    '{"schema_version":1,"id":"%s","title":"mush preview","inputs":[],"resources":[],"capabilities":{"write_scene":true,"read_inputs":[],"read_theme":true}}',
    name
  ))
  file:close()

  print(string.format("mush: wrote %s (%d bytes)", module_path, #composed))
  return module_path
end

local function reload(options)
  local command = string.format(
    "printf '%s' | canvasctl",
    string.format('{"command":{"command":"reload_module","surface_id":"%s"}}', options.surface)
  )
  local ok = os.execute(command)
  if ok ~= 0 and ok ~= true then
    io.stderr:write("mush: canvasctl reload failed for surface " .. options.surface .. "\n")
    return false
  end
  print("mush: reloaded surface " .. options.surface)
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
  return failures == 0
end

local options = parse(arg or {})
if options.doctor then
  os.exit(doctor(options) and 0 or 1)
end

compose(options)
if options.reload then reload(options) end
