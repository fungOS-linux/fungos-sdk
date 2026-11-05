-- Superhuman-shaped inbox prototype on fungos.ui.
--
-- This is still a pure projection. It is intentionally denser and more
-- keyboard-first than the first inbox view:
--
--   split inbox rail · command bar · triage list · reading pane
--   AI brief · messages · composer · shortcut footer · undo affordance
--
-- Actions are intents. The live Spore/Unibus router decides what they mean.

local ui = require("fungos.ui")
local action = require("fungos.action")

local M = {}
M.name = "example.inbox-superhuman"
M.version = "0.1.0"

local function clip(value, limit)
  return ui.clip(value, limit)
end

local function selected_thread(snapshot)
  for index, thread in ipairs(snapshot.threads or {}) do
    if thread.selected or thread.id == snapshot.selected_id then return thread, index end
  end
  return (snapshot.threads or {})[1], 1
end

local function initials(name)
  name = tostring(name or "?")
  local a, b = name:match("(%S+)%s+(%S+)")
  if a and b then return (a:sub(1, 1) .. b:sub(1, 1)):upper() end
  return name:sub(1, 1):upper()
end

local function pane(workspace, id)
  for _, item in ipairs((workspace and workspace.panes) or {}) do
    if item.id == id then return item end
  end
end

local function nav(snapshot)
  local workspace = snapshot.workspace or {}
  local sidebar = workspace.sidebar or {}
  local children = {
    ui.text("rail-account", sidebar.account or (snapshot.account and snapshot.account.email) or "Inbox", {
      size = 10, height = 18, ink = "muted",
    }),
  }

  local groups = sidebar.groups
  if groups and #groups > 0 then
    for group_index, group in ipairs(groups) do
      local items = {}
      for _, item in ipairs(group.items or {}) do
        items[#items + 1] = {
          id = item.id,
          label = item.label or item.id,
          count = item.count,
          selected = item.selected,
          action = action.intent("nav.activate", {
            group = group.id,
            item = item.id,
          }),
        }
      end
      ui.push(children, ui.sidebar_group("rail-group-" .. group_index, group.label or "", items, {
        size = 10,
        height = 26,
      }))
    end
  else
    ui.push(children, ui.section_label("rail-split-label", "SPLIT"))
    for index, item in ipairs(snapshot.splits or {}) do
      ui.push(children, ui.list_row("split-" .. index, {
        height = 30,
        padding = { left = 8, right = 8 },
        selected = item.selected == true,
      }, {
        ui.text("split-" .. index .. "-name", item.label, {
          size = 11,
          ink = item.selected and "primary" or "text",
          flex_grow = 1,
        }),
        ui.text("split-" .. index .. "-count", tostring(item.count or ""), {
          size = 10,
          ink = item.selected and "primary" or "muted",
          width = 28,
        }),
      }))
    end
    ui.push(children, ui.section_label("rail-labels-label", "LABELS"))
    for index, item in ipairs(snapshot.labels or {}) do
      ui.push(children, ui.list_row("label-" .. index, {
        height = 25,
        padding = { left = 8, right = 8 },
      }, {
        ui.text("label-" .. index .. "-name", "#" .. (item.label or item.id), {
          size = 10, ink = "muted", flex_grow = 1,
        }),
        ui.text("label-" .. index .. "-count", tostring(item.count or ""), {
          size = 9, ink = "muted", width = 24,
        }),
      }))
    end
  end

  ui.push(children, ui.spacer("rail-spacer", { flex_grow = 1 }))
  ui.push(children, ui.slot("inbox.rail.footer", ui.column("rail-footer", { gap = 2 }, {
    ui.text("rail-zero", string.format("%d to zero", snapshot.remaining or 0), {
      size = 11, ink = "primary", height = 18,
    }),
    ui.text("rail-sync", (snapshot.account and snapshot.account.sync or "") .. "  ·  synced", {
      size = 9, ink = "muted", height = 14,
    }),
  })))
  return ui.column("inbox-rail-body", { flex_grow = 1, gap = 1 }, children)
end

local function row(thread, index, selected)
  local unread = thread.unread == true
  local important = thread.important == true
  local tag_children = {}
  if important then
    tag_children[#tag_children + 1] = ui.badge("thread-" .. index .. "-important", "IMPORTANT", {
      size = 8, ink = "primary",
    })
  end
  tag_children[#tag_children + 1] = ui.text("thread-" .. index .. "-preview", clip(thread.preview, 36), {
    size = 10, ink = "muted", flex_grow = 1,
  })
  return ui.list_row("thread-" .. index, {
    height = 68,
    selected = selected,
    unread = unread,
    gap = 10,
  }, {
    ui.avatar("thread-" .. index .. "-avatar", initials(thread.sender), {
      size = 32,
      ink = selected and "primary" or "muted",
    }),
    ui.column("thread-" .. index .. "-body", { flex_grow = 1, gap = 2 }, {
      ui.row("thread-" .. index .. "-top", { height = 17 }, {
        ui.text("thread-" .. index .. "-sender", clip(thread.sender, 20), {
          size = 11,
          ink = unread and "text" or "muted",
          flex_grow = 1,
        }),
        ui.text("thread-" .. index .. "-time", thread.time or "", {
          size = 9,
          ink = "muted",
          width = 42,
        }),
      }),
      ui.text("thread-" .. index .. "-title", clip(thread.title, 31), {
        size = unread and 14 or 13,
        height = 19,
        ink = unread and "text" or "muted",
      }),
      ui.row("thread-" .. index .. "-tags", { height = 16, gap = 4 }, tag_children),
    }),
  })
end

local function list(ctx)
  local snapshot = ctx.snapshot
  local workspace = snapshot.workspace or {}
  local list_pane = pane(workspace, "list")
  local tabs = (list_pane and list_pane.tabs) or {}
  local active = nil
  for _, tab in ipairs(tabs) do
    if tab.selected or tab.id == list_pane.active_tab then active = tab end
  end
  local threads = snapshot.threads or {}
  local offset = math.max(0, math.floor(tonumber((snapshot.layout or {}).list_offset) or 0))
  local limit = math.min(12, math.max(1, math.floor(tonumber((snapshot.layout or {}).list_limit) or #threads or 1)))
  local first = math.min(#threads, offset + 1)
  local last = math.min(#threads, offset + limit)
  local _, selected_index = selected_thread(snapshot)

  local tab_nodes = {}
  for _, tab in ipairs(tabs) do
    tab_nodes[#tab_nodes + 1] = {
      id = tab.id,
      label = tab.label,
      unread = tab.unread,
      selected = tab.selected or tab.id == list_pane.active_tab,
      action = action.intent("tab.activate", { pane_id = "list", tab_id = tab.id }),
    }
  end

  local header
  if #tab_nodes > 0 then
    header = ui.tabbar("list-tabs", tab_nodes, { height = 26, gap = 2 })
  else
    header = ui.row("list-filter", {
      height = 24, gap = 10, padding = { left = 2, right = 2 },
    }, {
      ui.text("list-filter-all", "All", { size = 10, ink = "primary", width = 32 }),
      ui.text("list-filter-unread", "Unread", { size = 10, ink = "muted", width = 52 }),
      ui.text("list-filter-attention", "Attention", { size = 10, ink = "muted", width = 68 }),
    })
  end

  local children = {
    ui.command_bar("inbox-command", {
      placeholder = "Search or run a command",
      query = snapshot.search,
      hint = "⌘K",
      size = 11,
      height = 38,
    }),
    ui.row("list-head", { height = 30, padding = { left = 4, right = 4 } }, {
      ui.text("list-title", (active and active.label) or snapshot.title or "Important", {
        size = 16, ink = "primary", flex_grow = 1,
      }),
      ui.text("list-remaining", string.format("%d left", snapshot.remaining or 0), {
        size = 10, ink = "muted", width = 52,
      }),
    }),
    ui.slot("inbox.list.header", header),
  }

  local group = snapshot.group or "TODAY"
  ui.push(children, ui.section_label("list-group", group))
  for index = first, last do
    local thread = threads[index]
    if thread then
      ui.push(children, row(thread, index, index == selected_index))
    end
  end
  if #threads == 0 then
    ui.push(children, ui.empty_state("list-empty", "Inbox zero", "Nothing needs you right now.", {
      title_size = 15, detail_size = 11, detail_height = 28,
    }))
  end

  return ui.column("mail-list", {
    flex_grow = 1,
    gap = 2,
    padding = { top = 8, right = 8, bottom = 8, left = 8 },
  }, children)
end

local function action_bar(thread)
  return ui.row("detail-actions", { height = 32, gap = 6 }, {
    ui.button("detail-reply", "Reply", {
      variant = "primary",
      size = 11,
      height = 30,
      action = action.intent("mail.reply", { thread_id = thread.id }),
    }),
    ui.button("detail-reply-all", "Reply all", {
      size = 11,
      height = 30,
      action = action.intent("mail.reply_all", { thread_id = thread.id }),
    }),
    ui.button("detail-archive", "Archive", {
      size = 11,
      height = 30,
      action = action.intent("mail.archive", { thread_id = thread.id }),
    }),
    ui.spacer("detail-actions-spacer", { flex_grow = 1 }),
    ui.kbd("detail-kbd-e", "E", { width = 18 }),
    ui.kbd("detail-kbd-u", "U", { width = 18 }),
    ui.kbd("detail-kbd-r", "R", { width = 18 }),
  })
end

local function message_card(message, index)
  return ui.column("message-" .. index, {
    gap = 4,
    padding = { top = 10, right = 12, bottom = 10, left = 12 },
  }, {
    ui.row("message-" .. index .. "-head", { height = 16 }, {
      ui.text("message-" .. index .. "-from", clip(message.from, 34), {
        size = 11, ink = "text", flex_grow = 1,
      }),
      ui.text("message-" .. index .. "-time", message.time or "", {
        size = 9, ink = "muted", width = 42,
      }),
    }),
    ui.text("message-" .. index .. "-body", message.preview or "", {
      size = 11, ink = "text", wrap = true, height = 42,
    }),
  })
end

local function detail(ctx)
  local thread = selected_thread(ctx.snapshot)
  if not thread then
    return ui.slot("empty_state", ui.empty_state("detail-empty", "Select a conversation", "j/k to move.", {
      title_size = 15, detail_size = 11, detail_height = 24,
    }))
  end

  local children = {
    ui.row("detail-top", { height = 30, gap = 8 }, {
      ui.text("detail-kicker", "CONVERSATION  ·  " .. (thread.status or "open"), {
        size = 9, ink = "muted", flex_grow = 1,
      }),
      ui.text("detail-position", "1 / " .. tostring(#(ctx.snapshot.threads or {})), {
        size = 9, ink = "muted", width = 42,
      }),
    }),
    ui.slot("detail.actions", action_bar(thread)),
    ui.column("detail-title-block", { gap = 5, height = 62 }, {
      ui.text("detail-title", thread.title, {
        size = 22, height = 30, ink = "primary",
      }),
      ui.row("detail-meta", { height = 18, gap = 6 }, {
        ui.text("detail-sender", thread.sender or "", { size = 11, ink = "text", flex_grow = 1 }),
        ui.text("detail-time", thread.time or "", { size = 10, ink = "muted", width = 44 }),
      }),
    }),
    ui.column("detail-brief", {
      gap = 5,
      padding = { top = 12, right = 14, bottom = 12, left = 14 },
    }, {
      ui.row("detail-brief-head", { height = 16 }, {
        ui.text("detail-brief-label", "WHY THIS MATTERS", {
          size = 9, ink = "primary", flex_grow = 1,
        }),
        ui.badge("detail-brief-badge", "AI", { size = 8, ink = "primary" }),
      }),
      ui.text("detail-brief-text", thread.brief or thread.preview or "", {
        size = 11, wrap = true, height = 70,
      }),
      ui.row("detail-brief-actions", { height = 26, gap = 8 }, {
        ui.text("detail-brief-draft", "Draft reply", { size = 10, ink = "primary", width = 66 }),
        ui.text("detail-brief-remind", "Remind me", { size = 10, ink = "muted", width = 60 }),
        ui.text("detail-brief-later", "Later", { size = 10, ink = "muted", width = 40 }),
      }),
    }),
    ui.slot("detail.before_messages", nil),
  }

  local messages = thread.messages or {}
  for index, message in ipairs(messages) do
    children[#children + 1] = message_card(message, index)
  end

  ui.push(children, ui.column("composer", {
    gap = 6,
    padding = { top = 10, right = 12, bottom = 10, left = 12 },
  }, {
    ui.row("composer-head", { height = 18 }, {
      ui.text("composer-label", "REPLY", { size = 9, ink = "muted", flex_grow = 1 }),
      ui.text("composer-tone", "Friendly  ·  concise", { size = 9, ink = "muted", width = 120 }),
    }),
    ui.text("composer-draft", thread.draft or "Write a reply…", {
      size = 11, ink = thread.draft and "text" or "muted", wrap = true, height = 42,
    }),
    ui.row("composer-actions", { height = 28, gap = 8 }, {
      ui.button("composer-send", "Send", {
        size = 11, height = 26, variant = "primary",
        action = action.intent("mail.reply.send", { thread_id = thread.id }),
      }),
      ui.button("composer-approve", "Approve draft", {
        size = 10, height = 26,
        action = action.intent("mail.reply.approve", { thread_id = thread.id }),
      }),
      ui.spacer("composer-spacer", { flex_grow = 1 }),
      ui.text("composer-hint", "⌘↵ send", { size = 9, ink = "muted", width = 54 }),
    }),
  }))

  return ui.column("detail-page", { flex_grow = 1, gap = 10 }, children)
end

local function tree(ctx)
  local snapshot = ctx.snapshot
  local wide = ctx.viewport.width >= 980
  local workspace = snapshot.workspace or {}
  local focus = workspace.focus or "list"
  local root = ui.workspace("inbox-root", {
    width = ctx.viewport.width,
    height = ctx.viewport.height,
    gap = 0,
    padding = { top = 0, right = 0, bottom = 0, left = 0 },
  }, {
    ui.row("inbox-body", { flex_grow = 1, gap = 0 }, {
      ui.sidebar("inbox-rail", {
        width = wide and 190 or 150,
        flex_shrink = 0,
        gap = 1,
        padding = { top = 14, right = 10, bottom = 12, left = 12 },
      }, { nav(snapshot) }),
      ui.pane("inbox-list-pane", {
        pane_id = "list",
        width = wide and 366 or 310,
        flex_grow = 0,
        flex_shrink = 0,
        focused = focus == "list",
        gap = 2,
        padding = { top = 10, right = 8, bottom = 8, left = 8 },
      }, { list(ctx) }),
      ui.pane("inbox-detail-pane", {
        pane_id = "detail",
        flex_grow = 1,
        min_width = 0,
        focused = focus == "detail",
        gap = 8,
        padding = { top = 12, right = 18, bottom = 12, left = 18 },
      }, { detail(ctx) }),
    }),
    ui.row("inbox-status", {
      height = 30,
      gap = 10,
      padding = { left = 14, right = 14 },
      align_items = "center",
    }, {
      ui.text("status-keys", "j/k move   e archive   u unread   r reply   ⌘k command", {
        size = 9, ink = "muted", flex_grow = 1,
      }),
      ui.text("status-account", snapshot.account and snapshot.account.email or "", {
        size = 9, ink = "muted", width = 190,
      }),
    }),
  })
  if wide and ctx.state.toast then
    local message = ({
      archive = "Archived 1 thread",
      sent = "Reply sent",
      draft = "Draft ready",
    })[ctx.state.toast] or "Done"
    ui.push(root.children, ui.slot("inbox.toast", ui.row("toast", {
      height = 30, gap = 10, padding = { left = 12, right = 12 },
    }, {
      ui.text("toast-text", message, { size = 10, ink = "text", flex_grow = 1 }),
      ui.text("toast-undo", "Undo", { size = 10, ink = "primary", width = 36 }),
    })))
  end
  return root
end

local function paint(surface, laid, id, ink, opacity, radius)
  local node = ui.find(laid, id)
  if node then
    surface:rect(id .. "-fill", node.rect.x, node.rect.y, node.rect.width, node.rect.height, ink, opacity, radius)
  end
end

local function read_view_state()
  local module = rawget(_G, "module")
  local raw = module and module.view and module.view.selected
  local state = {}
  if type(raw) ~= "string" then return state end
  if raw:sub(1, 2) ~= "v1" then
    state.thread = raw
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
  for _, key in ipairs({ "thread", "tab", "nav", "toast" }) do
    local value = state[key]
    if value and value ~= "" and not value:find("[;=]") then
      parts[#parts + 1] = key .. "=" .. value
    end
  end
  local raw = table.concat(parts, ";")
  if #raw <= 128 then pcall(module.select, raw) end
end

local function apply_state(snapshot, state)
  local threads = snapshot.threads or {}
  if state.thread then
    for _, thread in ipairs(threads) do
      if thread.id == state.thread then
        snapshot.selected_id = thread.id
      end
      thread.selected = thread.id == snapshot.selected_id
    end
  end
  local workspace = snapshot.workspace or {}
  local list_pane = pane(workspace, "list")
  if list_pane and state.tab then
    list_pane.active_tab = state.tab
    for _, tab in ipairs(list_pane.tabs or {}) do
      tab.selected = tab.id == state.tab
    end
  end
  if state.nav then
    local group_id, item_id = state.nav:match("^(.-):(.+)$")
    for _, group in ipairs((workspace.sidebar and workspace.sidebar.groups) or {}) do
      if group.id == group_id then
        for _, item in ipairs(group.items or {}) do
          item.selected = item.id == item_id
        end
      end
    end
  end
end

local function activate(snapshot, state, target)
  target = tostring(target or "")
  local threads = snapshot.threads or {}
  local index = tonumber(target:match("^thread%-(%d+)$"))
  if index and threads[index] then
    state.thread = threads[index].id
    apply_state(snapshot, state)
    return
  end
  local tab_id = target:match("^list%-tabs%-(.+)$")
  if tab_id then
    state.tab = tab_id
    apply_state(snapshot, state)
    return
  end
  local group_index, item_id = target:match("^rail%-group%-(%d+)%-(.+)$")
  if group_index and item_id then
    local workspace = snapshot.workspace or {}
    local group = ((workspace.sidebar and workspace.sidebar.groups) or {})[tonumber(group_index)]
    if group then
      state.nav = group.id .. ":" .. item_id
      apply_state(snapshot, state)
    end
    return
  end
  if target == "detail-archive" then
    state.toast = "archive"
  elseif target == "composer-send" then
    state.toast = "sent"
  elseif target == "toast-undo" then
    state.toast = nil
  end
end

local function inside(rect, x, y)
  return x >= rect.x and y >= rect.y and x <= rect.x + rect.width and y <= rect.y + rect.height
end

local function hit_target(snapshot, laid, x, y)
  local function hit(id)
    local node = ui.find(laid, id)
    return node and inside(node.rect, x, y)
  end
  for _, id in ipairs({
    "detail-reply", "detail-reply-all", "detail-archive",
    "composer-send", "composer-approve", "toast-undo",
  }) do
    if hit(id) then return id end
  end
  local workspace = snapshot.workspace or {}
  local list_pane = pane(workspace, "list")
  for _, tab in ipairs((list_pane and list_pane.tabs) or {}) do
    local id = "list-tabs-" .. (tab.id or "")
    if hit(id) then return id end
  end
  for group_index, group in ipairs((workspace.sidebar and workspace.sidebar.groups) or {}) do
    for _, item in ipairs(group.items or {}) do
      local id = "rail-group-" .. group_index .. "-" .. (item.id or "")
      if hit(id) then return id end
    end
  end
  for index = 1, #(snapshot.threads or {}) do
    if hit("thread-" .. index) then return "thread-" .. index end
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
  elseif event and event.kind == "key" then
    local threads = snapshot.threads or {}
    local _, current = selected_thread(snapshot)
    local next_index = current
    if event.key == "j" or event.key == "down" then next_index = math.min(#threads, current + 1) end
    if event.key == "k" or event.key == "up" then next_index = math.max(1, current - 1) end
    if threads[next_index] then
      state.thread = threads[next_index].id
      apply_state(snapshot, state)
      write_view_state(state)
    end
  end

  local width, height = ui.viewport(1200, 900)
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
  local wide = width >= 980

  if event and event.kind == "pointer" then
    local target = hit_target(snapshot, laid, event.x * width, event.y * height)
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
  paint(surface, laid, "inbox-rail", "surface", 0.22, 0)
  paint(surface, laid, "inbox-list-pane", "surface", 0.30, 0)
  paint(surface, laid, "inbox-detail-pane", "surface", 0.24, 0)

  local workspace = snapshot.workspace or {}
  local list_pane = pane(workspace, "list")
  local selected_ids = {}
  local focus = workspace.focus or "list"
  local selected_thread_value, selected_index = selected_thread(snapshot)
  for _, entry in ipairs({
    { pane = "inbox-list-pane", id = "list" },
    { pane = "inbox-detail-pane", id = "detail" },
  }) do
    local node = ui.find(laid, entry.pane)
    if node and focus == entry.id then
      local r = node.rect
      surface:rect(entry.pane .. "-focus-top", r.x, r.y, r.width, 1.5, "primary", 0.45, 0)
      surface:rect(entry.pane .. "-focus-bottom", r.x, r.y + r.height - 1.5, r.width, 1.5, "primary", 0.45, 0)
      surface:rect(entry.pane .. "-focus-left", r.x, r.y, 1.5, r.height, "primary", 0.45, 0)
      surface:rect(entry.pane .. "-focus-right", r.x + r.width - 1.5, r.y, 1.5, r.height, "primary", 0.45, 0)
    end
  end

  for group_index, group in ipairs((workspace.sidebar and workspace.sidebar.groups) or {}) do
    for _, item in ipairs(group.items or {}) do
      local id = "rail-group-" .. group_index .. "-" .. (item.id or "")
      if item.selected then
        selected_ids[id] = true
        local node = ui.find(laid, id)
        if node then
          surface:rect(id .. "-selected", node.rect.x, node.rect.y, node.rect.width, node.rect.height, "primary", 0.12, 7)
        end
      end
    end
  end

  for _, tab in ipairs((list_pane and list_pane.tabs) or {}) do
    local id = "list-tabs-" .. (tab.id or "")
    if tab.selected or (list_pane and tab.id == list_pane.active_tab) then
      selected_ids[id] = true
      local node = ui.find(laid, id)
      if node then
        surface:rect(id .. "-selected", node.rect.x, node.rect.y, node.rect.width, node.rect.height, "primary", 0.14, 7)
      end
    end
  end
  paint(surface, laid, "inbox-command", "surface", 0.72, 9)
  paint(surface, laid, "detail-brief", "primary", 0.08, 10)
  paint(surface, laid, "composer", "surface", 0.66, 10)
  paint(surface, laid, "inbox-status", "surface", 0.46, 0)
  paint(surface, laid, "toast", "surface", 0.98, 14)

  for index = 1, math.min(#(snapshot.threads or {}), 12) do
    local node = ui.find(laid, "thread-" .. index)
    if node then
      local selected = index == selected_index
      surface:rect("thread-bg-" .. index, node.rect.x, node.rect.y, node.rect.width, node.rect.height,
        selected and "primary" or "surface", selected and 0.15 or 0.05, 8)
      local avatar = ui.find(laid, "thread-" .. index .. "-avatar")
      if avatar then
        surface:rect("avatar-bg-" .. index, avatar.rect.x, avatar.rect.y, avatar.rect.width, avatar.rect.height,
          selected and "primary" or "surface", selected and 0.20 or 0.70, avatar.rect.width / 2)
      end
      local important = ui.find(laid, "thread-" .. index .. "-important")
      if important then
        surface:rect("important-bg-" .. index, important.rect.x, important.rect.y, important.rect.width, important.rect.height,
          "primary", 0.12, 4)
      end
      if index < math.min(#(snapshot.threads or {}), 12) then
        surface:rect("thread-rule-" .. index, node.rect.x + 10, node.rect.y + node.rect.height - 1,
          node.rect.width - 20, 1, "muted", 0.08, 0)
      end
    end
  end

  for index = 1, #(snapshot.threads or {}) do
    local message = ui.find(laid, "message-" .. index)
    if message then
      surface:rect("message-bg-" .. index, message.rect.x, message.rect.y, message.rect.width, message.rect.height,
        "surface", 0.36, 9)
    end
  end

  for _, id in ipairs({
    "detail-reply", "detail-reply-all", "detail-archive",
    "composer-send", "composer-approve",
  }) do
    local node = ui.find(laid, id)
    if node then
      local primary = id == "detail-reply" or id == "composer-send"
      surface:rect(id .. "-fill", node.rect.x, node.rect.y, node.rect.width, node.rect.height,
        primary and "primary" or "surface", primary and 0.82 or 0.72, 7)
    end
  end

  local selected_row = ui.find(laid, "thread-" .. tostring(selected_index))
  if selected_row then
    surface:rect("thread-selected", selected_row.rect.x, selected_row.rect.y,
      selected_row.rect.width, selected_row.rect.height, "primary", 0.15, 8)
  end

  if state.hover and state.hover ~= state.pressed then
    local hover = ui.find(laid, state.hover)
    if hover and hover.kind == "container" then
      surface:rect("hover", hover.rect.x, hover.rect.y,
        hover.rect.width, hover.rect.height, "primary", 0.08, 7)
    end
  end

  if state.pressed then
    local pressed = ui.find(laid, state.pressed)
    if pressed and pressed.kind == "container" then
      surface:rect("pressed", pressed.rect.x, pressed.rect.y,
        pressed.rect.width, pressed.rect.height, "primary", 0.22, 7)
    end
  end

  ui.paint_rules(surface, laid, "muted", 0.10)
  ui.paint_text(surface, laid, function(node)
    if selected_ids[node.id .. "-label"] then return "primary" end
    if node.id:find("^rail%-group") then
      return node.id:find("%-label$") and "text" or "muted"
    end
    if node.id:find("^split%-") or node.id:find("^label%-") then
      return node.id:find("name$") and "text" or "muted"
    end
    if node.id:find("sender") or node.id:find("title") or node.id:find("preview")
      or node.id:find("meta") or node.id:find("kicker") or node.id:find("position")
      or node.id:find("group") or node.id:find("remaining") or node.id:find("label")
      or node.id:find("time") or node.id:find("role") or node.id:find("hint") then
      return "muted"
    end
    if node.id == "detail-title" or node.id == "list-title" or node.id == "detail-brief-label"
      or node.id == "composer-label" or node.id == "toast-undo" or node.id == "rail-zero" then
      return "primary"
    end
    if node.id:find("^detail%-reply") or node.id:find("^detail%-archive")
      or node.id:find("^composer%-send") or node.id:find("^composer%-approve") then
      return "background"
    end
    if node.id:find("^thread%-%d+%-title$") or node.id:find("^thread%-%d+%-sender$") then
      return "text"
    end
    return node.ink or "text"
  end)

  local hit_ids = {
    "detail-reply", "detail-reply-all", "detail-archive",
    "composer-send", "composer-approve", "toast-undo",
  }
  for _, tab in ipairs((list_pane and list_pane.tabs) or {}) do
    hit_ids[#hit_ids + 1] = "list-tabs-" .. (tab.id or "")
  end
  for group_index, group in ipairs((workspace.sidebar and workspace.sidebar.groups) or {}) do
    for _, item in ipairs(group.items or {}) do
      hit_ids[#hit_ids + 1] = "rail-group-" .. group_index .. "-" .. (item.id or "")
    end
  end
  for index = 1, math.min(#(snapshot.threads or {}), 12) do
    hit_ids[#hit_ids + 1] = "thread-" .. index
  end
  for _, id in ipairs(hit_ids) do
    local node = ui.find(laid, id)
    if node then surface:hit(id, node.rect) end
  end
end

return M
