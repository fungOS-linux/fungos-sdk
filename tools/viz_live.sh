#!/bin/sh
# Generate the Lua-owned live viz spec and open the resident Rust host.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SOIL=${SOIL_ROOT:-"$ROOT/../soil"}
SPEC=${VIZ_SPEC:-/tmp/fungos-viz-live.json}
HOST=${SOIL_VIZ:-"$SOIL/target/release/soil-viz"}
if [ ! -x "$HOST" ]; then
  HOST=${SOIL_VIZ:-"$SOIL/target/debug/soil-viz"}
fi
FPS=${VIZ_FPS:-60}

lua "$ROOT/tools/viz_spec.lua" "${1:-$ROOT/examples/viz_live.lua}" "$SPEC"
exec "$HOST" --live "$SPEC" --fps "$FPS"
