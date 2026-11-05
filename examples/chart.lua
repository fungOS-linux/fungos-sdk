-- A chart is a normal `fungos.ui` view. The snapshot is data; the chart DSL is
-- presentation. No chart-specific host API and no TypeScript runtime.

local chart = require("fungos.chart")

local M = {}
M.name = "example.chart"
M.version = "0.1.0"

function M.render(snapshot)
  snapshot = snapshot or {}
  local c = chart.new {
    title = snapshot.title or "Chart",
    subtitle = snapshot.subtitle,
    width = 900,
    height = 520,
    x = { label = "seconds" },
    y = { label = "ms" },
  }
  for _, series in ipairs(snapshot.series or {}) do
    local method = series.kind == "area" and c.area or c.line
    method(c, {
      id = series.id,
      label = series.label,
      ink = series.ink,
      points = series.points,
      width = series.width or 2,
      fill_opacity = series.fill_opacity,
    })
  end
  c:render()
end

function M.present(snapshot)
  local c = chart.new {
    title = (snapshot or {}).title or "Chart",
    subtitle = (snapshot or {}).subtitle,
    width = 900,
    height = 520,
  }
  for _, series in ipairs((snapshot or {}).series or {}) do
    local method = series.kind == "area" and c.area or c.line
    method(c, { id = series.id, label = series.label, ink = series.ink, points = series.points, width = series.width or 2, fill_opacity = series.fill_opacity })
  end
  return c:present()
end

return M
