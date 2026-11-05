#!/usr/bin/env lua
-- Check that every Spore with a Lua UI documents its Lua API.
--
-- The Lua API is part of the package ABI. This check is intentionally boring:
-- find spore.toml, find ui/API.md, require the contract sections. It does not
-- try to parse prose or judge quality.

local REQUIRED = {
  "entrypoint",
  "snapshot",
  "actions",
  "slots",
  "components",
  "theme/config",
  "stable ids",
  "authority",
}

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

local function manifests(roots)
  local found = {}
  for _, root in ipairs(roots) do
    local pipe = assert(io.popen(string.format("find %q -name spore.toml -type f", root)))
    for path in pipe:lines() do found[#found + 1] = path end
    pipe:close()
  end
  table.sort(found)
  return found
end

local function check(path)
  local root = dirname(path)
  local ui = root .. "/ui/API.md"
  local errors = {}

  if not exists(ui) then
    errors[#errors + 1] = "missing " .. ui
    return false, errors
  end

  local headings = {}
  for heading in read(ui):gmatch("## ([^\n]+)") do
    headings[#headings + 1] = heading:lower()
  end
  for _, section in ipairs(REQUIRED) do
    local found = false
    for _, heading in ipairs(headings) do
      if heading:find(section, 1, true) then found = true break end
    end
    if not found then
      errors[#errors + 1] = "missing section containing " .. section
    end
  end
  return #errors == 0, errors
end

local roots = arg
if #roots == 0 then roots = { "." } end

local failures = 0
for _, manifest in ipairs(manifests(roots)) do
  local ok, errors = check(manifest)
  if ok then
    print("ok   " .. dirname(manifest) .. "/ui/API.md")
  else
    failures = failures + 1
    print("FAIL " .. manifest)
    for _, error in ipairs(errors) do print("     " .. error) end
  end
end

if failures > 0 then
  io.stderr:write(string.format("%d Spore Lua API document(s) failed\n", failures))
  os.exit(1)
end
print("all Spore Lua APIs documented")
