# Tend workspaces

A `tend.lua` file marks a workspace.

```lua
return {
  members = { "spores/*" },
  components = { "components/*.lua", "spores/*/ui/components.lua" },
  modules = "dist",
}
```

`members` are package roots. Component modules are discovered from:

```text
components/*.lua
<spore>/ui/components.lua
<spore>/components.lua
<spore>/ui/index.lua
```

## Commands

```sh
tend list
tend build app.lua snapshot.lua --name app
```

`tend list` prints workspace members and component modules.

`tend build` auto-loads workspace components when no `--component` is given.

## Explicit paths still win

```sh
tend build app.lua snapshot.lua \
  --workspace ../my-spores \
  --component extra/theme.lua \
  --name app
```

`--no-workspace` disables discovery.

## Output

```lua
modules = "dist"
```

sets the default `--out` directory.

## First pass

Implemented:

```text
tend.lua workspace file
members/components globs
component discovery from Spore dirs
tend list
auto component loading
default output directory
```

Not yet:

```text
workspace dependency graph
per-member build matrix
registry/git dependency resolution
package lockfile
```
