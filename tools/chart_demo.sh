#!/bin/sh
# Launch the chart demo surfaces against a running Canvas.
#
#   tools/chart_demo.sh
#   CANVAS_UI_SOCKET=/path/to/ui.sock tools/chart_demo.sh
#
# Re-run after editing a snapshot or chart.lua: the script kills the previous
# demo producers, regenerates the scenes, and starts new windows.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT=${CHART_DEMO_DIR:-/tmp/fungos-chart-demo}
SOCKET=${CANVAS_UI_SOCKET:-"$HOME/Library/Application Support/Dock/canvas/ui.sock"}
GPU=${SOIL_SCENE_GPU:-"$ROOT/../soil/target/debug/soil-scene-gpu"}
LAYOUT=${SOIL_LAYOUT:-"$ROOT/../soil/target/debug/soil-layout"}
TEND="$ROOT/bin/tend"

mkdir -p "$OUT"
if [ -f "$OUT/pids" ]; then
  while read -r pid; do kill "$pid" 2>/dev/null || true; done < "$OUT/pids"
  rm -f "$OUT/pids"
fi

if [ ! -S "$SOCKET" ]; then
  echo "chart_demo: no Canvas ui.sock at $SOCKET" >&2
  echo "chart_demo: start Canvas or set CANVAS_UI_SOCKET" >&2
  exit 2
fi
if [ ! -x "$GPU" ]; then
  echo "chart_demo: missing $GPU" >&2
  echo "chart_demo: cargo build -p soil-scene-gpu" >&2
  exit 2
fi
if [ ! -x "$TEND" ]; then
  echo "chart_demo: missing $TEND" >&2
  exit 2
fi

scene() {
  name=$1
  snapshot=$2
  width=$3
  height=$4
  SOIL_LAYOUT="$LAYOUT" "$TEND" --scene "$OUT/$name.json" \
    --width "$width" --height "$height" --no-reload \
    "$ROOT/examples/chart.lua" "$ROOT/examples/$snapshot" >/dev/null
  "$GPU" --scene "$OUT/$name.json" --canvas-socket "$SOCKET" \
    --source-id "chart-$name" --size "${width}x${height}" --hold \
    >>"$OUT/$name.log" 2>&1 &
  echo $! >> "$OUT/pids"
  echo "chart_demo: chart-$name ${width}x${height}"
}

scene line chart_snapshot.lua 900 520
scene area chart_area_snapshot.lua 900 520

echo "chart_demo: scenes in $OUT; re-run this script after edits"
wait
