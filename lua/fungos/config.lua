-- fungos.config — profile resolution for Spore UI modules.
--
-- The profile is plain data. A host may load it from `~/.config/fungos/ui.lua`,
-- a repo, a package, or a Settings Spore. `fungos.config` only normalizes and
-- merges it; it never reads files and never grants authority.
--
-- Resolution order:
--   defaults < theme/base < global profile < per-app profile < session overrides
--
-- An app profile may contain:
--   density, spacing, theme, radius, surfaces
--   hide = { "rail.tags" }
--   order = { "rail.accounts", "rail.inboxes" }
--   slots = { ["toolbar.end"] = function(ctx) ... end }
--   experimental_patch = function(tree, ctx) ... end

local config = {}

local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for key, item in pairs(value) do out[key] = copy(item) end
  return out
end

local function merge(base, override)
  if type(override) ~= "table" then return base end
  for key, value in pairs(override) do
    if type(value) == "table" and type(base[key]) == "table" then
      merge(base[key], value)
    else
      base[key] = copy(value)
    end
  end
  return base
end

config.copy = copy
config.merge = merge

--- Return a safe default profile.
function config.defaults()
  return {
    schema_version = 1,
    density = "comfortable",
    spacing = { xs = 4, sm = 8, md = 16, lg = 28, xl = 44 },
    theme = {},
    surfaces = { panel = 0.36, selected = 0.16, raised = 0.82 },
    apps = {},
  }
end

--- Normalize a user profile without mutating the input.
function config.normalize(raw)
  raw = raw or {}
  local out = config.defaults()
  merge(out, raw)
  if type(out.apps) ~= "table" then out.apps = {} end
  return out
end

--- Resolve a global profile plus one app overlay.
function config.for_app(raw, app_id)
  local out = config.normalize(raw)
  local app = app_id and out.apps[app_id] or nil
  if type(app) == "table" then merge(out, app) end
  return out
end

--- Extract just the UI-facing subset of a resolved profile.
function config.view(raw, app_id)
  local profile = config.for_app(raw, app_id)
  return {
    schema_version = profile.schema_version,
    density = profile.density,
    spacing = profile.spacing,
    theme = profile.theme,
    radius = profile.radius,
    surfaces = profile.surfaces,
    hide = profile.hide or {},
    order = profile.order or {},
    slots = profile.slots or {},
    experimental_patch = profile.experimental_patch,
  }
end

--- Stable slot lookup independent of array/table shape.
function config.slot(profile, name)
  local slots = profile and profile.slots
  if type(slots) ~= "table" then return nil end
  return slots[name]
end

--- A declared hide list as a set.
function config.hidden(profile)
  local set = {}
  for _, name in ipairs((profile and profile.hide) or {}) do set[name] = true end
  return set
end

--- Return children ordered by `profile.order` where names match node ids.
--- Unlisted nodes keep their relative order after the listed ones.
function config.order_children(children, order)
  if type(order) ~= "table" or #order == 0 then return children end
  local rank, original = {}, {}
  for index, id in ipairs(order) do rank[id] = index end
  for index, child in ipairs(children) do original[child.id] = index end
  table.sort(children, function(a, b)
    local ra, rb = rank[a.id], rank[b.id]
    if ra and rb then return ra < rb end
    if ra then return true end
    if rb then return false end
    return (original[a.id] or 0) < (original[b.id] or 0)
  end)
  return children
end

return config
