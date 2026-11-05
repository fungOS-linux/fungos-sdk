return {
  revision = 1,
  title = "Fleet latency",
  subtitle = "p50 / p95 · area fill",
  series = {
    { id = "p50", label = "p50", kind = "area", ink = "success", fill_opacity = 0.14, points = {
      { 0, 42 }, { 1, 44 }, { 2, 41 }, { 3, 47 }, { 4, 45 }, { 5, 52 }, { 6, 49 },
      { 7, 53 }, { 8, 51 }, { 9, 58 }, { 10, 55 }, { 11, 57 }, { 12, 54 }, { 13, 60 },
    } },
    { id = "p95", label = "p95", kind = "area", ink = "primary", fill_opacity = 0.12, points = {
      { 0, 88 }, { 1, 91 }, { 2, 84 }, { 3, 96 }, { 4, 101 }, { 5, 94 }, { 6, 112 },
      { 7, 105 }, { 8, 118 }, { 9, 109 }, { 10, 121 }, { 11, 115 }, { 12, 128 }, { 13, 119 },
    } },
  },
}
