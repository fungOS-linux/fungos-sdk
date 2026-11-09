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

local function is_dir(path)
  -- A directory renames to itself; a missing path does not.
  return os.rename(path, path) ~= nil
end

local function check(path)
  local root = dirname(path)
  local ui_dir = root .. "/ui"
  local errors = {}

  -- No Lua UI means no API to document. A Spore with a `ui/` directory does.
  if not is_dir(ui_dir) then
    return true, {}, false
  end

  local ui = ui_dir .. "/API.md"
  if not exists(ui) then
    errors[#errors + 1] = "missing " .. ui
    return false, errors, true
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
  return #errors == 0, errors, true
end

local function usage()
  print("usage: check-spores [ROOT...]")
  print("")
  print("Every Spore with a ui/ directory must have ui/API.md with the")
  print("contract sections. ROOT defaults to `.`.")
end

local roots = {}
for _, value in ipairs(arg) do
  if value == "--help" or value == "-h" then
    usage()
    os.exit(0)
  elseif value:sub(1, 1) == "-" then
    io.stderr:write("check-spores: unknown option " .. value .. "\n")
    io.stderr:write("try --help\n")
    os.exit(2)
  else
    roots[#roots + 1] = value
  end
end
if #roots == 0 then roots = { "." } end

for _, root in ipairs(roots) do
  if not is_dir(root) then
    io.stderr:write("check-spores: not a directory: " .. root .. "\n")
    os.exit(2)
  end
end

local found = manifests(roots)
if #found == 0 then
  io.stderr:write("check-spores: no spore.toml found under " .. table.concat(roots, ", ") .. "\n")
  os.exit(2)
end

local failures = 0
for _, manifest in ipairs(found) do
  local ok, errors, has_ui = check(manifest)
  if not has_ui then
    print("skip " .. dirname(manifest) .. " (no ui/)")
  elseif ok then
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
