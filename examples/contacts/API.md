# Contacts example UI API

## Entrypoint

`contacts.lua` exports:

- `M.render(snapshot) -> Canvas scene`

Pure projection. No WIT imports, no Unibus session, no filesystem or clock.

## Snapshot

```lua
{
  revision: integer,
  title: string?,
  search: string?,
  total: integer?,
  organizations: integer?,
  selected_id: string?,
  account = { label: string?, sync: string? }?,
  filters = {
    { id: string, label: string, count: integer?, selected: boolean? },
  }?,
  contacts = {
    {
      id: string,
      name: string,
      org: string?,
      title: string?,
      emails: { string }?,
      phones: { string }?,
      addresses: { string }?,
      birthday: string?,
      note: string?,
    },
  },
}
```

The Spore owns the query and filtering. The view may apply local presentation
filters (`all`, `orgs`, `recent`) for the prototype.

## Host events

| Event | Target | Meaning |
| --- | --- | --- |
| `activate` | `contact-<n>` | select contact |
| `activate` | `contacts-filters-<id>` | select filter |
| `activate` | `contact-action-message` | message intent |
| `activate` | `contact-action-call` | call intent |
| `activate` | `contact-action-email` | email intent |
| `activate` | `contact-action-edit` | edit intent |
| `activate` | `contact-toast-undo` | clear toast |
| `pointer` press/release | coordinates | press state, target activation |
| `pointer` move | coordinates | host-throttled hover |
| `pointer` leave | — | clear hover |

View state is persisted through Canvas `module.select`:

```text
v1;contact=<id>;filter=<id>;toast=<call|email|message|edit>
```

## Actions

| Action | Payload |
| --- | --- |
| `contacts.message` | `{ contact_id: string }` |
| `contacts.call` | `{ contact_id: string }` |
| `contacts.email` | `{ contact_id: string }` |
| `contacts.edit` | `{ contact_id: string }` |

These are intents only. The Spore/Unibus router owns semantics.

## Slots

None yet.

## Components

None yet.

## Theme/config

Uses `module.theme` and the global `fungos.ui` profile.

## Stable ids

`contacts-root`, `contacts-header`, `contacts-title`, `contacts-search`,
`contacts-body`, `contacts-sidebar`, `contacts-detail-pane`,
`contacts-filters`, `contacts-list`, `contact-<n>`, `contact-detail`,
`contact-action-message`, `contact-action-call`, `contact-action-email`,
`contact-action-edit`, `contact-toast`.

## Authority

None. Reads are performed by the Contacts Spore over `soil:records`.
