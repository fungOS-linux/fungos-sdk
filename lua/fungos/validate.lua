-- fungos.validate — preflight checks for Spore UI trees and scene calls.
--
-- This runs in the development loop (`tend`) before a module is written or
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
-- A runaway tree (a generator loop, a bad map over a large collection) can
-- produce thousands of distinct problems. Fifty is enough to see the pattern
-- and fix it, and it bounds both the output and the rest of the walk.
local MAX_ERRORS = 50

local KINDS = {
  container = true,
  text = true,
  text_input = true,
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

--- Record one problem.
---
--- A problem is `path` (where) plus `message` (what). Strict mode — what
--- `validate.tree` has always done — renders the pair as one sentence and
--- raises it; collect mode keeps them apart so a caller can print or group
--- them however it likes.
---
--- Returns `false`, so a check can `return fail(...)` to stop looking at a node
--- that is already known bad. Continuing would report derived noise ("style is
--- required for text" followed by "style.size is required for text").
local function fail(report, path, message)
  if report.strict then error(path .. " " .. message, 3) end
  if report.capped then return false end
  if #report.problems >= MAX_ERRORS then
    report.capped = true
    return false
  end
  report.problems[#report.problems + 1] = { path = path, message = message }
  return false
end

local function check_number_table(report, value, path, names)
  if value == nil then return true end
  if type(value) ~= "table" then
    return fail(report, path, "must be a table")
  end
  for _, name in ipairs(names) do
    local item = value[name]
    if item ~= nil and not is_finite_number(item) then
      return fail(report, path .. "." .. name, "must be a finite number")
    end
    if item ~= nil and (name == "width" or name == "height" or name == "size"
      or name == "line_height" or name == "min_width" or name == "max_width"
      or name == "min_height" or name == "max_height" or name == "flex_grow") then
      if item < 0 then return fail(report, path .. "." .. name, "must be non-negative") end
    end
  end
  return true
end

local function check_edges(report, value, path)
  if value == nil then return true end
  if type(value) ~= "table" then return fail(report, path, "must be a table") end
  for _, side in ipairs({ "top", "right", "bottom", "left" }) do
    local item = value[side]
    if item ~= nil and (not is_finite_number(item) or item < 0) then
      return fail(report, path .. "." .. side, "must be a finite non-negative number")
    end
  end
  return true
end

--- Validate a children array, returning the highest index worth walking.
---
--- A sparse array is a problem, but the entries it does have are still nodes,
--- so collect mode keeps walking them instead of dropping the whole subtree.
local function check_array(report, value, path)
  if type(value) ~= "table" then
    fail(report, path, "must be an array")
    return 0
  end
  local count, max = 0, 0
  for key in pairs(value) do
    if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
      fail(report, path, "has a non-array key " .. tostring(key))
    else
      count = count + 1
      if key > max then max = key end
    end
  end
  if count ~= max then
    fail(report, path, "is sparse (" .. count .. " entries, max index " .. max .. ")")
  end
  return max
end

--- Why a text value is unusable, or nil when it is fine.
local function text_problem(value)
  if type(value) ~= "string" then return "must be a string" end
  if utf8 and utf8.len and not utf8.len(value) then return "must be valid UTF-8" end
  if value:find("[%z\1-\31\127]") then return "contains a non-printable control character" end
  if not value:match("%S") then return "must not be empty or whitespace" end
  return nil
end

local function check_text(report, value, path)
  local problem = text_problem(value)
  if problem then return fail(report, path, problem) end
  return true
end

local function require_text(value, path)
  local problem = text_problem(value)
  if problem then error(path .. " " .. problem, 3) end
end

--- Why an id is unusable, or nil when it is fine. One rule, two renderers:
--- `check_id` reports into a walk, `string_id` raises for the canvas call
--- validators used directly by a view.
local function id_problem(value)
  if type(value) ~= "string" or value == "" then return "must be a non-empty string id" end
  if #value > 160 then return "id is too long" end
  return nil
end

local function check_id(report, value, path)
  local problem = id_problem(value)
  if problem then return fail(report, path, problem) end
  return true
end

local function string_id(value, path)
  local problem = id_problem(value)
  if problem then error(path .. " " .. problem, 3) end
end

--- Check one node's own fields.
---
--- Children are walked by `walk`, not here, so a problem in this node does not
--- hide an independent problem further down the tree.
local function check_node(node, path, state, report)
  if not check_id(report, node.id, path .. ".id") then return end
  if state.ids[node.id] then
    return fail(report, path, "duplicate node id " .. node.id)
  end
  state.ids[node.id] = true

  if not KINDS[node.kind] then
    return fail(report, path .. ".kind", "is invalid: " .. tostring(node.kind))
  end

  if node.layout ~= nil then
    if type(node.layout) ~= "table" then
      return fail(report, path .. ".layout", "must be a table")
    end
    if not check_number_table(report, node.layout, path .. ".layout", LAYOUT_NUMBERS) then return end
    if not check_edges(report, node.layout.padding, path .. ".layout.padding") then return end
  end

  if node.style ~= nil then
    if type(node.style) ~= "table" then
      return fail(report, path .. ".style", "must be a table")
    end
    if not check_number_table(report, node.style, path .. ".style", STYLE_NUMBERS) then return end
  end

  if node.kind == "text" then
    if not check_text(report, node.text, path .. ".text") then return end
    if node.style == nil then
      return fail(report, path .. ".style", "is required for text")
    end
    if node.style.size == nil then
      return fail(report, path .. ".style.size", "is required for text")
    end
  end

  if node.kind == "text_input" then
    if type(node.value) ~= "string" then
      return fail(report, path .. ".value", "must be a string")
    end
    if utf8 and utf8.len and not utf8.len(node.value) then
      return fail(report, path .. ".value", "must be valid UTF-8")
    end
    if node.value:find("%z") then
      return fail(report, path .. ".value", "contains NUL")
    end
    if node.multiline ~= nil and type(node.multiline) ~= "boolean" then
      return fail(report, path .. ".multiline", "must be a boolean")
    end
    if node.read_only ~= nil and type(node.read_only) ~= "boolean" then
      return fail(report, path .. ".read_only", "must be a boolean")
    end
    if node.style == nil then
      return fail(report, path .. ".style", "is required for text_input")
    end
    if node.style.size == nil then
      return fail(report, path .. ".style.size", "is required for text_input")
    end
  end

  if node.kind == "component" then
    if type(node.name) ~= "string" or node.name == "" then
      return fail(report, path .. ".name", "is required for component")
    end
  end
end

--- Reject functions and host objects on a node.
---
--- A node may carry presentation metadata. Booleans, numbers, strings and
--- nested plain tables are fine; anything with identity that the host cannot
--- serialize is not.
local function check_host_objects(node, path, report)
  for key, value in pairs(node) do
    local value_type = type(value)
    if value_type == "function" or value_type == "userdata" or value_type == "thread" then
      return fail(report, path .. "." .. tostring(key), "contains a " .. value_type)
    end
  end
end

local function walk_state()
  return { seen = {}, ids = {}, nodes = 0 }
end

local function walk(node, path, state, report, depth)
  if report.capped then return end
  if depth > MAX_DEPTH then return fail(report, path, "exceeds max depth") end
  if type(node) ~= "table" then
    return fail(report, path, "must be a table, got " .. type(node))
  end
  -- A cycle, or one table used twice, stops here rather than recursing: the
  -- ids below would be reported as duplicates of themselves and the walk would
  -- never finish.
  if state.seen[node] then return fail(report, path, "contains a cycle or reused table") end
  state.seen[node] = true
  state.nodes = state.nodes + 1
  if state.nodes > MAX_NODES then return fail(report, path, "exceeds node limit") end

  check_node(node, path, state, report)

  if node.children ~= nil then
    local max = check_array(report, node.children, path .. ".children")
    for index = 1, max do
      if node.children[index] ~= nil then
        walk(node.children[index], path .. ".children[" .. index .. "]", state, report, depth + 1)
      end
    end
  end

  check_host_objects(node, path, report)
end

local STRICT = { strict = true }

--- Validate a semantic tree. Raises on the first structural error.
---
--- This stays the compatibility surface: the host and the suite both rely on it
--- refusing a tree with one named sentence. `validate.errors` is the same walk
--- in collect mode.
function validate.tree(tree)
  if type(tree) ~= "table" then error("tree must be a table", 2) end
  walk(tree, "tree", walk_state(), STRICT, 0)
  return tree
end

--- Every problem in the tree, in walk order.
---
--- `validate.tree` stops at the first problem, which is the right answer while
--- reloading: a tree that cannot load is not worth painting, and the view would
--- only be half-built anyway. It is the wrong answer while fixing one, because
--- every run reveals exactly one mistake and the next is hidden behind it.
--- This walks the same checks and keeps going across subtrees, refusing to
--- recurse into a cycle and stopping at MAX_ERRORS.
---
--- Returns an ordered array of `{ path = ..., message = ... }` plus a boolean
--- that is true when the cap stopped the walk before the tree was exhausted.
function validate.errors(tree)
  local report = { strict = false, problems = {}, capped = false }
  if type(tree) ~= "table" then
    fail(report, "tree", "must be a table")
    return report.problems, report.capped
  end
  walk(tree, "tree", walk_state(), report, 0)
  return report.problems, report.capped
end

--- Render collected problems as the preflight's stderr text.
---
--- One problem reads exactly as `validate.tree` would have raised it, so the
--- familiar single-error output is unchanged. Several are one per line, each
--- with its path, because the point of collecting them is to fix them in one
--- pass.
function validate.report(problems, capped)
  local lines = {}
  if #problems > 1 then
    lines[#lines + 1] = string.format("%d problems in the UI tree:", #problems)
  end
  for _, problem in ipairs(problems) do
    lines[#lines + 1] = problem.path .. " " .. problem.message
  end
  if capped then
    lines[#lines + 1] = string.format("(stopped after %d problems)", MAX_ERRORS)
  end
  return table.concat(lines, "\n")
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
  require_text(args.text, "text.text")
  if type(args.ink) ~= "string" or args.ink == "" then
    error("text.ink must be a non-empty string", 2)
  end
  check_vec3(args.translation, "text.translation")
  check_vec3(args.scale, "text.scale")
  return args
end

return validate
