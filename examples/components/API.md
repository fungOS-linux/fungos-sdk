# Components demo API

## Entrypoint

`demo.lua` exports `M.render(snapshot) -> laid-out tree`.

## Snapshot

```lua
{ contacts = { { id, name, subtitle, initials, meta } } }
```

## Actions

None.

## Slots

None.

## Components

Uses `fungos.ui/list-row`, `fungos.ui/card`, `fungos.ui/badge`, `fungos.ui/empty`.

## Theme/config

Uses the active `fungos.ui` profile.

## Stable ids

`components-demo`, `components-demo-list`, `contact-<id>`.

## Authority

None. Pure presentation.
