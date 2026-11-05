local points = {}
for index = 1, 320 do
  local x = index / 320 * 40
  local noise = math.sin(index * 12.9898) * 43758.5453
  noise = noise - math.floor(noise)
  points[#points + 1] = { x, 50 + math.sin(x * 0.5) * 18 + (noise - 0.5) * 12 }
end
return {
  revision = 1,
  title = "Scatter density",
  subtitle = "320 points · one points primitive",
  series = {
    { id = "cloud", label = "cloud", kind = "scatter", ink = "info", size = 4, points = points },
  },
}
