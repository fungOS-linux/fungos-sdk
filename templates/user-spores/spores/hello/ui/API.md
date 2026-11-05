# Hello UI API

## Entrypoint

`ui/hello.lua` exports:

- `M.render(snapshot) -> tree`

Pure projection. No WIT imports, no Unibus session, no filesystem or clock.

## Snapshot

```lua
{
  message: string?,
}
```

## Actions

None.

## Slots

| Slot | Replacement |
| --- | --- |
| `hello.footer` | one node |

## Components

None.

## Theme/config

Supports the global `fungos.ui` profile. No app-specific keys yet.

## Stable ids

`hello`, `hello-title`, `hello-body`, `hello-footer`.

## Authority

None. The view only renders.
