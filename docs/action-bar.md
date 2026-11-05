# Action bar

`fungos.ui.action_bar` and `fungos.ui.action_button` are the standard top-level
app action surface.

```lua
local ui = require("fungos.ui")
local action = require("fungos.action")

ui.action_bar("app-actions", {
  { id = "run", label = "Run", shortcut = "ctrl+enter",
    action = action.intent("elmers.run", { workflow_id = "crm/leads" }) },
  { separator = true },
  { id = "approve", label = "Approve", confirm = true,
    action = action.intent("elmers.approve", { run_id = run.id }) },
  { id = "reject", label = "Reject", danger = true, confirm = true,
    action = action.intent("elmers.reject", { run_id = run.id }) },
  { spacer = true },
  { id = "refresh", label = "Refresh",
    action = action.intent("elmers.refresh") },
}, {
  label = "Elmers actions",
  overflow = "menu",
})
```

## Contract

The action bar is a `container` row with:

```lua
role = "toolbar"
label = string
orientation = "horizontal"
overflow = "menu" | "none"
a11y = { role = "toolbar", label = string, orientation = string }
```

An action button is a normal `ui.button` with:

```lua
role = "button"
label = string
shortcut = string?
description = string?
confirm = boolean
danger = boolean
pending = boolean
disabled = boolean
disabled_reason = string?
checked = boolean?
action = { action = string, payload = table? }?
a11y = {
  role = "button",
  label = string,
  description = string?,
  shortcut = string?,
  disabled = boolean,
  disabled_reason = string?,
  checked = boolean?,
  pending = boolean?,
}
```

## Rules

- The app owns action definitions; the host owns placement, focus, overflow,
  shortcut dispatch, confirmation UI and screen-reader output.
- A disabled action must explain `disabled_reason`.
- A destructive or externally visible action should set `confirm = true`.
- `pending = true` means the host should show progress and avoid duplicate
  submission; it does not grant or execute anything.
- The button only emits an action intent. Grants, approval, credentials and
  execution remain host-side.
- The host may expose the same action catalog over Unibus for agents, but the
  action bar itself never publishes on Unibus.

## From an action catalog

`fungos.ui.action_bar_from_catalog` projects the host/Canvas action catalog into
the same bar.

```lua
local bar = ui.action_bar_from_catalog("app-actions", snapshot.actions, {
  label = "Available actions",
})
```

Expected descriptor fields:

```lua
{
  id, label, description, shortcut,
  input_schema, requires_input,       -- Canvas JSON Schema 2020-12
  effect, idempotency, confirmation,
  available, reason,
  provider, catalog_revision, state_revision,
  phases,
}
```

- `requires_input = false` → plain click button.
- `requires_input = true` → button carries the schema; the host opens the form.
- `confirmation = "required" | "destructive"` → host confirmation gate.
- `available = false` → disabled with `reason`.
- `effect = "external"` → marked dangerous by default.

DCP catalogs map directly: `input_schema`, `phases`, provider identity and both
revisions are preserved. The action bar still emits intents only.
