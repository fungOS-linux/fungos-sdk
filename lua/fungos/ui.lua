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

--- Split a semantic ink or a `{ink=..., rgb={r,g,b}}` colour.
-- Scene surfaces can carry raw RGB; the Canvas fallback keeps the semantic ink.
local function color_parts(value, fallback)
  if type(value) == "table" then
    local ink = value.ink or fallback
    local rgb = value.rgb
    if not rgb and type(value[1]) == "number" then
      rgb = { value[1], value[2], value[3] }
    end
    if type(rgb) == "table" and type(rgb[1]) == "number" then
      return ink, {
        math.max(0, math.min(255, math.floor(rgb[1]))),
        math.max(0, math.min(255, math.floor(rgb[2] or 0))),
        math.max(0, math.min(255, math.floor(rgb[3] or 0))),
      }
    end
    return ink, nil
  end
  return value or fallback, nil
end

local function measure_text(value, size)
  value, size = tostring(value or ""), tonumber(size) or 10
  return { width = #value * size * 0.58, height = size * 1.3 }
end

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
--- Only the keys a caller installed, so `ui.theme` can tell a choice from a default.
ui.overrides = {}

--- When set, `ui.surface` returns a recording surface instead of calling the
--- Canvas draw ABI. A GPU/replay host installs this around a view's render.
ui.backend = nil

--- Install a user/app profile. The profile is data, never authority.
function ui.configure(profile, app_id)
  ui.profile = copy(ui.defaults)
  merge(ui.profile, profile or {})
  -- What the caller asked for, kept apart from what `defaults` merely supplies.
  -- `ui.theme` needs the distinction: a default body size is not an instruction
  -- to draw at it, and letting it win over the host's theme is how a view ends up
  -- measuring at 16 and drawing at 24.
  ui.overrides = {}
  if profile then merge(ui.overrides, profile) end
  if app_id and profile and type(profile.apps) == "table" and profile.apps[app_id] then
    merge(ui.overrides, profile.apps[app_id])
    merge(ui.profile, profile.apps[app_id])
  end
  return ui.profile
end

--- Resolve the host theme plus local overrides.
---
--- The host's own theme is the base, the same way `ui.viewport` reads
--- `module.viewport`: a host that hands the module a theme is telling it the scale
--- it will draw at. A surface normalised against a different body size draws text
--- at a size the view never measured — 1.5x too large on a 1.5x theme, which
--- overflows the column the view wrapped for.
function ui.theme(base)
  local module = rawget(_G, "module")
  -- Defaults, then the host's theme, then the caller's own choices. A default is
  -- not an instruction: letting one win over the host is how a view measures at
  -- 16 and draws at 24, which overflows the column it wrapped for.
  local out = copy(ui.defaults.theme)
  merge(out, base or (module and module.theme) or {})
  local overrides = ui.overrides or {}
  merge(out, overrides.theme or {})
  if overrides.radius then out.radius = overrides.radius end
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

--- A column that carries a fill, so `ui.paint_tree` can draw it.
---
--- The kit has no notion of "this region is a card": a container is geometry and
--- nothing else. A fill is a presentation fact, so it lives in `style`, beside the
--- size and ink a text node already keeps there.
function ui.panel(id, layout, children, opts)
  return ui.filled(ui.column(id, layout, children), opts)
end

--- Give a node a fill. Any container can be a card; this is how a view says so,
--- instead of the kit having to guess which containers are panels.
---
--- The fill is presentation metadata in `style`, the same place a text node keeps
--- its size and ink, so `ui.paint_tree` can read it and a host that paints its own
--- way can ignore it.
function ui.filled(node, opts)
  opts = opts or {}
  node.style = node.style or {}
  node.style.fill = opts.fill or "surface"
  node.style.opacity = opts.opacity == nil and 0.36 or opts.opacity
  node.style.radius = opts.radius == nil and 8 or opts.radius
  return node
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

--- An editable text field. The host owns the edit buffer, selection, IME and
--- commit timing; the tree only names the initial value and the intent that
--- will save it. `multiline` selects the editor presentation.
---
---   ui.text_input("note-editor", snapshot.editor.text, {
---     multiline = true,
---     expected_version = snapshot.editor.expected_version,
---     action = action.intent("notes.save", { path = snapshot.selected }),
---   })
function ui.text_input(id, value, opts)
  opts = opts or {}
  local multiline = opts.multiline == true
  local layout = copy(opts.layout or {})
  if opts.width ~= nil then layout.width = opts.width end
  layout.height = opts.height or (multiline and 240 or 34)
  if opts.flex_grow ~= nil then layout.flex_grow = opts.flex_grow end
  if opts.flex_shrink ~= nil then layout.flex_shrink = opts.flex_shrink end
  layout.direction = multiline and "column" or "row"
  layout.align_items = multiline and "stretch" or "center"
  layout.padding = opts.padding or { left = 10, right = 10, top = 6, bottom = 6 }
  return {
    id = id,
    kind = "text_input",
    value = tostring(value or ""),
    placeholder = opts.placeholder and tostring(opts.placeholder) or nil,
    multiline = multiline,
    read_only = opts.read_only == true,
    action = opts.action,
    expected_version = opts.expected_version,
    role = "textbox",
    a11y = {
      role = multiline and "multiline_textbox" or "textbox",
      label = opts.label or "Text",
      value = tostring(value or ""),
      multiline = multiline,
      read_only = opts.read_only == true,
      description = opts.description,
    },
    style = {
      size = opts.size or (ui.profile.theme and ui.profile.theme.body) or 16,
      line_height = opts.line_height,
      wrap = multiline,
    },
    layout = layout,
  }
end

--- A multiline text editor. Shorthand for `ui.text_input(..., multiline = true)`.
function ui.editor(id, value, opts)
  opts = copy(opts or {})
  opts.multiline = true
  return ui.text_input(id, value, opts)
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
--- Install the host/tend component resolver. Called immediately before layout
--- so `ui.component(...)` and `ui.slot(...)` become real nodes. The resolver is
--- presentation-only and is not available as authority to a Spore.
ui._component_resolver = nil
function ui.set_component_resolver(resolver)
  ui._component_resolver = resolver
end

--- Pure-Lua layout for a `fungos.ui` tree, when the host has no layout service.
---
--- A Canvas host exposes `canvas.layout` (Taffy) and `ui.layout` prefers it. Every
--- other host — `tools/shot.lua`, `chrome-host`, a test fixture, a scene recorder
--- — records primitives and offers no layout, and a view that hands such a host a
--- tree arrives somewhere that cannot lay it out: the snapshot is fine and the
--- scene is empty. This is the fallback that closes that gap, so a view is written
--- once and paints the same geometry everywhere.
---
--- It honours the hints the views actually declare: direction, gap, padding,
--- fixed sizes and flex_grow. It is deliberately not a stub — a stubbed layout
--- (every child 20px tall, no gap) draws a scene of the right size and the wrong
--- picture, which is harder to notice than a failure.
---
--- The shape matches the host's: `{ root = <rect>, nodes = <flat list> }`, where
--- every listed node is the original node carrying a pixel `rect`, so a painter
--- can still read `kind`, `text`, `style` and `action` from it.
local function layout_padding(node)
  local padding = node.layout and node.layout.padding
  local top, right, bottom, left = 0, 0, 0, 0
  -- A number is uniform padding. Views write `padding = 16` far more often than
  -- the table form, and silently treating it as zero is how a panel ends up with
  -- its text welded to its border.
  if type(padding) == "number" then
    return padding, padding, padding, padding
  end
  if type(padding) == "table" then
    top = padding.top or 0
    right = padding.right or 0
    bottom = padding.bottom or 0
    left = padding.left or 0
  end
  return top, right, bottom, left
end

local function layout_fixed(node, direction)
  local spec = node.layout or {}
  local value = direction == "row" and spec.width or spec.height
  return type(value) == "number" and value or nil
end

local function layout_default(node)
  if node.kind == "text" then
    local size = node.style and node.style.size
    return type(size) == "number" and (size + 4) or 20
  end
  if node.kind == "rule" then return 2 end
  if node.kind == "spacer" then return 8 end
  return nil
end

local function layout_assign(node, x, y, width, height, out)
  node.rect = { x = x, y = y, width = width, height = height }
  out[#out + 1] = node

  local children = node.children
  if type(children) ~= "table" or #children == 0 then return end

  local spec = node.layout or {}
  local direction = spec.direction or "column"
  local gap = spec.gap or 0
  local pad_top, pad_right, pad_bottom, pad_left = layout_padding(node)
  local content_x, content_y = x + pad_left, y + pad_top
  local content_w = width - pad_left - pad_right
  local content_h = height - pad_top - pad_bottom

  local count = #children
  local total = direction == "row" and content_w or content_h
  local gaps = gap * math.max(0, count - 1)

  -- A flex child must stay flex. Resolving it to its content height first would
  -- pin a sender at fourteen pixels and push the timestamp over it, which is
  -- what the interface actually draws if the grow is ignored.
  local sizes, fixed, flex_total = {}, 0, 0
  for index, child in ipairs(children) do
    local size = layout_fixed(child, direction)
    if size ~= nil then
      sizes[index] = size
      fixed = fixed + size
    else
      local grow = child.layout and child.layout.flex_grow or 0
      if type(grow) == "number" and grow > 0 then
        sizes[index] = false
        flex_total = flex_total + grow
      else
        local fallback = layout_default(child)
        if fallback ~= nil then
          sizes[index] = fallback
          fixed = fixed + fallback
        else
          sizes[index] = false
        end
      end
    end
  end

  local remaining = math.max(0, total - fixed - gaps)
  for index, child in ipairs(children) do
    if sizes[index] == false then
      local grow = child.layout and child.layout.flex_grow or 0
      if flex_total > 0 and type(grow) == "number" and grow > 0 then
        sizes[index] = remaining * (grow / flex_total)
      else
        sizes[index] = remaining / math.max(1, count)
      end
    end
  end

  local cursor = 0
  for index, child in ipairs(children) do
    local size = sizes[index]
    if direction == "row" then
      layout_assign(child, content_x + cursor, content_y, size, content_h, out)
    else
      layout_assign(child, content_x, content_y + cursor, content_w, size, out)
    end
    cursor = cursor + size + gap
  end
end

--- Lay out `tree` in a `width` x `height` surface.
---
--- Returns `{ root = <rect>, nodes = <flat list> }`, matching the host's shape so
--- a view can reach for either without noticing.
function ui.layout_tree(tree, width, height)
  assert(type(tree) == "table", "ui.layout_tree needs a tree")
  local out = {}
  layout_assign(tree, 0, 0, width or 0, height or 0, out)
  return { root = tree.rect, nodes = out }
end

function ui.layout(tree, width, height)
  if ui._component_resolver then
    tree = ui._component_resolver(tree)
  end
  local host = rawget(_G, "canvas")
  if type(host) == "table" and type(host.layout) == "function" then
    return host.layout(tree, width, height)
  end
  return ui.layout_tree(tree, width, height)
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

--- A recording surface that emits a `soil_scene` document plus hit targets.
---
--- This is the portable form of `ui.surface`: no `canvas.*`, no `widget.*`, no
--- host globals. A GPU renderer or a test can capture the same view the Canvas
--- path draws, without linking the compositor.
function ui.scene_surface(width, height, theme)
  local surface = {
    width = width,
    height = height,
    theme = theme or ui.theme(),
    z = 0,
    scene = { schema = 1, nodes = {}, transparent = false },
    hits = {},
    used = {},
  }

  local base = surface.theme.body or 16

  function surface:nx(px) return -4 + 8 * px / self.width end
  function surface:ny(px) return 4 - 8 * px / self.height end
  function surface:sw(px) return 8 * px / self.width end
  function surface:sh(px) return 8 * px / self.height end
  function surface:ts(px) return px / (base * 1.25) end

  function surface:unique(id)
    id = tostring(id or "node")
    if id == "" then id = "node" end
    if id:find("[\128-\255]") then id = "node" end
    local seen = self.used[id] or 0
    self.used[id] = seen + 1
    if seen == 0 then return id end
    return id .. "~" .. seen
  end

  function surface:rect(id, x, y, w, h, ink, opacity, radius, z)
    local ink_name, rgb = color_parts(ink, "surface")
    self.scene.nodes[#self.scene.nodes + 1] = {
      id = self:unique(id),
      transform = {
        translation = { self:nx(x), self:ny(y), z or self.z },
        scale = { self:sw(math.max(1, w)), self:sh(math.max(1, h)), 1 },
      },
      type = "rect",
      ink = ink_name,
      rgb = rgb,
      opacity = opacity == nil and 1.0 or opacity,
      radius = math.min(self:sw(radius or 0), self:sh(radius or 0)),
    }
  end

  function surface:text(id, value, x, y, size, ink, z)
    local ink_name, rgb = color_parts(ink, "text")
    self.scene.nodes[#self.scene.nodes + 1] = {
      id = self:unique(id),
      transform = {
        translation = { self:nx(x), self:ny(y), z or (self.z + 0.1) },
        scale = { self:ts(size), self:ts(size), 1 },
      },
      type = "text",
      text = tostring(value or ""),
      ink = ink_name,
      rgb = rgb,
      opacity = 1.0,
    }
  end

  --- One text node per line, not one per colour change.
  ---
  --- A terminal row is a single line that changes colour part-way through.
  --- Painting it as one node per run costs a node per run; the line is the
  --- thing, the runs are only how it is painted. The node still carries `text`
  --- (the runs concatenated) and the first run's ink, so a host that has not
  --- learned `runs` draws the line in one colour instead of drawing nothing.
  function surface:text_runs(id, runs, x, y, size, ink, z)
    local styled, joined = {}, {}
    for _, run in ipairs(runs or {}) do
      local value = tostring(run.text or run[1] or "")
      if value ~= "" then
        local ink_name, rgb = color_parts(run.ink or run[2], nil)
        styled[#styled + 1] = { text = value, ink = ink_name, rgb = rgb }
        joined[#joined + 1] = value
      end
    end
    if #styled == 0 then return end
    local first = styled[1]
    local ink_name, rgb = color_parts(ink or first.ink, "text")
    self.scene.nodes[#self.scene.nodes + 1] = {
      id = self:unique(id),
      transform = {
        translation = { self:nx(x), self:ny(y), z or (self.z + 0.1) },
        scale = { self:ts(size), self:ts(size), 1 },
      },
      type = "text",
      text = table.concat(joined),
      ink = ink_name,
      rgb = rgb or first.rgb,
      runs = styled,
      opacity = 1.0,
    }
  end

  function surface:measure_text(value, size)
    local api = rawget(_G, "canvas")
    if type(api) == "table" and type(api.measure_text) == "function" then
      local ok, measured = pcall(api.measure_text, tostring(value or ""), {
        size = tonumber(size) or 10,
        wrap = false,
      })
      if ok and type(measured) == "table" and type(measured.width) == "number" then
        return measured
      end
    end
    return measure_text(value, size)
  end

  function surface:line(id, x1, y1, x2, y2, width, ink, opacity)
    local dx, dy = x2 - x1, y2 - y1
    local length = math.max(math.abs(dx), math.abs(dy))
    -- The Canvas fallback is a retained scene, not a raster surface: a line
    -- made of one node per pixel burns the module node budget.  Two-pixel
    -- blocks stay visually contiguous and leave room for chart axes and text.
    local steps = math.max(1, math.ceil(length / 6))
    local thick = math.max(1, width or 1, 6)
    for index = 0, steps do
      local t = index / steps
      self:rect(id .. "-" .. index, x1 + dx * t - thick * 0.5, y1 + dy * t - thick * 0.5,
        thick, thick, ink or "primary", opacity == nil and 1.0 or opacity, thick * 0.5)
    end
  end

  function surface:polyline(id, points, width, ink, opacity, join, miter_limit)
    local out = {}
    for _, point in ipairs(points or {}) do
      out[#out + 1] = { self:nx(point[1]), self:ny(point[2]) }
    end
    if #out < 2 then return end
    local ink_name, rgb = color_parts(ink, "primary")
    self.scene.nodes[#self.scene.nodes + 1] = {
      id = self:unique(id),
      transform = { translation = { 0, 0, self.z }, scale = { 1, 1, 1 } },
      type = "polyline",
      points = out,
      width = self:sh(math.max(1, width or 1)),
      ink = ink_name,
      rgb = rgb,
      opacity = opacity == nil and 1.0 or opacity,
      join = join or "miter",
      miter_limit = miter_limit or 4.0,
    }
  end

  function surface:area(id, points, baseline, ink, opacity, base_opacity)
    local out = {}
    for _, point in ipairs(points or {}) do
      out[#out + 1] = { self:nx(point[1]), self:ny(point[2]) }
    end
    if #out < 2 then return end
    local ink_name, rgb = color_parts(ink, "primary")
    self.scene.nodes[#self.scene.nodes + 1] = {
      id = self:unique(id),
      transform = { translation = { 0, 0, self.z }, scale = { 1, 1, 1 } },
      type = "area",
      points = out,
      baseline = self:ny(baseline),
      ink = ink_name,
      rgb = rgb,
      opacity = opacity == nil and 0.18 or opacity,
      base_opacity = base_opacity,
    }
  end

  function surface:band(id, upper, lower, ink, opacity)
    local up, lo = {}, {}
    for index, point in ipairs(upper or {}) do
      up[#up + 1] = { self:nx(point[1]), self:ny(point[2]) }
      local low = (lower or {})[index]
      if low then lo[#lo + 1] = { self:nx(low[1]), self:ny(low[2]) } end
    end
    if #up < 2 or #up ~= #lo then return end
    local ink_name, rgb = color_parts(ink, "primary")
    self.scene.nodes[#self.scene.nodes + 1] = {
      id = self:unique(id),
      transform = { translation = { 0, 0, self.z }, scale = { 1, 1, 1 } },
      type = "band",
      upper = up,
      lower = lo,
      ink = ink_name,
      rgb = rgb,
      opacity = opacity == nil and 0.14 or opacity,
    }
  end

  function surface:points(id, points, size, ink, opacity)
    local out = {}
    for _, point in ipairs(points or {}) do
      out[#out + 1] = { self:nx(point[1]), self:ny(point[2]) }
    end
    if #out == 0 then return end
    size = math.max(1, size or 3)
    self.scene.nodes[#self.scene.nodes + 1] = {
      id = self:unique(id),
      transform = { translation = { 0, 0, self.z }, scale = { 1, 1, 1 } },
      type = "points",
      points = out,
      size = { self:sw(size), self:sh(size) },
      ink = ink or "primary",
      opacity = opacity == nil and 1.0 or opacity,
    }
  end

  function surface:heatmap(id, values, rows, cols, x, y, width, height, min, max, opacity)
    self.scene.nodes[#self.scene.nodes + 1] = {
      id = self:unique(id),
      transform = {
        translation = { self:nx(x), self:ny(y), self.z },
        scale = { self:sw(width), self:sh(height), 1 },
      },
      type = "heatmap",
      rows = rows,
      cols = cols,
      values = values,
      min = min,
      max = max,
      opacity = opacity == nil and 0.9 or opacity,
    }
  end

  function surface:candles(id, candles, width, up_ink, down_ink, opacity)
    local out = {}
    for _, candle in ipairs(candles or {}) do
      out[#out + 1] = {
        x = self:nx(candle.x),
        open = self:ny(candle.open),
        high = self:ny(candle.high),
        low = self:ny(candle.low),
        close = self:ny(candle.close),
      }
    end
    if #out == 0 then return end
    self.scene.nodes[#self.scene.nodes + 1] = {
      id = self:unique(id),
      transform = { translation = { 0, 0, self.z }, scale = { 1, 1, 1 } },
      type = "candles",
      candles = out,
      width = self:sw(math.max(1, width or 4)),
      up_ink = up_ink or "success",
      down_ink = down_ink or "danger",
      opacity = opacity == nil and 1.0 or opacity,
    }
  end

  function surface:find(laid, id)
    return ui.find(laid, id)
  end

  function surface:hit(id, rect, label)
    if rect.width <= 0 or rect.height <= 0
      or rect.x < -0.5 or rect.y < -0.5
      or rect.x + rect.width > self.width + 0.5
      or rect.y + rect.height > self.height + 0.5 then
      return false
    end
    self.hits[#self.hits + 1] = {
      id = tostring(id),
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

--- Capture a view that calls `ui.surface` into a portable scene document.
---
--- `paint(surface)` usually calls the view's render function. The return value
--- is `(present, hits)` where `present` is a `soil_scene::Present::Scene`
--- payload and `hits` are normalized local target rectangles.
function ui.capture(width, height, theme, paint)
  local previous = ui.backend
  local surface = ui.scene_surface(width, height, theme)
  ui.backend = surface
  local ok, err = pcall(paint, surface)
  ui.backend = previous
  if not ok then error(err, 0) end
  local present = {
    kind = "scene",
    schema = surface.scene.schema,
    nodes = surface.scene.nodes,
    transparent = surface.scene.transparent,
  }
  return present, surface.hits
end

--- A rect inside an existing surface, in logical pixels.
--
-- The child delegates primitives and ids to the parent but maps its local
-- coordinates into the parent's pixel box. It is the composition seam for
-- dashboards and component cells: a child never needs to know the parent's
-- normalized coordinate system.
function ui.subsurface(parent, x, y, width, height, prefix)
  if not parent or not parent.nx or not parent.ny then
    error("ui.subsurface needs a surface", 2)
  end
  prefix = prefix or ""
  local sub = {
    width = width,
    height = height,
    z = parent.z,
    theme = parent.theme,
    used = parent.used,
    parent = parent,
    origin = { x = x, y = y },
  }
  function sub:nx(px) return parent:nx(x + px) end
  function sub:ny(py) return parent:ny(y + py) end
  function sub:sw(px) return parent:sw(px) end
  function sub:sh(py) return parent:sh(py) end
  function sub:ts(px) return parent:ts(px) end
  -- Prefix ids so two composed charts cannot collide in the host scene. The
  -- primitive bodies still live in the parent; only identity is namespaced.
  function sub:rect(id, ...) return parent.rect(self, prefix .. id, ...) end
  function sub:text(id, ...) return parent.text(self, prefix .. id, ...) end
  function sub:text_runs(id, ...) return parent.text_runs(self, prefix .. id, ...) end
  function sub:line(id, ...) return parent.line(self, prefix .. id, ...) end
  function sub:polyline(id, ...) return parent.polyline(self, prefix .. id, ...) end
  function sub:area(id, ...) return parent.area(self, prefix .. id, ...) end
  function sub:band(id, ...) return parent.band(self, prefix .. id, ...) end
  function sub:points(id, ...) return parent.points(self, prefix .. id, ...) end
  function sub:heatmap(id, ...) return parent.heatmap(self, prefix .. id, ...) end
  function sub:candles(id, ...) return parent.candles(self, prefix .. id, ...) end
  function sub:hit(id, ...) return parent.hit(self, prefix .. id, ...) end
  return setmetatable(sub, { __index = parent })
end

--- A tiny scene surface in logical pixels.
---
--- Surface coordinates are top-left origin. It converts to Canvas's normalized
--- space, so views never hand-write the -4..4 math.
function ui.surface(width, height, theme)
  if ui.backend then return ui.backend end
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
    local ink_name, rgb = color_parts(ink, "surface")
    canvas.rect {
      id = id,
      ink = ink_name,
      rgb = rgb,
      opacity = opacity == nil and 1.0 or opacity,
      radius = radius or 0,
      translation = { self:nx(x), self:ny(y), z or self.z },
      scale = { self:sw(math.max(1, w)), self:sh(math.max(1, h)), 1 },
    }
  end

  function surface:text(id, value, x, y, size, ink, z)
    local ink_name, rgb = color_parts(ink, "text")
    canvas.text {
      id = id,
      text = tostring(value or ""),
      ink = ink_name,
      rgb = rgb,
      translation = { self:nx(x), self:ny(y), z or (self.z + 0.1) },
      scale = { self:ts(size), self:ts(size), 1 },
    }
  end

  --- See `ui.scene_surface`'s `text_runs`: one node per line, runs inside it.
  function surface:text_runs(id, runs, x, y, size, ink, z)
    local styled, joined = {}, {}
    for _, run in ipairs(runs or {}) do
      local value = tostring(run.text or run[1] or "")
      if value ~= "" then
        local ink_name, rgb = color_parts(run.ink or run[2], nil)
        styled[#styled + 1] = { text = value, ink = ink_name, rgb = rgb }
        joined[#joined + 1] = value
      end
    end
    if #styled == 0 then return end
    local first = styled[1]
    local ink_name, rgb = color_parts(ink or first.ink, "text")
    canvas.text {
      id = id,
      text = table.concat(joined),
      ink = ink_name,
      rgb = rgb or first.rgb,
      runs = styled,
      translation = { self:nx(x), self:ny(y), z or (self.z + 0.1) },
      scale = { self:ts(size), self:ts(size), 1 },
    }
  end

  function surface:measure_text(value, size)
    local api = rawget(_G, "canvas")
    if type(api) == "table" and type(api.measure_text) == "function" then
      local ok, measured = pcall(api.measure_text, tostring(value or ""), {
        size = tonumber(size) or 10,
        wrap = false,
      })
      if ok and type(measured) == "table" and type(measured.width) == "number" then
        return measured
      end
    end
    return measure_text(value, size)
  end

  function surface:line(id, x1, y1, x2, y2, width, ink, opacity)
    local dx, dy = x2 - x1, y2 - y1
    local length = math.max(math.abs(dx), math.abs(dy))
    -- The Canvas fallback is a retained scene, not a raster surface: a line
    -- made of one node per pixel burns the module node budget.  Two-pixel
    -- blocks stay visually contiguous and leave room for chart axes and text.
    local steps = math.max(1, math.ceil(length / 6))
    local thick = math.max(1, width or 1, 6)
    for index = 0, steps do
      local t = index / steps
      self:rect(id .. "-" .. index, x1 + dx * t - thick * 0.5, y1 + dy * t - thick * 0.5,
        thick, thick, ink or "primary", opacity == nil and 1.0 or opacity, thick * 0.5)
    end
  end

  function surface:polyline(id, points, width, ink, opacity, join, miter_limit)
    for index = 2, #(points or {}) do
      local previous, point = points[index - 1], points[index]
      self:line(id .. "-" .. index, previous[1], previous[2], point[1], point[2], width, ink, opacity)
    end
  end

  function surface:area(id, points, baseline, ink, opacity)
    for index = 2, #(points or {}) do
      local a, b = points[index - 1], points[index]
      local dx = b[1] - a[1]
      local steps = math.max(1, math.ceil(math.abs(dx)))
      for step = 0, steps do
        local t = step / steps
        local x = a[1] + dx * t
        local y = a[2] + (b[2] - a[2]) * t
        self:rect(id .. "-" .. index .. "-" .. step, x, math.min(y, baseline), 1,
          math.max(1, math.abs(baseline - y)), ink or "primary", opacity == nil and 0.18 or opacity, 0)
      end
    end
  end

  function surface:points(id, points, size, ink, opacity)
    for index, point in ipairs(points or {}) do
      self:rect(id .. "-" .. index, point[1] - size * 0.5, point[2] - size * 0.5,
        size, size, ink or "primary", opacity == nil and 1.0 or opacity, size * 0.5)
    end
  end

  function surface:heatmap(id, values, rows, cols, x, y, width, height, min, max, opacity)
    local cw, ch = width / cols, height / rows
    local lo, hi = min, max
    if not lo or not hi then
      lo, hi = math.huge, -math.huge
      for _, value in ipairs(values or {}) do
        lo, hi = math.min(lo, value), math.max(hi, value)
      end
    end
    if lo == hi then hi = lo + 1 end
    for row = 1, rows do
      for col = 1, cols do
        local value = values[(row - 1) * cols + col]
        local t = (value - lo) / (hi - lo)
        local color = t >= 0.75 and "danger" or t >= 0.5 and "warning" or t >= 0.25 and "success" or "primary"
        self:rect(id .. "-" .. row .. "-" .. col, x + (col - 1) * cw, y + (row - 1) * ch,
          cw + 0.5, ch + 0.5, color, opacity == nil and 0.9 or opacity, 0)
      end
    end
  end

  function surface:candles(id, candles, width, up_ink, down_ink, opacity)
    for index, candle in ipairs(candles or {}) do
      local color = candle.close >= candle.open and (up_ink or "success") or (down_ink or "danger")
      self:line(id .. "-wick-" .. index, candle.x, candle.high, candle.x, candle.low, 1, color, opacity)
      local top, bottom = math.min(candle.open, candle.close), math.max(candle.open, candle.close)
      self:rect(id .. "-body-" .. index, candle.x - width * 0.5, top, width,
        math.max(1, bottom - top), color, opacity == nil and 1.0 or opacity, 0)
    end
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
local function measured_width(surface, value, size)
  local measured = surface.measure_text and surface:measure_text(value, size)
  if type(measured) == "table" and type(measured.width) == "number" then
    return measured.width
  end
  return tonumber(measured) or (#tostring(value or "") * size * 0.58)
end

local function wrap_lines(surface, value, size, width)
  local lines = {}
  for paragraph in tostring(value or ""):gmatch("[^\n]+") do
    local current = ""
    for word in paragraph:gmatch("%S+") do
      local candidate = current == "" and word or (current .. " " .. word)
      if current ~= "" and measured_width(surface, candidate, size) > width then
        lines[#lines + 1] = current
        current = word
      else
        current = candidate
      end
    end
    lines[#lines + 1] = current
  end
  if #lines == 0 then lines[1] = "" end
  return lines
end

function ui.paint_text(surface, laid, ink_for)
  for _, item in ipairs((laid and laid.nodes) or {}) do
    if item.kind == "text" and item.style then
      local ink = (ink_for and ink_for(item)) or item.ink or "text"
      local lines = { item.text }
      if item.style.wrap and item.rect.width and item.rect.width > 1 then
        lines = wrap_lines(surface, item.text, item.style.size, item.rect.width)
      end
      local line_height = item.style.line_height or (item.style.size + 4)
      for index, line in ipairs(lines) do
        local id = index == 1 and item.id or (item.id .. "-line-" .. index)
        surface:text(id, line, item.rect.x, item.rect.y + (index - 1) * line_height,
          item.style.size, ink)
      end
    end
  end
end

--- Lay a tree out and paint it into this frame's surface.
---
--- This is the whole contract a view needs: build the tree, hand it here. The
--- layout comes from the host when it has one and from `ui.layout_tree` when it
--- does not, so the same view draws the same geometry under Canvas, `tend`,
--- `chrome-host` and `tools/shot.lua`. A view that returns a tree instead of
--- presenting it paints nothing anywhere, because no host in this system lays
--- out a tree it is handed.
---
--- Returns the hit targets (see `ui.paint_tree`).
function ui.present(tree, opts)
  opts = opts or {}
  local width, height = ui.viewport(opts.width or 1200, opts.height or 900)
  local laid = ui.layout(tree, width, height)
  local surface = ui.surface(width, height, opts.theme or ui.theme())
  return ui.paint_tree(surface, laid, opts)
end

--- Draw a tab strip into a surface and return where each tab landed.
---
--- `paint_text` and `paint_rules` exist because a view that places its own pixels
--- still wants the library's typography and separators. A tab strip is the same
--- kind of thing: sessions, documents and panes all need one, and a per-app copy
--- is where the widths, the active rule and the padding start disagreeing.
---
--- `tabs` is `{ { id, label, selected?, muted?, action? } }`. The return value is
--- the hit list — `{ id, x, y, width, height, action }` in the same pixels the
--- strip was drawn in — so a host can turn a click into an action without
--- repeating the layout arithmetic.
function ui.paint_tabs(surface, x, y, width, height, tabs, opts)
  opts = opts or {}
  local size = opts.size or 11
  local pad = opts.padding or 12
  local gap = opts.gap or 2
  local z = opts.z
  local hits = {}
  local cursor = x
  for index, tab in ipairs(tabs or {}) do
    local label = tostring(tab.label or "tab")
    local tab_width = math.floor(#label * size * 0.58 + pad * 2)
    if cursor + tab_width > x + width then break end
    local id = tostring(tab.id or index)
    if tab.selected then
      surface:rect("tab-" .. id .. "-active", cursor, y, tab_width, height, "surface", 0.30, 6, z)
      surface:rect("tab-" .. id .. "-rule", cursor, y + height - 2, tab_width, 2, "primary", 0.9, 0, z)
    end
    surface:text("tab-" .. id .. "-label", label, cursor + pad,
      y + math.floor((height - size) / 2), size,
      tab.selected and "primary" or (tab.muted and "muted" or "text"))
    hits[#hits + 1] = {
      id = id,
      label = label,
      x = cursor,
      y = y,
      width = tab_width,
      height = height,
      action = tab.action,
    }
    cursor = cursor + tab_width + gap
  end
  return hits
end

--- Paint a laid-out tree: fills first, then rules, then text.
---
--- The order is the job. Canvas sorts by z and breaks ties by insertion, so a
--- panel drawn after its text covers it; three passes make the order a property
--- of the painter instead of a consequence of how a view built its children.
---
--- Returns the hit targets for nodes that carry an `action`. A host that
--- implements `widget.button` is handed them directly; the return value keeps
--- them addressable for a host that does not.
function ui.paint_tree(surface, laid, opts)
  opts = opts or {}
  local nodes = (laid and laid.nodes) or {}
  local hits = {}

  local function fill_of(item)
    if opts.fill then return opts.fill(item) end
    local style = item.style or {}
    if style.fill then return style.fill, style.opacity or 1, style.radius or 0 end
    if item.selected then return "primary", 0.16, style.radius or 6 end
    if item.variant == "primary" then return "primary", 0.18, style.radius or 8 end
    if item.variant == "danger" then return "danger", 0.18, style.radius or 8 end
    return nil
  end

  for _, item in ipairs(nodes) do
    local rect = item.rect
    if rect then
      local ink, opacity, radius = fill_of(item)
      if ink then
        surface:rect(item.id, rect.x, rect.y, rect.width, rect.height, ink, opacity, radius, opts.z)
      end
    end
  end

  ui.paint_rules(surface, laid, opts.rule_ink, opts.rule_opacity)
  ui.paint_text(surface, laid, opts.ink_for)

  for _, item in ipairs(nodes) do
    if item.action and item.rect then
      local spec = {
        id = item.id,
        x = item.rect.x,
        y = item.rect.y,
        width = item.rect.width,
        height = item.rect.height,
        action = item.action,
      }
      hits[#hits + 1] = spec
      -- A scene surface keeps its own hit list, so a capture (`tend --scene`,
      -- `ui.capture`) reports the same targets a compositor would receive. The
      -- geometry it wants is pixel rects, not the spec's flat fields.
      if type(surface.hit) == "function" then
        surface:hit(item.id, item.rect, "button")
      end
      local host = rawget(_G, "widget")
      if type(host) == "table" and type(host.button) == "function" then
        host.button(spec)
      end
    end
  end
  return hits
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
