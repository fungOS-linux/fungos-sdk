local points = {}
for index = 0, 4999 do
  local x = index / 4999
  local spike = (index == 2499 and 18) or (index == 3711 and -12) or 0
  points[#points + 1] = {
    x,
    50 + math.sin(x * 34) * 10 + math.cos(x * 7) * 4 + spike,
  }
end

return {
  revision = 1,
  title = "Dense telemetry",
  subtitle = "5,000 samples · LTTB on the GPU scene path",
  series = {
    { id = "rtt", label = "rtt", kind = "area", ink = "info", fill_opacity = 0.12, points = points },
  },
}
