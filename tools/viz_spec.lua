#!/usr/bin/env lua
-- Encode a Lua live-viz spec as JSON. The spec is data; the Rust host owns the
-- frame loop and streams.

local ROOT = (debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\][^/\\]+$") or ".") .. "/.."
package.path = ROOT .. "/lua/?.lua;" .. ROOT .. "/lua/?/init.lua;" .. package.path

local function json_escape(value)
  return '"' .. tostring(value):gsub('[%z\1-\31\\"]', function(char)
    local map = {
      ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f',
      ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t',
    }
    return map[char] or string.format('\\u%04x', char:byte())
  end) .. '"'
end

local function json(value)
  local kind = type(value)
  if kind == "nil" then return "null" end
  if kind == "boolean" then return value and "true" or "false" end
  if kind == "number" then
    if value ~= value or value == math.huge or value == -math.huge then
      error("non-finite JSON number")
    end
    return tostring(value)
  end
  if kind == "string" then return json_escape(value) end
  if kind ~= "table" then error("cannot encode " .. kind .. " as JSON") end
  local count, array = 0, true
  for key in pairs(value) do
    count = count + 1
    if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then array = false end
  end
  if array then
    local out = {}
    for index = 1, count do out[index] = json(value[index]) end
    return "[" .. table.concat(out, ",") .. "]"
  end
  local keys = {}
  for key in pairs(value) do keys[#keys + 1] = tostring(key) end
  table.sort(keys)
  local out = {}
  for _, key in ipairs(keys) do
    out[#out + 1] = json_escape(key) .. ":" .. json(value[key])
  end
  return "{" .. table.concat(out, ",") .. "}"
end

local source = arg[1] or (ROOT .. "/examples/viz_live.lua")
local out_path = arg[2] or "/tmp/fungos-viz-live.json"
local spec = assert(loadfile(source))()
if type(spec) ~= "table" then error("spec module must return a table") end
local tmp = out_path .. ".tmp"
local file = assert(io.open(tmp, "wb"), "cannot write " .. tmp)
file:write(json(spec))
file:close()
assert(os.rename(tmp, out_path), "cannot replace " .. out_path)
print(string.format("viz_spec: wrote %s (%d layers)", out_path, #(spec.layers or {})))
