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

---

# Superhuman-shaped inbox example API

`inbox_superhuman.lua` is the denser, keyboard-first prototype.

## Entrypoint

`inbox_superhuman.lua` exports:

- `M.render(snapshot) -> Canvas scene`

## Snapshot additions

In addition to the fields above:

```lua
{
  splits = {
    { id: string, label: string, count: integer?, selected: boolean? },
  }?,
  labels = {
    { id: string, label: string?, count: integer? },
  }?,
  remaining = integer?,
  group = string?,
  thread.important = boolean?,
}
```

`thread.messages` entries may contain `{ from, time, preview }`.
`thread.draft` is the current agent/user reply draft.

The prototype also reads a host-owned workspace projection:

```lua
{
  workspace = {
    active_pane: string?,
    focus: string?,
    panes = {
      {
        id: string,
        kind: string?,
        width: number?,
        active_tab: string?,
        tabs = {
          { id: string, label: string, unread: integer?, selected: boolean?, action: ActionIntent? },
        },
      },
    },
    sidebar = {
      account: string?,
      groups = {
        {
          id: string,
          label: string,
          items = {
            { id: string, label: string, count: integer?, selected: boolean?, action: ActionIntent? },
          },
        },
      },
    },
  },
}
```

Pane geometry, tab state, focus, split persistence, and hit testing remain
host-owned. The view only renders the projection and emits intents.

## Host events

| Event | Target | Meaning |
| --- | --- | --- |
| `activate` | `thread-<n>` | select thread |
| `activate` | `list-tabs-<tab>` | select split/tab |
| `activate` | `rail-group-<n>-<item>` | select sidebar item |
| `activate` | `detail-archive` | show archive feedback |
| `activate` | `composer-send` | show send feedback |
| `activate` | `toast-undo` | clear toast |
| `key` with `j`/`down` | — | next thread |
| `key` with `k`/`up` | — | previous thread |
| `pointer` press/release | coordinates | immediate press state and target activation |
| `pointer` move | coordinates | hover state when the host sends it |

The view persists its own selection/state through the Canvas `module.select`
memory:

```text
v1;thread=<id>;tab=<id>;nav=<group>:<item>;toast=<archive|sent|draft>
```

This is view-local memory, not Spore state. Durable mail state still belongs to
the Spore/Unibus action router.

Text input, command palette execution, and composer editing are not wired yet.
The host currently dispatches pointer press/release, not hover moves; the view
is prepared to handle moves when that is enabled.

## Actions

| Action | Payload |
| --- | --- |
| `mail.reply` | `{ thread_id: string }` |
| `mail.reply_all` | `{ thread_id: string }` |
| `mail.archive` | `{ thread_id: string }` |
| `mail.reply.send` | `{ thread_id: string }` |
| `mail.reply.approve` | `{ thread_id: string }` |
| `tab.activate` | `{ pane_id: string, tab_id: string }` |
| `nav.activate` | `{ group: string, item: string }` |

## Slots

| Slot | Replacement |
| --- | --- |
| `inbox.rail.footer` | one rail child |
| `inbox.list.header` | one list child |
| `detail.actions` | one detail child |
| `detail.before_messages` | one detail child |
| `empty_state` | one detail child |
| `inbox.toast` | one root child |

## Stable ids

`inbox-root`, `inbox-rail`, `inbox-list-pane`, `inbox-detail-pane`,
`inbox-command`, `list-head`, `list-tabs`, `list-tabs-<tab>`, `rail-group-<n>`,
`rail-group-<n>-<item>`, `thread-<n>`, `detail-actions`, `detail-title`,
`detail-brief`, `composer`, `inbox-status`, `toast`.

## Authority

None. The prototype only emits intents and renders a snapshot.
