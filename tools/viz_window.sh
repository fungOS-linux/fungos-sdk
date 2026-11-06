#!/bin/sh
# Compose the runtime visualization layers into one scene and open it in the
# native Soil + winit + wgpu window.
#
#   tools/viz_window.sh
#   SOIL_VIZ=/path/to/soil-viz tools/viz_window.sh
#
# The window is a Soil host, not Canvas: no compositor, no Spore process.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SOIL=${SOIL_ROOT:-"$ROOT/../soil"}
OUT=${VIZ_SCENE:-/tmp/fungos-viz-native.json}
SOIL_LAYOUT=${SOIL_LAYOUT:-"$SOIL/target/debug/soil-layout"}
SOIL_VIZ=${SOIL_VIZ:-"$SOIL/target/debug/soil-viz"}

if [ ! -x "$SOIL_VIZ" ]; then
  echo "viz_window: missing $SOIL_VIZ" >&2
  echo "viz_window: cargo build -p soil-scene-gpu --bin soil-viz" >&2
  exit 2
fi

SOIL_LAYOUT="$SOIL_LAYOUT" "$ROOT/bin/tend" \
  --scene "$OUT" --width 1200 --height 840 --no-reload \
  "$ROOT/examples/viz.lua" "$ROOT/examples/viz_snapshot.lua" >/dev/null

echo "viz_window: $OUT"
exec "$SOIL_VIZ" --scene "$OUT" --watch
