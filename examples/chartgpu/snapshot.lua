-- Deterministic incident replay for the Canvas ChartGPU surface.
-- The native ChartGPU Spore generates these streams in Rust; this snapshot is
-- the same shape so the Lua view can be iterated through `tend watch`.

local function series(count, base, amplitude, period, phase, spike_at, spike)
  local points = {}
  for i = 0, count do
    local y = base + amplitude * math.sin((i + phase) / period)
    if spike_at and i >= spike_at then
      local tail = math.max(0, 1 - (i - spike_at) / 12)
      y = y + spike * tail
    end
    points[#points + 1] = { x = i, y = math.max(0, y) }
  end
  return points
end

return {
  latency = {
    p50 = series(59, 70, 18, 7, 0),
    p95 = series(59, 210, 55, 6, 3, 42, 120),
    p99 = series(59, 300, 75, 5, 5, 42, 220),
  },
  throughput = {
    requests = series(59, 960, 150, 9, 1, 44, -430),
  },
  resources = {
    memory = series(59, 48, 10, 13, 2),
    cpu = series(59, 44, 16, 5, 4),
  },
  errors = {
    e4xx = series(59, 2.2, 1.0, 4, 1),
    e5xx = series(59, 0.4, 0.25, 8, 2, 42, 8),
  },
  connections = {
    active = series(59, 92, 22, 7, 3),
    waiting = series(59, 12, 6, 5, 1, 43, 44),
  },
}
