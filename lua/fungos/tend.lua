-- fungos.tend — pure helpers shared by the tend CLI and its tests.
--
-- Nothing here touches the filesystem or spawns a process, so tests can drive
-- it directly. tools/tend.lua keeps the I/O: file reads, canvasctl, Canvas
-- reloads. Extracting this surface is what makes the development loop testable
-- at all; a preflight with no tests is just a second opinion.

local tend = {}

--- The Lua API is part of the package ABI, so every Spore UI documents these
--- sections in ui/API.md. Keep this list in step with docs/lua-api-contract.md.
tend.api_sections = {
  "entrypoint",
  "snapshot",
  "actions",
  "slots",
  "components",
  "theme/config",
  "stable ids",
  "authority",
}

tend.commands = {
  ["check"] = true,
  ["doctor"] = true,
  ["preview"] = true,
  ["build"] = true,
  ["list"] = true,
  ["api-check"] = true,
  ["watch"] = true,
}

--- Parse argv into an options table.
---
--- `defaults` is copied, never mutated: callers routinely reuse one defaults
--- table across invocations, and a parse that wrote back into it would leak
--- flags between runs.
function tend.parse(argv, defaults)
  defaults = defaults or {}

  local options = {}
  for key, value in pairs(defaults) do
    if key ~= "components" then options[key] = value end
  end
  options.components = {}
  for _, path in ipairs(defaults.components or {}) do
    options.components[#options.components + 1] = path
  end

  local positional = {}
  local index = 1
  while index <= #argv do
    local arg = argv[index]
    if arg == "--doctor" then
      options.doctor = true
    elseif arg == "--no-reload" then
      options.reload = false
    elseif arg == "--no-preflight" then
      options.preflight = false
    elseif arg == "--allow-undocumented" then
      options.check_api = false
    elseif arg == "--no-workspace" then
      options.no_workspace = true
    elseif arg == "--strict-baseline" then
      options.strict_baseline = true
    elseif arg == "--workspace" then
      index = index + 1
      options.workspace = assert(argv[index], "--workspace requires a path")
    elseif arg == "--root" then
      index = index + 1
      options.roots = options.roots or {}
      options.roots[#options.roots + 1] = assert(argv[index], "--root requires a path")
    elseif arg == "--component" then
      index = index + 1
      options.components[#options.components + 1] = assert(argv[index], "--component requires a path")
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

--- Length of a long-bracket opener at `at`, plus its equals count, or nil.
--- `[[` is level 0, `[==[` is level 2.
local function long_bracket(source, at)
  local equals = source:match("^%[(=*)%[", at)
  if equals == nil then return nil end
  return #equals + 2, #equals
end

local function long_close(equals)
  return "]" .. string.rep("=", equals) .. "]"
end

--- Strip comments and blank lines from Lua source.
---
--- Respects single-quoted, double-quoted and long-bracket strings: a `--`
--- inside `[[...]]` is text, not a comment. The composed module is loaded by
--- Canvas, so mangling a long string here would ship a silently-wrong view.
function tend.strip_comments(source)
  local out = {}
  local index, length = 1, #source
  local quote

  local function push(text) out[#out + 1] = text end

  while index <= length do
    local char = source:sub(index, index)

    if quote then
      push(char)
      if char == "\\" then
        index = index + 1
        push(source:sub(index, index))
      elseif char == quote then
        quote = nil
      end
      index = index + 1
    elseif char == '"' or char == "'" then
      quote = char
      push(char)
      index = index + 1
    elseif char == "-" and source:sub(index + 1, index + 1) == "-" then
      local open, equals = long_bracket(source, index + 2)
      if open then
        local close = long_close(equals)
        local at = source:find(close, index + 2 + open, true)
        index = at and (at + #close) or (length + 1)
      else
        while index <= length and source:sub(index, index) ~= "\n" do index = index + 1 end
      end
    elseif char == "[" then
      local open, equals = long_bracket(source, index)
      if open then
        local close = long_close(equals)
        local at = source:find(close, index + open, true)
        local stop = at and (at + #close - 1) or length
        push(source:sub(index, stop))
        index = stop + 1
      else
        push(char)
        index = index + 1
      end
    else
      push(char)
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

--- Which documented sections are absent from an API.md body.
---
--- Headings are matched case-insensitively as substrings, so `## Theme/config`
--- satisfies `theme/config`. Returns names in canonical order, so the CLI
--- prints the same list for the same input.
function tend.missing_sections(text)
  local headings = {}
  for heading in (text or ""):gmatch("## ([^\n]+)") do
    headings[#headings + 1] = heading:lower()
  end

  local missing = {}
  for _, section in ipairs(tend.api_sections) do
    local found = false
    for _, heading in ipairs(headings) do
      if heading:find(section, 1, true) then found = true break end
    end
    if not found then missing[#missing + 1] = section end
  end
  return missing
end

--- A `## Actions` heading. Matched case-insensitively, and a longer title such
--- as `## Actions emitted` still counts; `## Interactions` does not.
local function is_actions_heading(heading)
  local name = heading:lower()
  return name == "actions" or name:match("^actions%s") ~= nil
end

--- Action ids documented under a `## Actions` heading.
---
--- The convention: `## Actions` holds a fenced ```text block listing action ids,
--- one per line (see docs/lua-api-contract.md). Only that section's ```text
--- blocks count. The table and prose beside them are for humans, and a ```lua
--- example in another section is not a list of ids.
---
--- Blank lines are skipped, duplicates dropped, file order kept. A file with no
--- `## Actions` section returns an empty list: most API.md files predate this
--- convention, so "not documented this way" has to mean "nothing to check"
--- rather than "this Spore has no actions".
function tend.documented_actions(text)
  local ids, seen = {}, {}
  local in_actions = false
  local fence = nil

  for raw in (text or ""):gmatch("([^\n]*)\n?") do
    local line = raw:gsub("\r$", "")
    -- An opening fence carries an info string; a closing fence is bare. Both
    -- match here, and the state decides which one this is.
    local fence_info = line:match("^%s*```%s*(%S*)%s*$")
    if fence then
      if fence_info == "" then
        fence = nil
      elseif in_actions and fence == "text" then
        local id = line:gsub("^%s+", ""):gsub("%s+$", "")
        if id ~= "" and not seen[id] then
          seen[id] = true
          ids[#ids + 1] = id
        end
      end
    elseif fence_info ~= nil then
      fence = fence_info:lower()
    else
      -- A `##` line inside a fence is text, not a heading: the fence branch
      -- above consumes it, and this branch only runs outside one.
      local heading = line:match("^##%s+(.-)%s*$")
      if heading then in_actions = is_actions_heading(heading) end
    end
  end
  return ids
end

--- Call forms that emit an action id.
---
--- `action.call` is the documented alias of `action.intent`; `ui.action_intent`
--- is accepted because views have used both spellings.
local EMIT_CALLS = { "action%.intent", "action%.call", "ui%.action_intent" }

--- Action ids a view source appears to emit.
---
--- Deliberately static and approximate. It matches only a literal first
--- argument of a known emit call: an id assembled at runtime
--- (`action.intent("mail." .. verb)`) is invisible to it, and a call spelled the
--- same way inside a long string would be a false positive. Comments are
--- stripped first, so a commented-out intent does not count. This is enough to
--- catch the mistake it exists for — the view emits an action nobody documented
--- — and it is not a substitute for running the view.
function tend.emitted_actions(source)
  local text = tend.strip_comments(source or "")
  local found = {}
  for _, call in ipairs(EMIT_CALLS) do
    local pattern = call .. "%s*%(%s*([\"'])([^\"'\n]*)"
    local at = 1
    while true do
      local start, _, _, id = text:find(pattern, at)
      if not start then break end
      if id ~= "" then found[#found + 1] = { at = start, id = id } end
      at = start + 1
    end
  end
  -- One pass per call form loses the interleaving, so order by match position
  -- to keep "first seen" meaning first seen.
  table.sort(found, function(a, b) return a.at < b.at end)
  local ids, seen = {}, {}
  for _, item in ipairs(found) do
    if not seen[item.id] then
      seen[item.id] = true
      ids[#ids + 1] = item.id
    end
  end
  return ids
end

--- Compare documented action ids with the ones a view emits.
---
--- `undocumented` is a failure: the view emits an action the Spore API does not
--- describe, so no consumer can know it exists. `unused` is only a warning: a
--- Spore may document an action it wires conditionally. Both lists are sorted so
--- the same input prints the same order.
function tend.action_gaps(documented, emitted)
  local documented_set, emitted_set = {}, {}
  for _, id in ipairs(documented or {}) do documented_set[id] = true end
  for _, id in ipairs(emitted or {}) do emitted_set[id] = true end
  local undocumented, unused = {}, {}
  for id in pairs(emitted_set) do
    if not documented_set[id] then undocumented[#undocumented + 1] = id end
  end
  for id in pairs(documented_set) do
    if not emitted_set[id] then unused[#unused + 1] = id end
  end
  table.sort(undocumented)
  table.sort(unused)
  return { undocumented = undocumented, unused = unused }
end

--- The `[ui] entry` path from a spore.toml body, or nil.
---
--- This is not a TOML parser. It reads the one string `tend api-check` needs,
--- and only from the `[ui]` table, so an `entry` under `[module]` or at the top
--- level is not mistaken for the view.
function tend.ui_entry(text)
  local section
  for raw in (text or ""):gmatch("([^\n]*)\n?") do
    local line = raw:gsub("\r$", "")
    local heading = line:match("^%s*%[([^%]]+)%]%s*$")
    if heading then
      section = heading:gsub("^%s+", ""):gsub("%s+$", "")
    elseif section == "ui" then
      local entry = line:match('^%s*entry%s*=%s*"([^"]+)"')
        or line:match("^%s*entry%s*=%s*'([^']+)'")
      if entry then return entry end
    end
  end
  return nil
end

--- Parse a baseline file body into a set of tolerated paths.
---
--- Blank lines and `#` comments are ignored. Entries are trimmed but otherwise
--- taken verbatim: they are filesystem paths, not identifiers.
function tend.baseline_entries(text)
  local known = {}
  for line in (text or ""):gmatch("[^\n]+") do
    local entry = line:gsub("^%s+", ""):gsub("%s+$", "")
    if entry ~= "" and entry:sub(1, 1) ~= "#" then known[entry] = true end
  end
  return known
end

return tend
