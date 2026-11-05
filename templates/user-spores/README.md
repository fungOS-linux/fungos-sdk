# user/spores

Your own Spores and UI contributions.

```text
spores/
  hello/
    spore.toml
    module.wasm
    ui/
      hello.lua
      API.md
```

Every Spore with a `[ui]` entry must ship `ui/API.md`. The Lua API is part of the
package ABI, because other Spores, rices, and dotfiles may compose against it.

A UI-only Spore can omit `module.wasm` once the package format supports it. Until
then, keep a small logic module or publish it as a component/rice contribution.
