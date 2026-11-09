-- A fixture-driven gallery for the reusable Canvas dashboard primitives.
--
-- Canvas remains a compositor: this module is SDK content, authored at a stable
-- 1200x840 coordinate space and retained as ordinary scene nodes.

local ui = require("fungos.ui")
local dashboard = require("fungos.dashboard")

local M = { name = "example.dashboard.gallery", version = "0.1.0" }

local function status(surface, x, y)
  dashboard.status(surface, "gallery-fixture", x, y, "live", {
    label = "FIXTURE-DRIVEN",
    ink = "info",
  })
end

function M.render(snapshot)
  snapshot = snapshot or {}
  local width, height = 1200, 840
  local surface = ui.surface(width, height, ui.theme())
  surface:background("background")

  surface:text("gallery-title", "Canvas dashboard primitives", 18, 8, 18, "text")
  surface:text("gallery-subtitle",
    "panel chrome · stat · gauge · table · axes · legend · selection · thresholds",
    18, 46, 9, "muted")
  status(surface, width - 170, 21)

  local stats = snapshot.stats or {}
  local stat_w = (width - 24) / 3
  for index = 1, math.min(#stats, 3) do
    local item = stats[index]
    dashboard.stat(surface, "gallery-stat-" .. index,
      (index - 1) * (stat_w + 12), 60, stat_w, 112, item)
  end

  dashboard.gauge(surface, "gallery-gauge", 0, 184, 344, 212, snapshot.gauge or {})
  dashboard.table(surface, "gallery-table", 356, 184, 844, 212, snapshot.table or {})
  local chart = snapshot.chart or {}
  chart.columns = 24
  dashboard.chart(surface, "gallery-chart", 0, 408, 1200, 420, chart)
end

return M
