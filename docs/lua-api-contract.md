# Spore Lua API contract

Every Spore that ships Lua must document its Lua API. The Lua API is part of the
package ABI, not an implementation detail.

This is required because Spores are composable: another Spore, a rice, a user
dotfile, or a host projection may depend on the snapshot shape, action ids,
slot names, component names, and config keys. Undocumented Lua is not a stable
extension point.

## Required files

Every Spore with a `[ui]` entry **must** include:

```text
ui/API.md
```

The file is checked by `tend check`, `tend doctor`, and by the package/CI check. A missing file
is an error, not a warning.

## Required sections

`ui/API.md` must document:

1. **Entrypoint** — the Lua module path and exported functions.
2. **Snapshot** — fields the view reads, with types and nullability.
3. **Actions** — every action id the UI can emit, its payload, and its result.
4. **Slots** — named extension points and their expected replacement type.
5. **Components** — named components this Spore exports, if any.
6. **Theme/config** — supported profile keys and app-specific overrides.
7. **Stable ids** — ids other Spores/config may target, if any.
8. **Authority** — grants the UI view does not have, and where logic lives.

If a section does not apply, say `None` and explain why.

## Example

```markdown
# Inbox UI API

## Entrypoint

`ui/inbox.lua` exports:

- `M.render(snapshot) -> Canvas scene`

The view is a pure projection. It has no WIT imports, no Unibus session, and no
filesystem access.

## Snapshot

```lua
{
  account = { label: string, email: string, sync: string },
  counts = { unread: integer, urgent: integer },
  accounts = { { id, label, email, unread, selected } },
  inboxes = { { id, label, unread, selected } },
  tags = { { id, label, count } },
  threads = { Thread },
  selected_id = string?,
  layout = { list_offset = integer?, list_limit = integer? },
  sort = string?,
}

Thread = {
  id: string,
  sender: string,
  title: string,
  preview: string,
  brief: string,
  time: string,
  unread: boolean,
  labels: { string },
}
```

## Actions

| Action | Payload | Emitted by |
| --- | --- | --- |
| `mail.read` | `{ thread_id: string }` | thread selection |
| `mail.unread` | `{ thread_id: string }` | row action |
| `mail.archive` | `{ thread_id: string }` | detail action bar |
| `mail.tag` | `{ thread_id: string, tag: string }` | tag control |

The UI only emits intents. The Unibus action router stamps the caller and checks
the manifest grants.

## Slots

| Slot | Replacement |
| --- | --- |
| `toolbar.start` | one node |
| `toolbar.end` | one node |
| `rail.header` | one node |
| `rail.footer` | one node |
| `detail.actions` | one node |
| `empty_state` | one node |

## Components

None. This Spore is an app.

## Theme/config

Supported per-app keys:

```lua
{
  density = "compact" | "comfortable" | "spacious",
  theme = { radius = number },
  hide = { "rail.tags" },
  order = { "rail.accounts", "rail.inboxes" },
}
```

## Stable ids

`thread-<n>`, `mail-list`, `inbox-rail`, `inbox-detail-pane`,
`detail-actions`, `inbox-search`.

## Authority

None in Lua. Reads and mutations are executed by the Spore logic module through
`soil:records` with the grants declared in `spore.toml`.
```

## Composition rules

- UI Lua may read only its snapshot, theme, viewport, and module event.
- UI Lua may not import Soil WIT.
- UI Lua may not publish on Unibus.
- UI Lua may emit action intents.
- A component Spore exports pure component functions.
- A chrome Spore exports `chrome.<name>` components.
- A rice Spore exports `theme` and/or `slots`.
- A user profile is data; advanced recipes are presentation-only Lua.
- A missing documented slot/component fails preview; an undocumented internal
  id may change at any time.
