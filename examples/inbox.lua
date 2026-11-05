-- Inbox example rendered with fungos.ui.
--
-- The real Spore owns the snapshot and actions. This file only proves the SDK
-- shape: host Taffy layout, named slots, composable row component, and action
-- intents.

local ui = require("fungos.ui")
local action = require("fungos.action")

local M = {}
M.name = "example.inbox"
M.version = "0.1.0"

local function clip(value, limit)
  value = tostring(value or "")
  if #value <= limit then return value end
  return value:sub(1, limit - 1) .. "…"
end

local function selected_thread(snapshot)
  for index, thread in ipairs(snapshot.threads or {}) do
    if thread.selected or thread.id == snapshot.selected_id then return thread, index end
  end
  return (snapshot.threads or {})[1], 1
end

local function thread_row(ctx, thread, index, selected)
  local unread = thread.unread == true
  return ui.column("thread-" .. index, {
    height = 66,
    gap = 2,
    padding = { top = 9, right = 12, bottom = 7, left = 12 },
  }, {
    ui.row("thread-" .. index .. "-top", { height = 16 }, {
      ui.text("thread-" .. index .. "-sender", clip(thread.sender, 24), {
        size = 10,
        ink = unread and "text" or "muted",
        flex_grow = 1,
      }),
      ui.text("thread-" .. index .. "-time", thread.time or "", {
        size = 10,
        ink = "muted",
        width = 64,
      }),
    }),
    ui.text("thread-" .. index .. "-title", clip(thread.title, 42), {
      size = unread and 14 or 13,
      height = 19,
      ink = unread and "text" or "muted",
    }),
    ui.text("thread-" .. index .. "-preview", clip(thread.preview, 62), {
      size = 10,
      height = 14,
      ink = "muted",
    }),
  })
end

local function row_component(ctx, props)
  return thread_row(ctx, props.thread, props.index, props.selected)
end

local function rail(ctx, snapshot)
  local children = {
    ui.text("rail-accounts", "ACCOUNTS", { size = 9, height = 16, ink = "muted" }),
  }
  for index, account in ipairs(snapshot.accounts or {}) do
    ui.push(children, ui.text("rail-account-" .. index,
      clip(account.label or account.email, 16) .. "  ·  " .. tostring(account.unread or 0),
      { size = 10, height = 22, ink = account.selected and "primary" or "muted" }))
  end
  ui.push(children, ui.text("rail-inboxes", "INBOXES", { size = 9, height = 16, ink = "muted" }))
  for index, box in ipairs(snapshot.inboxes or {}) do
    ui.push(children, ui.text("rail-inbox-" .. index,
      clip(box.label or box.id, 16) .. "  ·  " .. tostring(box.unread or box.count or 0),
      { size = 10, height = 22, ink = box.selected and "primary" or "muted" }))
  end
  ui.push(children, ui.text("rail-tags", "TAGS", { size = 9, height = 16, ink = "muted" }))
  for index, tag in ipairs(snapshot.tags or {}) do
    ui.push(children, ui.text("rail-tag-" .. index,
      "#" .. clip(tag.label or tag.id, 15) .. "  ·  " .. tostring(tag.count or 0),
      { size = 10, height = 20, ink = "muted" }))
  end
  return ui.column("inbox-rail-body", { flex_grow = 1, gap = 1 }, children)
end

local function list(ctx, snapshot)
  local threads = snapshot.threads or {}
  local offset = math.max(0, math.floor(tonumber((snapshot.layout or {}).list_offset) or 0))
  local limit = math.min(14, math.max(1, math.floor(tonumber((snapshot.layout or {}).list_limit) or #threads or 1)))
  local first = math.min(#threads, offset + 1)
  local last = math.min(#threads, offset + limit)
  local range = (#threads == 0) and "0 of 0" or string.format("%d–%d of %d", first, last, #threads)
  local _, selected_index = selected_thread(snapshot)

  local children = {
    ui.row("mail-head", { height = 20 }, {
      ui.text("mail-range", "MAIL  ·  " .. range, { size = 10, ink = "muted", flex_grow = 1 }),
      ui.text("mail-sort", snapshot.sort or "Newest first", { size = 10, ink = "muted", width = 92 }),
    }),
  }

  for index = first, last do
    local thread = threads[index]
    if thread then
      local fallback = thread_row(ctx, thread, index, index == selected_index)
      ui.push(children, ui.component("dev.fungos.mail/thread-row", {
        id = "thread-" .. index,
        thread = thread,
        index = index,
        selected = index == selected_index,
      }, nil, fallback))
    end
  end

  return ui.column("mail-list", { flex_grow = 1, gap = 0 }, children)
end

local function detail(ctx, snapshot)
  local thread = selected_thread(snapshot)
  if not thread then
    return ui.slot("empty_state", ui.text("detail-empty-text", "Select a conversation", {
      size = 13,
      ink = "muted",
    }))
  end

  local actions = ui.row("detail-actions", { height = 34, gap = 8 }, {
    ui.button("detail-reply", "Reply", {
      variant = "primary",
      action = action.intent("mail.reply", { thread_id = thread.id }),
    }),
    ui.button("detail-reply-all", "Reply all", {
      action = action.intent("mail.reply_all", { thread_id = thread.id }),
    }),
    ui.button("detail-archive", "Archive", {
      action = action.intent("mail.archive", { thread_id = thread.id }),
    }),
  })

  return ui.column("detail-page", { flex_grow = 1, gap = 14 }, {
    ui.column("detail-head", { gap = 3 }, {
      ui.text("detail-title", thread.title, { size = 19, height = 25, ink = "primary" }),
      ui.text("detail-meta", (thread.sender or "") .. "  ·  " .. (thread.time or ""), {
        size = 10,
        height = 16,
        ink = "muted",
      }),
    }),
    ui.slot("detail.actions", actions),
    ui.column("detail-brief", {
      height = 188,
      gap = 5,
      padding = { top = 12, right = 13, bottom = 10, left = 13 },
    }, {
      ui.text("detail-brief-label", "AGENT BRIEF", { size = 10, height = 14, ink = "muted" }),
      ui.text("detail-brief-text", thread.brief or thread.preview or "", {
        size = 11,
        height = 132,
        wrap = true,
      }),
    }),
  })
end

local function tree(ctx)
  local snapshot = ctx.snapshot
  local count = snapshot.counts or {}
  local wide = ctx.viewport.width >= 700
  local root = ui.column("inbox-root", {
    width = ctx.viewport.width,
    height = ctx.viewport.height,
    gap = 8,
    padding = { top = 12, right = 22, bottom = 18, left = 22 },
  }, {
    ui.row("inbox-toolbar", { height = 22 }, {
      ui.slot("toolbar.start", ui.text("inbox-account",
        (snapshot.account and (snapshot.account.email .. "  ·  " .. (snapshot.account.sync or ""))) or "",
        { size = 10, ink = "muted", flex_grow = 1 })),
      ui.slot("toolbar.end", ui.text("inbox-counts",
        string.format("%d unread  ·  %d attention", count.unread or 0, count.urgent or 0),
        { size = 10, ink = "muted", width = 200 })),
    }),
    ui.column("inbox-search", { height = 36, padding = { left = 12, right = 12, top = 10 } }, {
      ui.text("inbox-search-text", "⌕  Search mail, people, tags", { size = 10, ink = "muted" }),
    }),
  })

  if wide then
    ui.push(root.children, ui.row("inbox-main", { flex_grow = 1, gap = 16 }, {
      ui.column("inbox-rail", {
        width = 150,
        flex_shrink = 0,
        padding = { top = 8, right = 8, bottom = 8, left = 8 },
      }, { rail(ctx, snapshot) }),
      ui.column("inbox-list-pane", {
        width = 340,
        flex_shrink = 0,
        padding = { top = 8, right = 10, bottom = 8, left = 10 },
      }, { list(ctx, snapshot) }),
      ui.column("inbox-detail-pane", {
        flex_grow = 1,
        padding = { top = 10, right = 18, bottom = 10, left = 18 },
      }, { detail(ctx, snapshot) }),
    }))
  else
    ui.push(root.children, ui.column("inbox-main", { flex_grow = 1 }, { list(ctx, snapshot) }))
  end

  return root
end

local function apply_event(snapshot)
  local event = ui.event()
  if not event or event.kind ~= "activate" then return snapshot end
  local index = tonumber((event.target_id or ""):match("^thread%-(%d+)$"))
  if index and (snapshot.threads or {})[index] then
    snapshot.selected_id = snapshot.threads[index].id
    for _, thread in ipairs(snapshot.threads or {}) do
      thread.selected = thread.id == snapshot.selected_id
    end
  end
  return snapshot
end

function M.render(snapshot)
  snapshot = apply_event(snapshot or {})
  local width, height = ui.viewport(1086, 1569)
  local theme = ui.theme()
  local surface = ui.surface(width, height, theme)
  local ctx = { snapshot = snapshot, viewport = { width = width, height = height }, theme = theme }
  local laid = ui.layout(tree(ctx), width, height)
  local wide = width >= 700

  surface:background("background")
  local search = ui.find(laid, "inbox-search")
  if search then surface:rect("inbox-search-bg", search.rect.x, search.rect.y, search.rect.width, search.rect.height, "surface", 0.72, 8) end
  if wide then
    for _, id in ipairs({ "inbox-rail", "inbox-list-pane", "inbox-detail-pane" }) do
      local pane = ui.find(laid, id)
      if pane then
        surface:rect(id .. "-bg", pane.rect.x, pane.rect.y, pane.rect.width, pane.rect.height, "surface", 0.28, 10)
      end
    end
  end

  local _, selected_index = selected_thread(snapshot)
  local selected = ui.find(laid, "thread-" .. tostring(selected_index))
  if selected then
    surface:rect("thread-selected", selected.rect.x, selected.rect.y, selected.rect.width, selected.rect.height, "primary", 0.14, 7)
  end

  ui.paint_rules(surface, laid, "muted", 0.08)
  ui.paint_text(surface, laid, function(node)
    if node.id:find("account") or node.id:find("range") or node.id:find("sort")
      or node.id:find("meta") or node.id:find("brief%-label") or node.id:find("%-preview$")
      or node.id:find("^rail%-") then return "muted" end
    if node.id == "detail-title" then return "primary" end
    if node.id == "detail-reply-label" then return "background" end
    return node.ink or "text"
  end)

  if wide then
    for index = 1, math.min(#(snapshot.threads or {}), 14) do
      local row = ui.find(laid, "thread-" .. index)
      if row then surface:hit("thread-" .. index, row.rect) end
    end
  end
end

return M
