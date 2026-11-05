-- fungos.validate — preflight checks for Spore UI trees and scene calls.
--
-- This runs in the development loop (`mush`) before a module is written or
-- reloaded. It catches the things Canvas would otherwise reject at runtime:
--
--   nil holes / sparse child arrays
--   non-table children
--   empty or duplicate node ids
--   invalid kinds
--   non-finite layout/style numbers
--   functions, cycles, or host objects in the tree
--   malformed canvas.rect / canvas.text calls
--
-- Validation is a developer affordance. The host still validates everything it
-- accepts; this just moves the failure into the edit loop.

local validate = {}

local MAX_NODES = 10000
local MAX_DEPTH = 64

local KINDS = {
  container = true,
  text = true,
  rule = true,
  spacer = true,
  component = true,
}

local LAYOUT_NUMBERS = {
  "width", "height", "min_width", "max_width", "min_height", "max_height",
  "gap", "flex_grow", "flex_shrink", "flex_basis",
}

local STYLE_NUMBERS = { "size", "line_height" }

local function is_finite_number(value)
  return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function check_number_table(value, path, names)
  if value == nil then return end
  if type(value) ~= "table" then
    error(path .. " must be a table", 3)
  end
  for _, name in ipairs(names) do
    local item = value[name]
    if item ~= nil and not is_finite_number(item) then
      error(path .. "." .. name .. " must be a finite number", 3)
    end
    if item ~= nil and (name == "width" or name == "height" or name == "size"
      or name == "line_height" or name == "min_width" or name == "max_width"
      or name == "min_height" or name == "max_height" or name == "flex_grow") then
      if item < 0 then error(path .. "." .. name .. " must be non-negative", 3) end
    end
  end
end

local function check_edges(value, path)
  if value == nil then return end
  if type(value) ~= "table" then error(path .. " must be a table", 3) end
  for _, side in ipairs({ "top", "right", "bottom", "left" }) do
    local item = value[side]
    if item ~= nil and (not is_finite_number(item) or item < 0) then
      error(path .. "." .. side .. " must be a finite non-negative number", 3)
    end
  end
end

local function check_array(value, path)
  if type(value) ~= "table" then
    error(path .. " must be an array", 3)
  end
  local count, max = 0, 0
  for key in pairs(value) do
    if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
      error(path .. " has a non-array key " .. tostring(key), 3)
    end
    count = count + 1
    if key > max then max = key end
  end
  if count ~= max then
    error(path .. " is sparse (" .. count .. " entries, max index " .. max .. ")", 3)
  end
  for index = 1, max do
    if value[index] == nil then
      error(path .. " has a nil hole at index " .. index, 3)
    end
  end
end

local function check_text(value, path)
  if type(value) ~= "string" then error(path .. " must be a string", 3) end
  local ok = utf8 and utf8.len and utf8.len(value)
  if utf8 and utf8.len then
    local length = utf8.len(value)
    if not length then error(path .. " must be valid UTF-8", 3) end
  end
  if value:find("[%z\1-\31\127]") then
    error(path .. " contains a non-printable control character", 3)
  end
  if not value:match("%S") then
    error(path .. " must not be empty or whitespace", 3)
  end
end

local function string_id(value, path)
  if type(value) ~= "string" or value == "" then
    error(path .. " must be a non-empty string id", 3)
  end
  if #value > 160 then
    error(path .. " id is too long", 3)
  end
end

local function walk(node, path, state, depth)
  if depth > MAX_DEPTH then error(path .. " exceeds max depth", 3) end
  if type(node) ~= "table" then
    error(path .. " must be a table, got " .. type(node), 3)
  end
  if state.seen[node] then error(path .. " contains a cycle or reused table", 3) end
  state.seen[node] = true
  state.nodes = state.nodes + 1
  if state.nodes > MAX_NODES then error(path .. " exceeds node limit", 3) end

  string_id(node.id, path .. ".id")
  if state.ids[node.id] then
    error("duplicate node id " .. node.id .. " at " .. path, 3)
  end
  state.ids[node.id] = true

  if not KINDS[node.kind] then
    error(path .. ".kind is invalid: " .. tostring(node.kind), 3)
  end

  if node.layout ~= nil then
    if type(node.layout) ~= "table" then error(path .. ".layout must be a table", 3) end
    check_number_table(node.layout, path .. ".layout", LAYOUT_NUMBERS)
    check_edges(node.layout.padding, path .. ".layout.padding")
  end

  if node.style ~= nil then
    if type(node.style) ~= "table" then error(path .. ".style must be a table", 3) end
    check_number_table(node.style, path .. ".style", STYLE_NUMBERS)
  end

  if node.kind == "text" then
    check_text(node.text, path .. ".text")
    if node.style == nil then
      error(path .. ".style is required for text", 3)
    end
    if node.style.size == nil then
      error(path .. ".style.size is required for text", 3)
    end
  end

  if node.kind == "component" then
    if type(node.name) ~= "string" or node.name == "" then
      error(path .. ".name is required for component", 3)
    end
  end

  if node.children ~= nil then
    check_array(node.children, path .. ".children")
    for index, child in ipairs(node.children) do
      walk(child, path .. ".children[" .. index .. "]", state, depth + 1)
    end
  end

  -- A node may carry presentation metadata. Reject functions and host objects,
  -- but allow booleans/numbers/strings and nested plain tables.
  for key, value in pairs(node) do
    local value_type = type(value)
    if value_type == "function" or value_type == "userdata" or value_type == "thread" then
      error(path .. "." .. tostring(key) .. " contains a " .. value_type, 3)
    end
  end
end

--- Validate a semantic tree. Raises on the first structural error.
function validate.tree(tree)
  if type(tree) ~= "table" then error("tree must be a table", 2) end
  walk(tree, "tree", { seen = {}, ids = {}, nodes = 0 }, 0)
  return tree
end

local function check_vec3(value, path)
  if type(value) ~= "table" or #value ~= 3 then
    error(path .. " must be a 3-element array", 3)
  end
  for index = 1, 3 do
    if not is_finite_number(value[index]) then
      error(path .. "[" .. index .. "] must be a finite number", 3)
    end
  end
end

--- Validate a canvas.rect call.
function validate.rect(args)
  if type(args) ~= "table" then error("canvas.rect needs a table", 2) end
  string_id(args.id, "rect.id")
  if type(args.ink) ~= "string" or args.ink == "" then
    error("rect.ink must be a non-empty string", 2)
  end
  if args.opacity ~= nil and (not is_finite_number(args.opacity) or args.opacity < 0 or args.opacity > 1) then
    error("rect.opacity must be 0..1", 2)
  end
  if args.radius ~= nil and (not is_finite_number(args.radius) or args.radius < 0) then
    error("rect.radius must be non-negative", 2)
  end
  check_vec3(args.translation, "rect.translation")
  check_vec3(args.scale, "rect.scale")
  return args
end

--- Validate a canvas.text call.
function validate.text(args)
  if type(args) ~= "table" then error("canvas.text needs a table", 2) end
  string_id(args.id, "text.id")
  check_text(args.text, "text.text")
  if type(args.ink) ~= "string" or args.ink == "" then
    error("text.ink must be a non-empty string", 2)
  end
  check_vec3(args.translation, "text.translation")
  check_vec3(args.scale, "text.scale")
  return args
end

return validate
