# Inbox example UI API

## Entrypoint

`inbox.lua` exports:

- `M.render(snapshot) -> Canvas scene`

## Snapshot

See `inbox_snapshot.lua` for the fixture. The view reads:

```lua
{
  account = { email: string, sync: string }?,
  counts = { unread: integer, urgent: integer }?,
  accounts = { Account }?,
  inboxes = { Inbox }?,
  tags = { Tag }?,
  threads = { Thread },
  selected_id = string?,
  sort = string?,
  layout = { list_offset: integer?, list_limit: integer? }?,
}

Thread = {
  id: string,
  sender: string,
  title: string,
  preview: string,
  brief: string?,
  time: string,
  unread: boolean?,
  urgent: boolean?,
  selected: boolean?,
  labels: { string }?,
}
```

## Actions

| Action | Payload |
| --- | --- |
| `mail.reply` | `{ thread_id: string }` |
| `mail.reply_all` | `{ thread_id: string }` |
| `mail.archive` | `{ thread_id: string }` |

## Slots

| Slot | Replacement |
| --- | --- |
| `toolbar.start` | one node |
| `toolbar.end` | one node |
| `detail.actions` | one node |
| `empty_state` | one node |

## Components

Consumes:

- `dev.fungos.mail/thread-row` with props `{ thread, index, selected }`.
  Falls back to the built-in row when unresolved.

Exports:

None.

## Theme/config

Uses the global `fungos.ui` profile. App-specific keys are not implemented yet.

## Stable ids

`inbox-root`, `inbox-toolbar`, `inbox-search`, `inbox-rail`,
`inbox-list-pane`, `inbox-detail-pane`, `mail-list`, `thread-<n>`,
`detail-actions`, `detail-brief`.

## Authority

None. The example only emits action intents.
