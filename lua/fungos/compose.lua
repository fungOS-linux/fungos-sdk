-- fungos.compose — compose Spore UI contributions into one view.
--
-- A Spore does not have to be an app. It may contribute any of:
--
--   components   named UI components
--   slots        named replacements/extensions
--   theme        tokens and ricing
--   chrome       named window/app-shell components
--   view         a complete app view
--
-- Resolution order for a component or slot is registration order. Higher
-- priority Spores (system > package > user rice) are registered later.
--
-- Composition is presentation-only. Every contribution runs in the same
-- no-authority UI sandbox.

local compose = {}

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

compose.copy = copy
compose.merge = merge

--- A registry of UI contributions.
function compose.registry()
  local registry = {
    components = {},
    slots = {},
    theme = {},
    sources = {},
  }

  --- Register one contribution module.
  --- `source` is only used for diagnostics.
  function registry:add(module, source)
    if type(module) ~= "table" then return self end
    source = source or module.name or "anonymous"

    for name, fn in pairs(module.components or {}) do
      if type(fn) == "function" then
        self.components[name] = { fn = fn, source = source }
      end
    end

    for name, fn in pairs(module.slots or {}) do
      if type(fn) == "function" then
        self.slots[name] = { fn = fn, source = source }
      end
    end

    for name, fn in pairs(module.chrome or {}) do
      if type(fn) == "function" then
        self.components["chrome." .. name] = { fn = fn, source = source }
      end
    end

    if type(module.theme) == "table" then
      merge(self.theme, module.theme)
    end

    self.sources[#self.sources + 1] = source
    return self
  end

  function registry:component(name)
    local entry = self.components[name]
    return entry and entry.fn or nil, entry and entry.source or nil
  end

  function registry:slot(name)
    local entry = self.slots[name]
    return entry and entry.fn or nil, entry and entry.source or nil
  end

  function registry:resolve_theme(base)
    local out = copy(base or {})
    merge(out, self.theme)
    return out
  end

  return registry
end

-- ---- tree walking -------------------------------------------------------

local function walk(node, visit)
  if type(node) ~= "table" then return node end
  node = visit(node) or node
  if type(node.children) == "table" then
    for index, child in ipairs(node.children) do
      node.children[index] = walk(child, visit)
    end
  end
  return node
end

--- Replace `ui.component(name, ...)` nodes with registered components.
function compose.resolve_components(tree, registry, ctx, on_missing)
  return walk(tree, function(node)
    if node.kind ~= "component" then return node end
    local fn, source = registry:component(node.name)
    if fn then
      local rendered = fn(ctx, node.props or {}, node.children or {})
      if type(rendered) == "table" then return rendered end
    end
    if on_missing then on_missing(node.name, source) end
    if node.fallback then return node.fallback end
    return {
      id = node.id or node.name,
      kind = "container",
      layout = {},
      children = {},
      missing_component = node.name,
    }
  end)
end

--- Replace `ui.slot(name)` nodes with the highest-priority registered slot.
function compose.resolve_slots(tree, registry, ctx)
  return walk(tree, function(node)
    if not node.slot then return node end
    local fn = registry:slot(node.slot)
    if not fn then return node end
    local rendered = fn(ctx, node)
    if type(rendered) == "table" then return rendered end
    return node
  end)
end

--- Resolve components first, then slots. Slots may themselves contain
--- components, so one extra component pass keeps the result fully resolved.
function compose.apply(tree, registry, ctx, on_missing)
  tree = compose.resolve_components(tree, registry, ctx, on_missing)
  tree = compose.resolve_slots(tree, registry, ctx)
  tree = compose.resolve_components(tree, registry, ctx, on_missing)
  return tree
end

--- Collect the names a view depends on. Useful for `tend doctor`.
function compose.dependencies(tree, into)
  into = into or { components = {}, slots = {} }
  walk(tree, function(node)
    if node.kind == "component" and node.name then
      into.components[node.name] = true
    end
    if node.slot then into.slots[node.slot] = true end
    return node
  end)
  return into
end

return compose
