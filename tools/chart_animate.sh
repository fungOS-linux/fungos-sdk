#!/bin/sh
# Launch the live ChartGPU catalog against a running Canvas.
#
#   tools/chart_animate.sh
#   CANVAS_UI_SOCKET=/path/to/ui.sock tools/chart_animate.sh
#
# Generates sin/random chart scenes continuously and lets `soil-scene-gpu
# --watch` republish frames as the files change. Ctrl-C stops every producer.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT=${CHART_DEMO_DIR:-/tmp/fungos-chart-demo}
SOCKET=${CANVAS_UI_SOCKET:-"$HOME/Library/Application Support/Dock/canvas/ui.sock"}
GPU=${SOIL_SCENE_GPU:-"$ROOT/../soil/target/debug/soil-scene-gpu"}
FPS=${CHART_FPS:-24}

mkdir -p "$OUT"
if [ -f "$OUT/animate.pids" ]; then
  while read -r pid; do kill "$pid" 2>/dev/null || true; done < "$OUT/animate.pids"
  rm -f "$OUT/animate.pids"
fi

if [ ! -S "$SOCKET" ]; then
  echo "chart_animate: no Canvas ui.sock at $SOCKET" >&2
  echo "chart_animate: start Canvas or set CANVAS_UI_SOCKET" >&2
  exit 2
fi
if [ ! -x "$GPU" ]; then
  echo "chart_animate: missing $GPU" >&2
  echo "chart_animate: cargo build -p soil-scene-gpu" >&2
  exit 2
fi

pids=""
cleanup() {
  for pid in $pids; do kill "$pid" 2>/dev/null || true; done
  rm -f "$OUT/animate.pids"
}
trap cleanup INT TERM EXIT

lua "$ROOT/tools/chart_live.lua" --out "$OUT" --fps "$FPS" \
  >>"$OUT/live.log" 2>&1 &
pids="$pids $!"
echo $! >> "$OUT/animate.pids"

# Wait for the first atomic scene writes before opening surfaces.
tries=0
while [ "$tries" -lt 100 ]; do
  ready=1
  for name in line scatter heatmap dense candle; do
    [ -f "$OUT/live-$name.json" ] || ready=0
  done
  [ "$ready" -eq 1 ] && break
  sleep 0.05
  tries=$((tries + 1))
done
if [ "$tries" -ge 100 ]; then
  echo "chart_animate: live generator did not produce scenes" >&2
  exit 2
fi

for name in line scatter heatmap dense candle; do
  "$GPU" --scene "$OUT/live-$name.json" --canvas-socket "$SOCKET" \
    --source-id "live-$name" --size 900x520 --watch --fps "$FPS" \
    --input-out "$OUT/live-$name.input" \
    >>"$OUT/live-$name.log" 2>&1 &
  pids="$pids $!"
  echo $! >> "$OUT/animate.pids"
  echo "chart_animate: live-$name"
done

echo "chart_animate: scenes in $OUT; Ctrl-C to stop"
wait
