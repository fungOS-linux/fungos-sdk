# Shared UI components

Status: **initial library, 2026-11-06.**

`components/fungos.ui.lua` is the first shared component package.

```text
fungos.ui/button
fungos.ui/badge
fungos.ui/avatar
fungos.ui/field
fungos.ui/card
fungos.ui/empty
fungos.ui/list-row
```

Use with `tend`:

```sh
tend build examples/components/demo.lua examples/components/snapshot.lua \
  --component components/fungos.ui.lua \
  --name components-demo \
  --out /tmp/tend-build
```

A component is pure:

```text
(ctx, props, children) -> semantic UiNode
```

No records, network, filesystem, clock or authority. Pass a stable `id` when the
same component appears more than once.

## App usage

```lua
local ui = require("fungos.ui")

return ui.component("fungos.ui/list-row", {
  id = "contact-ada",
  title = "Ada Lovelace",
  subtitle = "CTO · Acme",
  meta = "shared",
  initials = "AL",
})
```

Components resolve immediately before `ui.layout` via the registry installed by
`tend`. Missing components use their fallback and are reported.

## Package shape

The first component package is a Lua module:

```lua
local M = { name = "fungos.ui", version = "0.1.0" }
M.components = { ["fungos.ui/button"] = function(ctx, props) ... end }
return M
```

Later this is a Spore package exporting the same namespaced component identity.
Rust components compile to Wasm and implement the same render contract.
