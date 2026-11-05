-- fungos.ui — a small, declarative UI kit for Spore views.
--
-- A Spore UI is a pure projection:
--
--   snapshot + theme + viewport -> semantic tree -> host layout -> Canvas scene
--
-- The host measures text and resolves geometry. This module only describes
-- structure, styles, tokens, slots, and scene primitives. It never owns state
-- and never performs I/O.
--
-- The kit intentionally has no `require` dependency so a Spore package can be
-- composed into a single Canvas module by `tend` or a package builder.

local ui = {}

ui.version = "0.1.0"

local unpack = table.unpack or unpack

-- ---- small utilities ----------------------------------------------------

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

ui.copy = copy
ui.merge = merge

-- ---- profile / theme ----------------------------------------------------

ui.defaults = {
  density = "comfortable",
  spacing = { xs = 4, sm = 8, md = 16, lg = 28, xl = 44 },
  theme = {
    title = 28,
    large = 20,
    body = 16,
    small = 13,
    micro = 10,
    radius = 10,
  },
  surfaces = {
    panel = 0.36,
    selected = 0.16,
    raised = 0.82,
  },
}

-- The active profile is installed once per composed Spore UI module.
ui.profile = copy(ui.defaults)

--- Install a user/app profile. The profile is data, never authority.
function ui.configure(profile, app_id)
  ui.profile = copy(ui.defaults)
  merge(ui.profile, profile or {})
  if app_id and profile and type(profile.apps) == "table" and profile.apps[app_id] then
    merge(ui.profile, profile.apps[app_id])
  end
  return ui.profile
end

--- Resolve the host theme plus local overrides.
function ui.theme(base)
  local out = copy(base or {})
  merge(out, ui.profile.theme or {})
  if ui.profile.radius then out.radius = ui.profile.radius end
  return out
end

--- Current viewport, in logical pixels. Falls back to the authoring size.
function ui.viewport(fallback_w, fallback_h)
  local module = rawget(_G, "module")
  local vp = module and (module.viewport or (module.theme and module.theme.viewport))
  if vp and vp.width and vp.height and vp.width > 0 and vp.height > 0 then
    return vp.width, vp.height
  end
  return fallback_w or 1086, fallback_h or 1569
end

--- Host wall clock in Unix milliseconds, when the host provides one.
function ui.now_ms()
  local module = rawget(_G, "module")
  local now = module and module.now
  if type(now) == "table" and type(now.epoch_ms) == "number" then return now.epoch_ms end
  if type(now) == "number" then return now end
  return 0
end

--- Current module event, if the host routed an activation into this render.
function ui.event()
  local module = rawget(_G, "module")
  return module and module.event or nil
end

-- ---- tree nodes ---------------------------------------------------------

local function node(kind, id, layout, children)
  return {
    id = id,
    kind = kind,
    layout = layout or {},
    children = children or {},
  }
end

local function text_layout(opts, layout)
  layout = copy(layout or opts.layout or {})
  if opts.width ~= nil then layout.width = opts.width end
  if opts.height ~= nil then layout.height = opts.height end
  if opts.flex_grow ~= nil then layout.flex_grow = opts.flex_grow end
  if opts.flex_shrink ~= nil then layout.flex_shrink = opts.flex_shrink end
  if opts.padding ~= nil then layout.padding = opts.padding end
  if opts.align ~= nil then layout.align_items = opts.align end
  return layout
end

--- A text leaf. `opts`:
---   size, line_height, wrap, ink, width, height, flex_grow, layout
function ui.text(id, value, opts)
  opts = opts or {}
  local size = opts.size or (ui.profile.theme and ui.profile.theme.body) or 16
  local line_height = opts.line_height or (size + math.max(3, size * 0.22))
  local node_out = {
    id = id,
    kind = "text",
    text = tostring(value or ""),
    ink = opts.ink,
    style = {
      size = size,
      line_height = line_height,
      wrap = opts.wrap == true,
    },
    layout = text_layout(opts, opts.layout),
  }
  return node_out
end

--- Shorthand used by existing views: label(id, value, size, layout).
function ui.label(id, value, size, layout)
  return ui.text(id, value, { size = size, layout = layout })
end

function ui.container(id, layout, children)
  return node("container", id, layout, children)
end

function ui.column(id, layout, children)
  layout = copy(layout or {})
  layout.direction = "column"
  return node("container", id, layout, children)
end

function ui.row(id, layout, children)
  layout = copy(layout or {})
  layout.direction = "row"
  return node("container", id, layout, children)
end

function ui.rule(id, layout)
  return node("rule", id, layout)
end

function ui.spacer(id, layout)
  return node("spacer", id, layout)
end

--- A pressable control. The tree only carries the affordance and action id;
--- Canvas/Unibus decides whether the action is allowed.
function ui.button(id, label, opts)
  opts = opts or {}
  if type(id) == "table" then
    -- allow ui.button({ id = ..., label = ..., ... })
    opts = id
    id = opts.id
    label = opts.label
  end
  local height = opts.height or 34
  local size = opts.size or 12
  local layout = copy(opts.layout or {})
  layout.height = height
  layout.direction = "row"
  layout.align_items = "center"
  layout.justify_content = "center"
  layout.padding = layout.padding or { left = 12, right = 12 }
  layout.flex_shrink = 0
  if opts.flex_grow ~= nil then layout.flex_grow = opts.flex_grow end
  if opts.width ~= nil then
    layout.width = opts.width
  elseif not opts.flex_grow then
    local text_width
    if type(canvas) == "table" and type(canvas.measure_text) == "function" then
      local ok, measured = pcall(canvas.measure_text, tostring(label or ""), {
        size = size,
        line_height = size + 4,
        wrap = false,
      })
      if ok and type(measured) == "table" and type(measured.width) == "number" then
        text_width = measured.width
      end
    end
    layout.width = (text_width or (#tostring(label or "") * size * 0.62)) + 24
  end

  local child = ui.text(id .. "-label", label, {
    size = size,
    ink = opts.ink,
    flex_grow = opts.flex_grow and 1 or nil,
    layout = { flex_grow = opts.flex_grow and 1 or nil },
  })
  return {
    id = id,
    kind = "container",
    layout = layout,
    children = { child },
    action = opts.action,
    variant = opts.variant,
  }
end

--- A pressable app action with accessibility and safety metadata.
---
--- `opts.action` is an intent built with `fungos.action`. The host decides
--- whether it is allowed. `confirm`, `disabled_reason`, `shortcut`, `help` and
--- `pending` are presentation/policy hints, never authority.
function ui.action_button(id, label, opts)
  opts = opts or {}
  if type(id) == "table" then
    opts = id
    id = opts.id
    label = opts.label
  end
  local button = ui.button(id, label, {
    height = opts.height or 30,
    size = opts.size or 11,
    variant = opts.variant or (opts.danger and "danger" or nil),
    width = opts.width,
    flex_grow = opts.flex_grow,
    action = opts.action,
    layout = opts.layout,
    ink = opts.ink,
  })
  button.role = "button"
  button.label = tostring(label or "")
  button.description = opts.description
  button.shortcut = opts.shortcut
  button.confirm = opts.confirm == true
  button.danger = opts.danger == true
  button.pending = opts.pending == true
  button.disabled = opts.disabled == true
  button.disabled_reason = opts.disabled_reason
  button.checked = opts.checked
  button.help = opts.help
  button.priority = opts.priority
  button.needs_input = opts.needs_input == true
  button.input_schema = opts.input_schema
  button.source = opts.source
  button.a11y = {
    role = "button",
    label = tostring(label or ""),
    description = opts.description,
    shortcut = opts.shortcut,
    disabled = opts.disabled == true,
    disabled_reason = opts.disabled_reason,
    checked = opts.checked,
    pending = opts.pending == true,
  }
  return button
end

--- A top-level accessible action bar.
---
--- `actions` is a list of action-button specs, already-built nodes, separators
--- (`{ separator = true }`) or spacers (`{ spacer = true }`). The host owns
--- placement, focus order, overflow, shortcut dispatch and confirmation UI.
function ui.action_bar(id, actions, opts)
  opts = opts or {}
  local children = {}
  for index, action in ipairs(actions or {}) do
    if action and action.kind then
      ui.push(children, action)
    elseif action and action.separator then
      ui.push(children, ui.rule(id .. "-separator-" .. index, {
        width = 1,
        height = opts.separator_height or 18,
        margin = { left = 4, right = 4 },
      }))
    elseif action and action.spacer then
      ui.push(children, ui.spacer(id .. "-spacer-" .. index, { flex_grow = 1 }))
    elseif action then
      ui.push(children, ui.action_button(id .. "-" .. (action.id or index), action.label or "", action))
    end
  end
  local bar = ui.row(id, {
    height = opts.height or 36,
    gap = opts.gap or 6,
    padding = opts.padding or { left = 10, right = 10, top = 3, bottom = 3 },
    align_items = "center",
  }, children)
  bar.role = "toolbar"
  bar.label = opts.label or "Actions"
  bar.orientation = opts.orientation or "horizontal"
  bar.overflow = opts.overflow or "menu"
  bar.a11y = {
    role = "toolbar",
    label = bar.label,
    orientation = bar.orientation,
  }
  return bar
end

--- Build a top action bar from a host/granted action catalog.
---
--- Catalog actions use the Canvas/DCP shape:
---
---   { id, label, description, shortcut, input_schema, requires_input,
---     effect, idempotency, confirmation, available, reason, phases,
---     provider, catalog_revision, state_revision }
---
--- Parameterless actions become buttons. Actions with `requires_input` keep
--- their JSON Schema so the host can open a form; the UI still emits only an
--- intent.
function ui.action_bar_from_catalog(id, catalog, opts)
  opts = opts or {}
  local actions = {}
  for index, item in ipairs(catalog or {}) do
    local action_id = item.id or item.action
    if action_id then
      local confirmation = item.confirmation
      local blocked = item.available == false
      ui.push(actions, {
        id = action_id,
        label = item.label or item.title or action_id,
        description = item.description,
        shortcut = item.shortcut,
        input_schema = item.input_schema,
        needs_input = item.requires_input == true,
        confirm = confirmation == "required" or confirmation == "destructive",
        danger = confirmation == "destructive" or item.effect == "external",
        disabled = blocked,
        disabled_reason = item.reason,
        source = item.provider,
        action = item.action or { action = action_id, payload = item.payload or {} },
        priority = item.priority or index,
      })
      if item.separator_after then
        ui.push(actions, { separator = true })
      end
    end
  end
  local bar_opts = ui.copy(opts)
  bar_opts.label = bar_opts.label or "Actions"
  return ui.action_bar(id, actions, bar_opts)
end

--- A named extension point. Recipes may replace the fallback at this name.
function ui.slot(name, fallback)
  fallback = fallback or ui.container(name, {})
  fallback.slot = name
  return fallback
end

--- A named component supplied by a component/chrome/rice Spore.
--- The host or `tend` resolves it before layout. If it is unresolved, the
--- fallback is used and the missing component is reported.
function ui.component(name, props, children, fallback)
  return {
    id = props and props.id or name,
    kind = "component",
    name = name,
    props = props or {},
    children = children or {},
    fallback = fallback,
  }
end

--- Insert a node into a child list unless it is nil.
function ui.push(children, child)
  if child ~= nil then children[#children + 1] = child end
  return children
end


--- UTF-8-safe truncation. Canvas scene text must remain printable.
function ui.clip(value, limit)
  value = tostring(value or "")
  if limit <= 0 then return "" end
  local ok, length = pcall(utf8.len, value)
  if ok and length then
    if length <= limit then return value end
    local offset = utf8.offset(value, limit + 1)
    if offset then return value:sub(1, offset - 1) .. "…" end
  end
  if #value <= limit then return value end
  return value:sub(1, limit - 1) .. "…"
end

-- ---- common inbox/desktop components ------------------------------------

--- A compact status/classification pill.
function ui.badge(id, value, opts)
  opts = opts or {}
  return ui.row(id, {
    height = opts.height or 18,
    gap = 3,
    align_items = "center",
    padding = { left = 6, right = 6 },
  }, {
    ui.text(id .. "-text", value, {
      size = opts.size or 9,
      ink = opts.ink or "muted",
    }),
  })
end

--- A keyboard hint, visually quieter than a button.
function ui.kbd(id, value, opts)
  opts = opts or {}
  return ui.text(id, value, {
    size = opts.size or 10,
    ink = opts.ink or "muted",
    width = opts.width,
    height = opts.height or 18,
  })
end

--- A circular initials avatar. The view draws the circle; this is structure.
function ui.avatar(id, initials, opts)
  opts = opts or {}
  local size = opts.size or 34
  return ui.column(id, {
    width = size,
    height = size,
    align_items = "center",
    justify_content = "center",
    flex_shrink = 0,
  }, {
    ui.text(id .. "-text", initials or "?", {
      size = opts.text_size or math.max(10, size * 0.42),
      ink = opts.ink or "primary",
    }),
  })
end

--- A small all-caps section label.
function ui.section_label(id, value, opts)
  opts = opts or {}
  return ui.text(id, value, {
    size = opts.size or 9,
    height = opts.height or 16,
    ink = opts.ink or "muted",
  })
end

--- A centered empty state with a title and optional detail.
function ui.empty_state(id, title, detail, opts)
  opts = opts or {}
  local children = {
    ui.text(id .. "-title", title, {
      size = opts.title_size or 15,
      ink = opts.title_ink or "text",
      height = 22,
    }),
  }
  if detail and detail ~= "" then
    ui.push(children, ui.text(id .. "-detail", detail, {
      size = opts.detail_size or 11,
      ink = opts.detail_ink or "muted",
      wrap = true,
      height = opts.detail_height or 36,
    }))
  end
  return ui.column(id, {
    flex_grow = 1,
    gap = 4,
    align_items = "center",
    justify_content = "center",
    padding = { left = 24, right = 24 },
  }, children)
end

--- A row that reads as a selectable list item.
function ui.list_row(id, opts, children)
  opts = opts or {}
  local layout = {
    direction = "row",
    gap = opts.gap or 10,
    align_items = opts.align_items or "center",
    padding = opts.padding or { top = 8, right = 12, bottom = 8, left = 12 },
  }
  if opts.auto_height then
    layout.min_height = opts.min_height or opts.height or 62
  else
    layout.height = opts.height or 62
    if opts.min_height then layout.min_height = opts.min_height end
  end
  if opts.width then layout.width = opts.width end
  if opts.flex_grow ~= nil then layout.flex_grow = opts.flex_grow end
  return {
    id = id,
    kind = "container",
    layout = layout,
    selected = opts.selected == true,
    unread = opts.unread == true,
    disabled = opts.disabled == true,
    children = children or {},
    action = opts.action,
  }
end

--- A command/search bar. The host wires text input; this is the surface.
function ui.command_bar(id, opts)
  opts = opts or {}
  local query = opts.query
  if query == nil or query == "" then query = opts.placeholder or "Search" end
  local children = {
    ui.text(id .. "-icon", opts.icon or "⌕", { size = 13, ink = "muted", width = 18 }),
    ui.text(id .. "-query", query, {
      size = opts.size or 12,
      ink = (opts.query and opts.query ~= "") and "text" or "muted",
      flex_grow = 1,
    }),
  }
  if opts.hint then
    ui.push(children, ui.kbd(id .. "-hint", opts.hint, { size = 10 }))
  end
  return ui.row(id, {
    height = opts.height or 40,
    gap = 8,
    align_items = "center",
    padding = { left = 12, right = 12 },
  }, children)
end

-- ---- workspace / pane / tab components ----------------------------------

--- Mark a node as focusable and optionally focused. Painting decides how the
--- focus ring looks; the tree only carries the semantic state.
function ui.focusable(node, focused)
  node.focusable = true
  node.focused = focused == true
  return node
end

--- A workspace root. Pane geometry remains host-owned; this is the content box.
function ui.workspace(id, opts, children)
  opts = opts or {}
  return ui.column(id, {
    width = opts.width,
    height = opts.height,
    flex_grow = opts.flex_grow,
    gap = opts.gap or 0,
    padding = opts.padding or { top = 0, right = 0, bottom = 0, left = 0 },
  }, children)
end

--- A pane content box. `opts.focused` is presentation metadata, not authority.
function ui.pane(id, opts, children)
  opts = opts or {}
  local layout = {
    flex_grow = opts.flex_grow == nil and 1 or opts.flex_grow,
    flex_shrink = opts.flex_shrink == nil and 1 or opts.flex_shrink,
    min_width = opts.min_width,
    width = opts.width,
    gap = opts.gap or 0,
    padding = opts.padding,
  }
  local pane = ui.column(id, layout, children)
  pane.pane = opts.pane_id or id
  pane.focused = opts.focused == true
  return pane
end

--- One tab. Selected/unread are semantic flags; the view paints them.
function ui.tab(id, label, opts)
  opts = opts or {}
  local children = {
    ui.text(id .. "-label", label, {
      size = opts.size or 11,
      ink = opts.selected and "primary" or (opts.unread and "text" or "muted"),
      flex_grow = 1,
    }),
  }
  if opts.badge then
    children[#children + 1] = ui.badge(id .. "-badge", tostring(opts.badge), {
      size = opts.badge_size or 9,
      ink = opts.selected and "primary" or "muted",
    })
  elseif opts.unread then
    children[#children + 1] = ui.text(id .. "-unread", tostring(opts.unread), {
      size = opts.badge_size or 9,
      ink = opts.selected and "primary" or "muted",
      width = 24,
    })
  end
  return ui.list_row(id, {
    height = opts.height or 30,
    padding = opts.padding or { left = 8, right = 8 },
    selected = opts.selected,
    unread = opts.unread,
    action = opts.action,
  }, children)
end

--- Horizontal tabs for a pane. `tabs` is `{ {id,label,unread,selected,action} }`.
function ui.tabbar(id, tabs, opts)
  opts = opts or {}
  local children = {}
  for index, tab in ipairs(tabs or {}) do
    children[#children + 1] = ui.tab(id .. "-" .. (tab.id or index), tab.label or "Tab", {
      selected = tab.selected,
      unread = tab.unread,
      badge = tab.badge,
      action = tab.action,
      height = opts.height,
      size = opts.size,
      padding = opts.padding,
    })
  end
  return ui.row(id, {
    height = opts.height or 32,
    gap = opts.gap or 2,
    padding = opts.padding or { left = 0, right = 0 },
  }, children)
end

--- A sidebar content box.
function ui.sidebar(id, opts, children)
  opts = opts or {}
  return ui.column(id, {
    width = opts.width,
    flex_shrink = opts.flex_shrink == nil and 0 or opts.flex_shrink,
    gap = opts.gap or 1,
    padding = opts.padding or { top = 12, right = 10, bottom = 12, left = 12 },
  }, children)
end

--- One named sidebar group. Items are `{ id,label,count,selected,action }`.
function ui.sidebar_group(id, label, items, opts)
  opts = opts or {}
  local children = { ui.section_label(id .. "-label", label, { ink = opts.label_ink }) }
  for index, item in ipairs(items or {}) do
    local row_children = {
      ui.text(id .. "-" .. (item.id or index) .. "-label", item.label or item.id or "", {
        size = opts.size or 10,
        ink = item.selected and "primary" or (opts.ink or "muted"),
        flex_grow = 1,
      }),
    }
    if item.count ~= nil then
      row_children[#row_children + 1] = ui.text(id .. "-" .. (item.id or index) .. "-count", tostring(item.count), {
        size = opts.count_size or 10,
        ink = item.selected and "primary" or "muted",
        width = opts.count_width or 28,
      })
    end
    children[#children + 1] = ui.list_row(id .. "-" .. (item.id or index), {
      height = opts.height or 26,
      padding = opts.padding or { left = 8, right = 8 },
      selected = item.selected,
      action = item.action,
    }, row_children)
  end
  return ui.column(id, { gap = opts.gap or 1 }, children)
end

--- A command palette panel. The host owns focus, filtering, and selection.
function ui.command_palette(id, opts, children)
  opts = opts or {}
  return ui.column(id, {
    width = opts.width or 520,
    height = opts.height,
    gap = opts.gap or 4,
    padding = opts.padding or { top = 10, right = 10, bottom = 10, left = 10 },
  }, children)
end

--- One command row.
function ui.command_item(id, label, opts)
  opts = opts or {}
  return ui.list_row(id, {
    height = opts.height or 30,
    padding = { left = 8, right = 8 },
    selected = opts.selected,
    action = opts.action,
  }, {
    ui.text(id .. "-label", label, {
      size = opts.size or 11,
      ink = opts.selected and "primary" or "text",
      flex_grow = 1,
    }),
    ui.kbd(id .. "-keys", opts.keys or "", { size = 9, width = opts.keys_width or 44 }),
  })
end

--- A focus ring descriptor. The view paints it.
function ui.focus_ring(node)
  node.focus_ring = true
  return node
end

--- A label/keys pair for shortcut sheets and empty states.
function ui.shortcut(id, label, keys, opts)
  opts = opts or {}
  return ui.row(id, {
    height = opts.height or 24,
    gap = 8,
    align_items = "center",
  }, {
    ui.text(id .. "-label", label, { size = opts.size or 11, ink = "text", flex_grow = 1 }),
    ui.kbd(id .. "-keys", keys, { size = opts.size or 10 }),
  })
end

-- ---- actions ------------------------------------------------------------

--- An action intent. The Spore/Unibus router owns semantics.
function ui.action(id, payload)
  return { action = id, payload = payload }
end

-- ---- layout + scene -----------------------------------------------------

--- Resolve the tree with host Taffy. The host must expose `canvas.layout`.
function ui.layout(tree, width, height)
  return canvas.layout(tree, width, height)
end

--- Index laid-out nodes by id.
function ui.index(laid)
  local by_id = {}
  for _, item in ipairs((laid and laid.nodes) or {}) do
    if item.id then by_id[item.id] = item end
  end
  return by_id
end

function ui.find(laid, id)
  for _, item in ipairs((laid and laid.nodes) or {}) do
    if item.id == id then return item end
  end
end

--- A tiny scene surface in logical pixels.
---
--- Surface coordinates are top-left origin. It converts to Canvas's normalized
--- space, so views never hand-write the -4..4 math.
function ui.surface(width, height, theme)
  local surface = {
    width = width,
    height = height,
    theme = theme or ui.theme(),
    z = 0,
  }

  local base = surface.theme.body or 16

  function surface:nx(px) return -4 + 8 * px / self.width end
  function surface:ny(px) return 4 - 8 * px / self.height end
  function surface:sw(px) return 8 * px / self.width end
  function surface:sh(px) return 8 * px / self.height end
  function surface:ts(px) return px / (base * 1.25) end

  function surface:rect(id, x, y, w, h, ink, opacity, radius, z)
    canvas.rect {
      id = id,
      ink = ink or "surface",
      opacity = opacity == nil and 1.0 or opacity,
      radius = radius or 0,
      translation = { self:nx(x), self:ny(y), z or self.z },
      scale = { self:sw(math.max(1, w)), self:sh(math.max(1, h)), 1 },
    }
  end

  function surface:text(id, value, x, y, size, ink, z)
    canvas.text {
      id = id,
      text = tostring(value or ""),
      ink = ink or "text",
      translation = { self:nx(x), self:ny(y), z or (self.z + 0.1) },
      scale = { self:ts(size), self:ts(size), 1 },
    }
  end

  function surface:find(laid, id)
    return ui.find(laid, id)
  end

  function surface:hit(id, rect, label)
    -- Hit targets outside the surface are a layout/overflow bug. Never emit
    -- geometry the host will reject; the caller can still draw clipped content.
    if rect.width <= 0 or rect.height <= 0
      or rect.x < -0.5 or rect.y < -0.5
      or rect.x + rect.width > self.width + 0.5
      or rect.y + rect.height > self.height + 0.5 then
      return false
    end
    widget.hit {
      id = id,
      label = label or "hit",
      x = self:nx(rect.x),
      y = self:ny(rect.y),
      width = self:sw(rect.width),
      height = self:sh(rect.height),
    }
    return true
  end

  function surface:background(ink)
    self:rect("surface-bg", 0, 0, self.width, self.height, ink or "background", 1.0, 0, -1)
  end

  return surface
end

--- Draw laid-out text nodes with a default ink policy.
function ui.paint_text(surface, laid, ink_for)
  for _, item in ipairs((laid and laid.nodes) or {}) do
    if item.kind == "text" and item.style then
      local ink = (ink_for and ink_for(item)) or item.ink or "text"
      surface:text(item.id, item.text, item.rect.x, item.rect.y, item.style.size, ink)
    end
  end
end

--- Draw laid-out rules.
function ui.paint_rules(surface, laid, ink, opacity)
  for _, item in ipairs((laid and laid.nodes) or {}) do
    if item.kind == "rule" then
      local r = item.rect
      surface:rect(item.id .. "-line", r.x, r.y, r.width, math.max(1, r.height), ink or "muted", opacity or 0.25, 0)
    end
  end
end

return ui
