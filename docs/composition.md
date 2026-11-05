# Composition

A Spore is a contribution. It may be an app, a component library, window chrome,
a rice, or a logic service. One package may contain several of these.

## Contribution kinds

```text
app        snapshot + view + actions
component  named pure UI components
chrome     window/app-shell components
rice       theme tokens, slots, assets
recipe     named slot replacements for specific apps
logic      WASM action implementation
```

A UI-only Spore has no WIT imports and no Unibus producer identity. It only has
the `fungos.ui` host API and scene output.

## Resolution order

```text
app default
  + package components/chrome
  + system components/chrome
  + user rice
  + per-app profile
  + session/view state
```

Later registrations win for the same component/slot name.

## A component Spore

```lua
-- ui/components.lua
local ui = require("fungos.ui")

local M = {}

M.name = "acme.mail-components"

M.components = {
  ["acme.thread-row"] = function(ctx, props)
    return ui.row("thread-row", {
      height = 64,
      gap = 10,
      padding = { left = 12, right = 12 },
    }, {
      ui.text("sender", props.sender, { size = 12, flex_grow = 1 }),
      ui.text("time", props.time, { size = 10, ink = "muted" }),
    })
  end,
}

M.slots = {
  ["toolbar.end"] = function(ctx)
    return ui.button("triage", "Triage", {
      action = ui.action("mail.triage"),
    })
  end,
}

M.theme = {
  radius = 12,
  accent = "mauve",
}

return M
```

## A chrome Spore

```lua
local ui = require("fungos.ui")

local M = { name = "acme.chrome" }

M.chrome = {
  window = function(ctx, props)
    return ui.column("window", {
      width = ctx.viewport.width,
      height = ctx.viewport.height,
      gap = 0,
    }, {
      ui.row("titlebar", { height = 38, padding = { left = 12, right = 12 } }, {
        ui.text("title", props.title, { size = 12 }),
      }),
      props.content,
    })
  end,
}

return M
```

## Using components in an app

```lua
local ui = require("fungos.ui")

return function view(ctx)
  return ui.column("inbox", {
    width = ctx.viewport.width,
    height = ctx.viewport.height,
    gap = 8,
  }, {
    ui.slot("toolbar.start", ui.text("mail-range", "MAIL", { size = 10 })),
    ui.slot("toolbar.end", ui.button("refresh", "Refresh")),
    ui.component("acme.thread-row", {
      id = "thread-1",
      sender = ctx.snapshot.threads[1].sender,
      time = ctx.snapshot.threads[1].time,
    }),
    ui.slot("empty_state", ui.text("empty", "No mail", { size = 13 })),
  })
end
```

## User rice

```lua
-- ~/.config/fungos/ui.lua
return {
  theme = { radius = 12 },
  apps = {
    ["dev.fungos.unibus"] = {
      hide = { "rail.tags" },
      order = { "rail.accounts", "rail.inboxes" },
      slots = {
        ["toolbar.end"] = function(ctx)
          return ui.button("triage", "Triage", {
            action = ui.action("mail.triage"),
          })
        end,
      },
    },
  },
}
```

## Rules

- A UI Spore cannot gain authority by being composed.
- Components are pure: `(ctx, props, children) -> tree`.
- Slots are pure: `(ctx, fallback_node) -> tree`.
- A missing component uses its fallback and is reported by `tend doctor`.
- An app must document the components/slots it uses and the ones it exports.
- Component names are namespaced, e.g. `dev.fungos.mail/thread-row`.
- Internal ids may change; documented stable ids may not.
