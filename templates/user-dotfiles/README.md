# user/dotfiles

`~/.config` for a fungOS machine, versioned as a repo.

```text
.config/
  fungos/
    ui.lua
    apps/
  nvim/
  shell/
```

`ui.lua` is data plus presentation-only recipes. It cannot grant capabilities.
The same files should be visible through the native home directory and the VFS
`.config` so `mush`, Settings, and the shell all see one source of truth.
