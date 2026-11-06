# Package and target model

Status: **direction, 2026-11-06.**

A Spore is the distribution and trust unit. It may contain apps, libraries,
components, CLIs and native packaging targets.

```text
tend   developer build/package/sign tool
soil   runtime
store  system Spore over the package service
```

## One package, many roles

```text
exports      importable libraries/components/schemas
entrypoints  launchable app/cli/native surfaces
targets      soil | wasm | macos | windows | linux
grants       requested authority
```

A package can export UI components and also be an app. An importer of a
component export does not inherit the app's grants.

## Exports

Component and library identity is namespaced:

```text
fungos.ui/button@1
fungos.ui/share-dialog@1
fungos.viz/chart@1
```

Import:

```lua
local Button = ui.use("fungos.ui/button@1")
local Chart = ui.use("fungos.viz/chart@1")
```

First pass package layout:

```text
components/fungos.ui.lua   -> fungos.ui/button, fungos.ui/card, ...
ui/button.lua              -> app-local component
lib/format.lua             -> Lua library
schemas/contact.json       -> schema export
```

## Targets

```text
soil target       Soil runs the Spore and enforces grants
native target     OS/installer owns authority; Soil may be embedded
cli target        WASI/Mush-style command
library export    imported by other Spores; no launch authority
```

Native packaging is a distribution wrapper, not a new package identity.

## Sharing modes

```text
data sharing        my data, their Spore, their identity
Spore sharing       my code, their identity, their grants
presentation lease  my code, my scoped data, delegated time-boxed identity
```

Data grants are revocable. Spore packages are copyable; do not treat package
sharing as access control. Presentation leases are device-bound and expire.

## Authority

```text
native target    OS login, sandbox, entitlements, installer
soil target      Mycelium/fungOS principal + host-linked grants
embedded soil    native wrapper maps a scoped subset into Soil
```

The Soil runtime may already be authenticated. That is not ambient authority:
a Spore gets only the grants linked to the current principal/device.

## Store and consent

```text
system.store     package UI
system.consent   grant review
system.updates   update status
```

Install flow:

```text
Store requests install
  -> package service resolves and verifies
  -> host computes grant diff
  -> consent approves new/changed grants
  -> host installs and links grants
```

The Store cannot grant authority. Consent cannot install.

## Updates

```text
Mycelium gossip   signed announcement/revocation
package service   fetch/verify CID
update agent      stage/restart/health/rollback
system.updates    UI/status
```

Gossip makes updates visible. Signatures make them trustworthy. The updater
makes them safe.

## Tend build

```sh
tend build ui/app.lua ui/snapshot.lua \
  --component components/fungos.ui.lua \
  --name my-app \
  --out dist/
```

`tend build` composes the app view with component modules and writes a Canvas
module. Component resolution happens through `fungos.compose` immediately before
layout.

The first pass accepts explicit `--component file.lua` paths. Package-level
resolution from installed Spores comes next.
