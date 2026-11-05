-- Contacts — Lua-only iteration on fungos.ui.
--
-- Host owns records, query, persistence, and pane geometry. This view owns
-- hierarchy, copy, hover/press feedback, and local selection memory.

local ui = require("fungos.ui")
local action = require("fungos.action")

local M = {}
M.name = "example.contacts"
M.version = "0.1.0"

local function clip(value, limit)
  return ui.clip(value, limit)
end

local function initials(name)
  name = tostring(name or "?")
  local a, b = name:match("(%S+)%s+(%S+)")
  if a and b then return (a:sub(1, 1) .. b:sub(1, 1)):upper() end
  return name:sub(1, 1):upper()
end

local function selected_contact(snapshot)
  for index, contact in ipairs(snapshot.contacts or {}) do
    if contact.id == snapshot.selected_id then return contact, index end
  end
  return (snapshot.contacts or {})[1], 1
end

local function read_view_state()
  local module = rawget(_G, "module")
  local raw = module and module.view and module.view.selected
  local state = {}
  if type(raw) ~= "string" then return state end
  if raw:sub(1, 2) ~= "v1" then
    state.contact = raw
    return state
  end
  for part in raw:gmatch("[^;]+") do
    local key, value = part:match("^([%w_]+)=(.*)$")
    if key then state[key] = value end
  end
  return state
end

local function write_view_state(state)
  local module = rawget(_G, "module")
  if not (module and type(module.select) == "function") then return end
  local parts = { "v1" }
  for _, key in ipairs({ "contact", "filter", "toast" }) do
    local value = state[key]
    if value and value ~= "" and not value:find("[;=]") then
      parts[#parts + 1] = key .. "=" .. value
    end
  end
  local raw = table.concat(parts, ";")
  if #raw <= 128 then pcall(module.select, raw) end
end

local function apply_state(snapshot, state)
  if state.contact then
    for _, contact in ipairs(snapshot.contacts or {}) do
      if contact.id == state.contact then snapshot.selected_id = contact.id end
    end
  end
  if state.filter then
    for _, filter in ipairs(snapshot.filters or {}) do
      filter.selected = filter.id == state.filter
    end
  end
end

local function contact_favorite(contact)
  return contact.favorite == true
end

local function contact_mru(contact)
  return tonumber(contact.last_contacted) or 0
end

local function slug(value)
  value = tostring(value or ""):lower():gsub("[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
  if value == "" then return "unknown" end
  return value
end

local function email_domain(contact)
  local email = contact.emails and contact.emails[1]
  if not email then return nil end
  local domain = tostring(email):match("@([^@]+)$")
  if not domain then return nil end
  return domain:lower()
end

local function sorted_contacts(snapshot)
  local contacts = {}
  for _, contact in ipairs(snapshot.contacts or {}) do contacts[#contacts + 1] = contact end
  table.sort(contacts, function(a, b)
    local af, bf = contact_favorite(a), contact_favorite(b)
    if af ~= bf then return af end
    local am, bm = contact_mru(a), contact_mru(b)
    if am ~= bm then return am > bm end
    return (a.name or "") < (b.name or "")
  end)
  return contacts
end

local function filter_matches(contact, filter_id)
  if filter_id == nil or filter_id == "" or filter_id == "all" then return true end
  if filter_id == "favorites" then return contact_favorite(contact) end
  if filter_id == "recent" then return contact_mru(contact) > 0 end
  if filter_id:sub(1, 4) == "org-" then
    return "org-" .. slug(contact.org) == filter_id
  end
  if filter_id:sub(1, 7) == "domain-" then
    return "domain-" .. slug(email_domain(contact)) == filter_id
  end
  if filter_id:sub(1, 4) == "tag-" then
    local wanted = filter_id:sub(5)
    for _, tag in ipairs(contact.tags or {}) do
      if slug(tag) == wanted then return true end
    end
    return false
  end
  return true
end

local function visible_contacts(snapshot, filter_id)
  local out = {}
  for _, contact in ipairs(sorted_contacts(snapshot)) do
    if filter_matches(contact, filter_id) then out[#out + 1] = contact end
  end
  if filter_id == "recent" then
    local recent = {}
    for index = 1, math.min(20, #out) do recent[#recent + 1] = out[index] end
    return recent
  end
  return out
end

local function derive_folders(snapshot)
  local contacts = snapshot.contacts or {}
  local folders = {
    { id = "all", label = "All", kind = "smart", count = #contacts },
    { id = "favorites", label = "Favorites", kind = "smart", count = 0 },
    { id = "recent", label = "Recent", kind = "smart", count = 0 },
  }
  local orgs, domains, tags = {}, {}, {}
  for _, contact in ipairs(contacts) do
    if contact_favorite(contact) then folders[2].count = folders[2].count + 1 end
    if contact_mru(contact) > 0 then folders[3].count = folders[3].count + 1 end
    local org = contact.org or ""
    if org ~= "" and org ~= contact.name then
      orgs[org] = (orgs[org] or 0) + 1
    end
    local domain = email_domain(contact)
    if domain then domains[domain] = (domains[domain] or 0) + 1 end
    for _, tag in ipairs(contact.tags or {}) do tags[tag] = (tags[tag] or 0) + 1 end
  end
  local function append(map, prefix, kind, limit)
    local rows = {}
    for label, count in pairs(map) do rows[#rows + 1] = { label = label, count = count } end
    table.sort(rows, function(a, b)
      if a.count ~= b.count then return a.count > b.count end
      return a.label < b.label
    end)
    for index = 1, math.min(limit, #rows) do
      local row = rows[index]
      folders[#folders + 1] = {
        id = prefix .. slug(row.label),
        label = row.label,
        kind = kind,
        value = row.label,
        count = row.count,
      }
    end
  end
  append(orgs, "org-", "org", 3)
  append(domains, "domain-", "domain", 3)
  append(tags, "tag-", "tag", 3)
  return folders
end

local function active_filter(snapshot, state)
  if state.filter and state.filter ~= "" then return state.filter end
  for _, filter in ipairs(snapshot.filters or {}) do
    if filter.selected then return filter.id end
  end
  return "all"
end

local function contact_line(contact)
  local org = contact.org or ""
  local title = contact.title or ""
  if org ~= "" and org == contact.name then org = "" end
  if org ~= "" and title ~= "" then return org .. "  ·  " .. title end
  if org ~= "" then return org end
  if title ~= "" then return title end
  return "—"
end

local function contact_preview(contact)
  if contact.emails and contact.emails[1] then return contact.emails[1] end
  if contact.phones and contact.phones[1] then return contact.phones[1] end
  return "No contact details"
end

local function activate(snapshot, state, target)
  target = tostring(target or "")
  local index = tonumber(target:match("^contact%-(%d+)$"))
  local current_filter = active_filter(snapshot, state)
  local contacts = visible_contacts(snapshot, current_filter)
  if index and contacts[index] then
    state.contact = contacts[index].id
    apply_state(snapshot, state)
    return
  end
  local filter_id = target:match("^contacts%-filters%-(.+)$")
    or target:match("^contacts%-smart%-(.+)$")
    or target:match("^contacts%-groups%-(.+)$")
  if filter_id then
    state.filter = filter_id
    apply_state(snapshot, state)
    return
  end
  if target == "contact-action-call" then
    state.toast = "call"
  elseif target == "contact-action-email" then
    state.toast = "email"
  elseif target == "contact-action-message" then
    state.toast = "message"
  elseif target == "contact-action-edit" then
    state.toast = "edit"
  elseif target == "contact-toast-undo" then
    state.toast = nil
  end
end

local function inside(rect, x, y)
  return x >= rect.x and y >= rect.y and x <= rect.x + rect.width and y <= rect.y + rect.height
end

local function hit_target(snapshot, state, laid, x, y)
  local function hit(id)
    local node = ui.find(laid, id)
    return node and inside(node.rect, x, y)
  end
  for _, id in ipairs({
    "contact-action-message", "contact-action-call", "contact-action-email",
    "contact-action-edit", "contact-toast-undo",
  }) do
    if hit(id) then return id end
  end
  local folders = derive_folders(snapshot)
  for _, filter in ipairs(folders) do
    for _, prefix in ipairs({ "contacts-filters-", "contacts-smart-", "contacts-groups-" }) do
      local id = prefix .. (filter.id or "")
      if hit(id) then return id end
    end
  end
  local contacts = visible_contacts(snapshot, active_filter(snapshot, state))
  for index = 1, #contacts do
    if hit("contact-" .. index) then return "contact-" .. index end
  end
end

local function contact_row(contact, index, selected)
  local line = contact_line(contact)
  local body = {
    ui.text("contact-" .. index .. "-name", clip(contact.name, 30), {
      size = 12,
      height = 18,
      ink = selected and "primary" or "text",
      flex_grow = 1,
    }),
  }
  if line ~= "—" then
    body[#body + 1] = ui.text("contact-" .. index .. "-line", clip(line, 36), {
      size = 9,
      ink = "muted",
      height = 14,
    })
  end
  return ui.list_row("contact-" .. index, {
    auto_height = true,
    min_height = 58,
    selected = selected,
    unread = false,
    gap = 10,
    padding = { top = 7, right = 10, bottom = 7, left = 10 },
  }, {
    ui.avatar("contact-" .. index .. "-avatar", initials(contact.name), {
      size = 34,
      ink = selected and "primary" or "muted",
    }),
    ui.column("contact-" .. index .. "-body", { flex_grow = 1, gap = 2 }, body),
  })
end

local function split_folders(snapshot)
  local smart, groups = {}, {}
  for _, folder in ipairs(derive_folders(snapshot)) do
    if folder.kind == "smart" then smart[#smart + 1] = folder
    else groups[#groups + 1] = folder end
  end
  return smart, groups
end

local function selected_folder(snapshot, state, folders)
  local id = active_filter(snapshot, state)
  for _, folder in ipairs(folders) do
    if folder.id == id then return folder end
  end
  return folders[1]
end

local function folder_bar(snapshot, state)
  local smart = split_folders(snapshot)
  local current = active_filter(snapshot, state)
  local children = {}
  for _, filter in ipairs(smart) do
    local id = filter.id or ""
    local selected = id == current
    children[#children + 1] = ui.list_row("contacts-filters-" .. id, {
      width = 96,
      height = 28,
      padding = { left = 7, right = 7 },
      selected = selected,
    }, {
      ui.text("contacts-filters-" .. id .. "-label", filter.label or id, {
        size = 9,
        ink = selected and "primary" or "muted",
        flex_grow = 1,
      }),
      ui.text("contacts-filters-" .. id .. "-count", tostring(filter.count or ""), {
        size = 8,
        ink = selected and "primary" or "muted",
        width = 20,
      }),
    })
  end
  return ui.row("contacts-filters", { height = 28, gap = 4 }, children)
end

local function folder_sidebar(snapshot, state)
  local smart, groups = split_folders(snapshot)
  local current = active_filter(snapshot, state)
  local function items(folders)
    local out = {}
    for _, folder in ipairs(folders) do
      out[#out + 1] = {
        id = folder.id,
        label = clip(folder.label, 24),
        count = folder.count,
        selected = folder.id == current,
      }
    end
    return out
  end
  local children = {
    ui.sidebar_group("contacts-smart", "SMART", items(smart), { size = 10, height = 27 }),
  }
  if #groups > 0 then
    children[#children + 1] = ui.sidebar_group("contacts-groups", "AUTO GROUPS", items(groups), {
      size = 9,
      height = 24,
      count_size = 9,
      count_width = 24,
    })
  end
  return ui.column("contacts-folders", { gap = 8 }, children)
end

local function details_page(contact, compact)
  if not contact then
    return ui.empty_state("contact-detail-empty", "Select a contact", "Choose someone from the list.", {
      title_size = 15, detail_size = 11, detail_height = 24,
    })
  end

  local head_children = {
    ui.avatar("contact-detail-avatar", initials(contact.name), {
      size = compact and 48 or 76,
      text_size = compact and 18 or 28,
      ink = "primary",
    }),
    ui.column("contact-detail-meta", { flex_grow = 1, gap = compact and 1 or 4 }, {
      ui.text("contact-detail-name", clip(contact.name, 40), {
        size = compact and 19 or 27,
        height = compact and 25 or 34,
        ink = "primary",
      }),
      ui.text("contact-detail-role", clip(contact_line(contact), compact and 34 or 56), {
        size = compact and 10 or 12,
        height = compact and 16 or 20,
        ink = "muted",
      }),
    }),
  }

  local children = {
    ui.row("contact-detail-head", {
      height = compact and 58 or 80,
      gap = compact and 10 or 14,
      align_items = "center",
    }, head_children),
  }

  if compact then
    ui.push(children, ui.row("contact-detail-actions", { height = 30, gap = 6 }, {
      ui.button("contact-action-message", "Message", {
        size = 10, height = 28, variant = "primary",
        action = action.intent("contacts.message", { contact_id = contact.id }),
      }),
      ui.button("contact-action-call", "Call", {
        size = 10, height = 28,
        action = action.intent("contacts.call", { contact_id = contact.id }),
      }),
      ui.button("contact-action-email", "Email", {
        size = 10, height = 28,
        action = action.intent("contacts.email", { contact_id = contact.id }),
      }),
    }))
  else
    ui.push(children, ui.row("contact-detail-actions", { height = 34, gap = 8 }, {
      ui.button("contact-action-message", "Message", {
        size = 11, height = 32, variant = "primary",
        action = action.intent("contacts.message", { contact_id = contact.id }),
      }),
      ui.button("contact-action-call", "Call", {
        size = 11, height = 32,
        action = action.intent("contacts.call", { contact_id = contact.id }),
      }),
      ui.button("contact-action-email", "Email", {
        size = 11, height = 32,
        action = action.intent("contacts.email", { contact_id = contact.id }),
      }),
      ui.button("contact-action-edit", "Edit", {
        size = 11, height = 32,
        action = action.intent("contacts.edit", { contact_id = contact.id }),
      }),
    }))
  end

  ui.push(children, ui.section_label("contact-details-label", "DETAILS"))
  local function detail_line(id, label, values, compact_height)
    if not values or #values == 0 then return end
    local lines = { ui.text(id .. "-label", label, { size = 9, ink = "muted", height = 14 }) }
    for index, value in ipairs(values) do
      lines[#lines + 1] = ui.text(id .. "-value-" .. index, clip(value, compact and 42 or 64), {
        size = compact and 10 or 12,
        height = compact_height or 19,
        ink = "text",
      })
    end
    ui.push(children, ui.column(id, { gap = 1 }, lines))
  end
  detail_line("contact-detail-email", "EMAIL", contact.emails, compact and 17 or 21)
  detail_line("contact-detail-phone", "PHONE", contact.phones, compact and 17 or 21)
  detail_line("contact-detail-address", "ADDRESS", contact.addresses, compact and 17 or 21)
  if contact.birthday and contact.birthday ~= "" then
    detail_line("contact-detail-birthday", "BIRTHDAY", { contact.birthday }, compact and 17 or 21)
  end

  ui.push(children, ui.section_label("contact-notes-label", "NOTES"))
  ui.push(children, ui.text("contact-notes-text", (contact.note and contact.note ~= "") and contact.note or "No notes yet.", {
    size = compact and 10 or 12,
    height = compact and 32 or 64,
    wrap = true,
    ink = (contact.note and contact.note ~= "") and "text" or "muted",
  }))

  return ui.column("contact-detail", {
    flex_grow = 1,
    gap = compact and 6 or 12,
    padding = compact and { top = 10, right = 12, bottom = 10, left = 12 }
      or { top = 16, right = 20, bottom = 16, left = 20 },
  }, children)
end

local function list_pane(snapshot, state, ctx, wide)
  local filter_id = active_filter(snapshot, state)
  local contacts = visible_contacts(snapshot, filter_id)
  local _, selected_index = selected_contact(snapshot)
  local max_rows = wide and 14 or math.max(4, math.floor((ctx.viewport.height - 500) / 58))
  local visible = math.min(#contacts, max_rows)
  local rows = {}
  for index = 1, visible do
    rows[#rows + 1] = contact_row(contacts[index], index, contacts[index].id == snapshot.selected_id)
  end
  if #contacts == 0 then
    rows[1] = ui.empty_state("contacts-list-empty", "No matches", "Try another folder or search.", {
      title_size = 14, detail_size = 10, detail_height = 24,
    })
  end
  local smart, groups = split_folders(snapshot)
  local folder = selected_folder(snapshot, state, (function()
    local all = {}
    for _, item in ipairs(smart) do all[#all + 1] = item end
    for _, item in ipairs(groups) do all[#all + 1] = item end
    return all
  end)())
  local children = {}
  if not wide then children[#children + 1] = folder_bar(snapshot, state) end
  children[#children + 1] = ui.row("contacts-list-head", { height = 28, padding = { left = 2, right = 2 } }, {
    ui.text("contacts-list-title", string.upper(folder and folder.label or "People"), {
      size = 9, ink = "muted", flex_grow = 1,
    }),
    ui.text("contacts-list-count", string.format("%d shown · %d total", #contacts, snapshot.total or #contacts), {
      size = 9, ink = "muted", width = 142,
    }),
  })
  children[#children + 1] = ui.column("contacts-list", { flex_grow = 1, gap = 0 }, rows)
  return ui.column("contacts-list-pane", { flex_grow = 1, gap = 2 }, children)
end

local function tree(ctx)
  local snapshot = ctx.snapshot
  local state = ctx.state
  local wide = ctx.viewport.width >= 760
  local selected = selected_contact(snapshot)
  local count = snapshot.total or #(snapshot.contacts or {})

  local root = ui.workspace("contacts-root", {
    width = ctx.viewport.width,
    height = ctx.viewport.height,
    gap = 10,
    padding = wide and { top = 18, right = 20, bottom = 16, left = 20 }
      or { top = 16, right = 14, bottom = 14, left = 14 },
  }, {
    ui.row("contacts-header", { height = wide and 70 or 64 }, {
      ui.column("contacts-heading", { flex_grow = 1, gap = 4 }, {
        ui.text("contacts-title", snapshot.title or "Contacts", {
          size = wide and 26 or 23,
          height = wide and 38 or 32,
          ink = "primary",
        }),
        ui.text("contacts-subtitle", (snapshot.account and snapshot.account.label or "Records") .. "  ·  " .. (snapshot.account and snapshot.account.sync or ""), {
          size = 9, ink = "muted", height = 16,
        }),
      }),
      ui.badge("contacts-total", tostring(count), { size = 11, ink = "primary", height = 24 }),
    }),
    ui.command_bar("contacts-search", {
      placeholder = "Search people, org, email, phone",
      query = snapshot.search,
      hint = "⌘K",
      size = 11,
      height = 40,
    }),
  })

  if wide then
    ui.push(root.children, ui.row("contacts-body", { flex_grow = 1, gap = 18 }, {
      ui.sidebar("contacts-sidebar", {
        width = 340,
        flex_shrink = 0,
        gap = 8,
        padding = { top = 10, right = 10, bottom = 10, left = 10 },
      }, { folder_sidebar(snapshot, state), list_pane(snapshot, state, ctx, true) }),
      ui.pane("contacts-detail-pane", {
        pane_id = "detail",
        flex_grow = 1,
        min_width = 0,
        focused = true,
        gap = 8,
        padding = { top = 0, right = 0, bottom = 0, left = 0 },
      }, { details_page(selected, false) }),
    }))
  else
    ui.push(root.children, ui.pane("contacts-detail-pane", {
      pane_id = "detail",
      flex_grow = 0,
      flex_shrink = 0,
      focused = true,
      gap = 6,
    }, { details_page(selected, true) }))
    ui.push(root.children, ui.sidebar("contacts-sidebar", {
      flex_grow = 1,
      gap = 4,
      padding = { top = 0, right = 0, bottom = 0, left = 0 },
    }, { list_pane(snapshot, state, ctx, false) }))
  end

  if state.toast then
    local message = ({
      call = "Opening call",
      email = "Opening email",
      message = "Opening message",
      edit = "Edit contact",
    })[state.toast] or "Done"
    ui.push(root.children, ui.row("contact-toast", {
      height = 30, gap = 10, padding = { left = 12, right = 12 },
    }, {
      ui.text("contact-toast-text", message, { size = 10, ink = "text", flex_grow = 1 }),
      ui.text("contact-toast-undo", "Undo", { size = 10, ink = "primary", width = 36 }),
    }))
  end

  return root
end

local function paint(surface, laid, id, ink, opacity, radius)
  local node = ui.find(laid, id)
  if node then
    surface:rect(id .. "-fill", node.rect.x, node.rect.y, node.rect.width, node.rect.height, ink, opacity, radius)
  end
end

function M.render(input)
  local snapshot = input or {}
  local state = read_view_state()
  apply_state(snapshot, state)
  local event = ui.event()

  if event and event.kind == "activate" then
    activate(snapshot, state, event.target_id)
    write_view_state(state)
  end

  local width, height = ui.viewport(1086, 1569)
  local theme = ui.theme()
  local surface = ui.surface(width, height, theme)
  local ctx = {
    snapshot = snapshot,
    state = state,
    viewport = { width = width, height = height },
    theme = theme,
  }
  local function build()
    return ui.layout(tree(ctx), width, height)
  end
  local laid = build()
  local wide = width >= 760

  if event and event.kind == "pointer" then
    local target = hit_target(snapshot, state, laid, event.x * width, event.y * height)
    if event.phase == "press" then
      state.pressed = target
      if target then
        activate(snapshot, state, target)
        write_view_state(state)
      end
      laid = build()
    elseif event.phase == "release" then
      state.pressed = nil
      laid = build()
    elseif event.phase == "move" then
      state.hover = target
      laid = build()
    elseif event.phase == "leave" then
      state.hover = nil
      laid = build()
    end
  end

  surface:background("background")
  paint(surface, laid, "contacts-search", "surface", 0.76, 9)
  if wide then
    paint(surface, laid, "contacts-sidebar", "surface", 0.32, 12)
    paint(surface, laid, "contacts-detail-pane", "surface", 0.24, 12)
  else
    paint(surface, laid, "contacts-detail-pane", "surface", 0.38, 12)
    paint(surface, laid, "contacts-sidebar", "surface", 0.20, 10)
  end
  paint(surface, laid, "contact-toast", "surface", 0.98, 14)

  local contacts = visible_contacts(snapshot, active_filter(snapshot, state))
  local selected, _ = selected_contact(snapshot)
  for index = 1, math.min(#contacts, 18) do
    local node = ui.find(laid, "contact-" .. index)
    if node then
      local is_selected = contacts[index].id == snapshot.selected_id
      surface:rect("contact-bg-" .. index, node.rect.x, node.rect.y, node.rect.width, node.rect.height,
        is_selected and "primary" or "surface", is_selected and 0.13 or 0.04, 8)
      local avatar = ui.find(laid, "contact-" .. index .. "-avatar")
      if avatar then
        surface:rect("contact-avatar-bg-" .. index, avatar.rect.x, avatar.rect.y, avatar.rect.width, avatar.rect.height,
          is_selected and "primary" or "surface", is_selected and 0.20 or 0.72, avatar.rect.width / 2)
      end
    end
  end

  local avatar = ui.find(laid, "contact-detail-avatar")
  if avatar then
    surface:rect("contact-detail-avatar-bg", avatar.rect.x, avatar.rect.y, avatar.rect.width, avatar.rect.height,
      "primary", 0.14, avatar.rect.width / 2)
  end

  for _, id in ipairs({
    "contact-action-message", "contact-action-call", "contact-action-email", "contact-action-edit",
  }) do
    local node = ui.find(laid, id)
    if node then
      local primary = id == "contact-action-message"
      surface:rect(id .. "-fill", node.rect.x, node.rect.y, node.rect.width, node.rect.height,
        primary and "primary" or "surface", primary and 0.82 or 0.68, 7)
    end
  end

  local selected_filter = current_filter
  for _, filter in ipairs(derive_folders(snapshot)) do
    if filter.id == current_filter then
      for _, prefix in ipairs({ "contacts-filters-", "contacts-smart-", "contacts-groups-" }) do
        local id = prefix .. (filter.id or "")
        local node = ui.find(laid, id)
        if node then
          surface:rect(id .. "-selected", node.rect.x, node.rect.y, node.rect.width, node.rect.height,
            "primary", 0.14, 7)
        end
      end
    end
  end

  if state.hover and state.hover ~= state.pressed then
    local hover = ui.find(laid, state.hover)
    if hover and hover.kind == "container" then
      surface:rect("contact-hover", hover.rect.x, hover.rect.y, hover.rect.width, hover.rect.height,
        "primary", 0.08, 7)
    end
  end
  if state.pressed then
    local pressed = ui.find(laid, state.pressed)
    if pressed and pressed.kind == "container" then
      surface:rect("contact-pressed", pressed.rect.x, pressed.rect.y, pressed.rect.width, pressed.rect.height,
        "primary", 0.22, 7)
    end
  end

  ui.paint_rules(surface, laid, "muted", 0.10)
  ui.paint_text(surface, laid, function(node)
    if node.id:find("^contacts%-filters%-") or node.id:find("^contacts%-smart%-")
      or node.id:find("^contacts%-groups%-") then
      local id = node.id:match("^contacts%-filters%-(.-)%-label$")
        or node.id:match("^contacts%-smart%-(.-)%-label$")
        or node.id:match("^contacts%-groups%-(.-)%-label$")
      return id == selected_filter and "primary" or "muted"
    end
    if node.id:find("subtitle") or node.id:find("list%-title") or node.id:find("list%-count")
      or node.id:find("role") or node.id:find("%-line$") or node.id:find("%-preview$")
      or node.id:find("label$") or node.id:find("notes%-text") then
      return "muted"
    end
    if node.id == "contacts-title" or node.id == "contact-detail-name" or node.id:find("avatar%-text") then
      return "primary"
    end
    if node.id:find("^contact%-%d+%-name$") then
      return "text"
    end
    if node.id:find("^contact%-action") then
      return "background"
    end
    if node.id == "contact-toast-undo" then return "primary" end
    return node.ink or "text"
  end)

  local hit_ids = {
    "contact-action-message", "contact-action-call", "contact-action-email",
    "contact-action-edit", "contact-toast-undo",
  }
  for _, filter in ipairs(derive_folders(snapshot)) do
    for _, prefix in ipairs({ "contacts-filters-", "contacts-smart-", "contacts-groups-" }) do
      hit_ids[#hit_ids + 1] = prefix .. (filter.id or "")
    end
  end
  for index = 1, math.min(#contacts, 18) do
    hit_ids[#hit_ids + 1] = "contact-" .. index
  end
  for _, id in ipairs(hit_ids) do
    local node = ui.find(laid, id)
    if node then surface:hit(id, node.rect) end
  end
end

return M
