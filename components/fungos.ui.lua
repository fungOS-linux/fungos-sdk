-- fungos.ui — initial shared Spore UI component package.
--
-- Pure components: (ctx, props, children) -> semantic tree. No records, no
-- network, no authority. Pass a stable `id` when a component appears more than
-- once in a tree.
--
--   --component components/fungos.ui.lua
--
-- Exports:
--   fungos.ui/button
--   fungos.ui/badge
--   fungos.ui/avatar
--   fungos.ui/field
--   fungos.ui/card
--   fungos.ui/empty
--   fungos.ui/list-row

local ui = require("fungos.ui")

local M = {
  name = "fungos.ui",
  version = "0.1.0",
  theme = {},
}

local function id_of(kind, props)
  return (props and props.id) or ("fungos.ui/" .. kind)
end

M.components = {
  ["fungos.ui/button"] = function(_, props)
    props = props or {}
    return ui.action_button(id_of("button", props), props.label or "Button", {
      variant = props.variant,
      action = props.action,
      disabled = props.disabled,
      disabled_reason = props.disabled_reason,
      description = props.description,
      shortcut = props.shortcut,
      confirm = props.confirm,
      danger = props.danger,
      pending = props.pending,
      width = props.width,
      flex_grow = props.flex_grow,
      size = props.size,
      height = props.height,
    })
  end,

  ["fungos.ui/badge"] = function(_, props)
    props = props or {}
    return ui.badge(id_of("badge", props), props.label or "", {
      size = props.size,
      ink = props.ink,
      height = props.height,
    })
  end,

  ["fungos.ui/avatar"] = function(_, props)
    props = props or {}
    return ui.avatar(id_of("avatar", props), props.initials or props.label or "?", {
      size = props.size,
      text_size = props.text_size,
      ink = props.ink,
    })
  end,

  ["fungos.ui/field"] = function(_, props)
    props = props or {}
    local id = id_of("field", props)
    return ui.column(id, { gap = 4, flex_grow = props.flex_grow }, {
      ui.text(id .. "-label", props.label or "Field", {
        size = props.label_size or 10,
        height = 16,
        ink = "muted",
      }),
      ui.text_input(id .. "-input", props.value or "", {
        label = props.label,
        placeholder = props.placeholder,
        action = props.action,
        read_only = props.read_only,
        multiline = props.multiline,
        expected_version = props.expected_version,
        height = props.height,
        flex_grow = props.flex_grow and 1 or nil,
      }),
    })
  end,

  ["fungos.ui/card"] = function(_, props, children)
    props = props or {}
    local id = id_of("card", props)
    local body = {
      ui.text(id .. "-title", props.title or "", {
        size = props.title_size or 13,
        height = props.title_size and (props.title_size + 6) or 20,
        ink = props.title_ink or "primary",
        wrap = true,
      }),
    }
    if props.detail and props.detail ~= "" then
      body[#body + 1] = ui.text(id .. "-detail", props.detail, {
        size = props.detail_size or 10,
        ink = "muted",
        wrap = true,
      })
    end
    for _, child in ipairs(children or {}) do body[#body + 1] = child end
    return ui.column(id, {
      gap = props.gap or 6,
      padding = props.padding or { left = 12, right = 12, top = 10, bottom = 10 },
      width = props.width,
      flex_grow = props.flex_grow,
    }, body)
  end,

  ["fungos.ui/empty"] = function(_, props)
    props = props or {}
    return ui.empty_state(id_of("empty", props), props.title or "Nothing here", props.detail or "", {
      title_size = props.title_size,
      detail_size = props.detail_size,
    })
  end,

  ["fungos.ui/list-row"] = function(_, props, children)
    props = props or {}
    local id = id_of("list-row", props)
    local body = {
      ui.avatar(id .. "-avatar", props.initials or "?", {
        size = props.avatar_size or 32,
        ink = props.avatar_ink,
      }),
      ui.column(id .. "-body", { gap = 2, flex_grow = 1 }, {
        ui.text(id .. "-title", props.title or "", {
          size = props.title_size or 12,
          ink = "text",
          wrap = false,
        }),
        ui.text(id .. "-subtitle", props.subtitle or "", {
          size = props.subtitle_size or 10,
          ink = "muted",
          wrap = false,
        }),
      }),
    }
    if props.meta and props.meta ~= "" then
      body[#body + 1] = ui.text(id .. "-meta", props.meta, {
        size = 9,
        ink = "muted",
        width = props.meta_width,
      })
    end
    for _, child in ipairs(children or {}) do body[#body + 1] = child end
    local row = ui.list_row(id, {
      selected = props.selected,
      disabled = props.disabled,
      height = props.height,
      min_height = props.min_height,
      auto_height = props.auto_height,
      gap = props.gap,
      width = props.width,
      flex_grow = props.flex_grow,
    }, body)
    row.action = props.action
    return row
  end,
}

return M
