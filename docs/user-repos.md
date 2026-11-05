# User repos

The intended model is two repos, both composable with the system and with each
other.

```text
user/spores
  spores/
    acme-mail/
    acme-components/
    acme-rice/

user/dotfiles
  .config/
    fungos/
      ui.lua
      apps/
        inbox.lua
      themes/
        aurora.lua
    nvim/
    shell/
    ...
```

## user/spores

Owns app Spores, component Spores, chrome Spores, and rice packages.

```text
spores/acme-mail/
  spore.toml
  module.wasm
  ui/
    inbox.lua
    API.md
```

A component/rice Spore may have no `module.wasm` and no logic grants. It only
contributes UI:

```text
spores/acme-rice/
  spore.toml
  ui/
    API.md
    rice.lua
```

## user/dotfiles

Owns configuration, not executable authority.

```lua
-- ~/.config/fungos/ui.lua
return {
  theme = { radius = 12 },
  apps = {
    ["dev.fungos.unibus"] = {
      density = "compact",
      hide = { "rail.tags" },
      order = { "rail.accounts", "rail.inboxes" },
    },
  },
}
```

Advanced recipes may live beside it:

```lua
-- ~/.config/fungos/apps/inbox.lua
return {
  slots = {
    ["toolbar.end"] = function(ctx)
      return ui.button("triage", "Triage", {
        action = ui.action("mail.triage"),
      })
    end,
  },
}
```

Recipes are presentation-only Lua. They cannot import Soil WIT or publish on
Unibus.

## Same files in the real home and the VFS

The dotfiles repo should be cloneable in both places:

```text
~/src/user/dotfiles
~/.config -> ~/src/user/dotfiles/.config

vfs:/user/dotfiles
vfs:/home/<user>/.config -> vfs:/user/dotfiles/.config
```

The host may use a symlink, bind, or VFS overlay. The requirement is that both
views expose the same files and the same apply/reload semantics.

This means:

- `mush` reads the same `~/.config/fungos/ui.lua` as the native shell.
- the Settings Spore edits the same files.
- the VFS sees the same themes and recipes.
- a fleet can clone the dotfiles repo and get the same UI.

## Bootstrapping

```bash
git clone <user/spores>   ~/src/user/spores
git clone <user/dotfiles> ~/src/user/dotfiles

ln -s ~/src/user/dotfiles/.config ~/.config
```

For a fresh machine, the installer can link `~/.config` before the first Canvas
launch, or import the dotfiles repo into the VFS and expose it at `~/.config`.

## Rules

- Dotfiles are data plus presentation-only recipes.
- A dotfile cannot grant a capability.
- A Spore component cannot read records.
- A rice cannot change action semantics.
- App profiles are versioned with `schema_version`.
- A broken overlay falls back per app, not globally.
