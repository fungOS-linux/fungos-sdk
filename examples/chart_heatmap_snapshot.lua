local rows, cols = 16, 32
local values = {}
for row = 0, rows - 1 do
  for col = 0, cols - 1 do
    values[#values + 1] = math.sin(col / cols * 12) + math.cos(row / rows * 9) + 0.4 * math.sin((row + col) / 3)
  end
end
return {
  revision = 1,
  title = "Scalar field",
  subtitle = "16 x 32 · GPU heat ramp",
  series = {
    { id = "field", label = "field", kind = "heatmap", rows = rows, cols = cols, values = values },
  },
}
