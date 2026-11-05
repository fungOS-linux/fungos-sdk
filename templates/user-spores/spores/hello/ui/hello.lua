-- Hello: the smallest documented Spore UI.
--
-- This file is pure. It reads a snapshot, viewport, and theme, and returns a
-- semantic tree. It does not read files, open sockets, or call actions.

local ui = require("fungos.ui")

local M = {}
M.name = "user.hello"
M.version = "0.1.0"

function M.render(snapshot)
  local width, height = ui.viewport(720, 480)
  local theme = ui.theme()

  return ui.column("hello", {
    width = width,
    height = height,
    gap = 12,
    padding = { top = 28, right = 28, bottom = 28, left = 28 },
  }, {
    ui.text("hello-title", "Hello", {
      size = theme.title or 28,
      ink = "primary",
    }),
    ui.text("hello-body", snapshot.message or "From a Spore.", {
      size = theme.body or 16,
      wrap = true,
    }),
    ui.slot("hello.footer", ui.text("hello-footer", "user.hello", {
      size = theme.micro or 10,
      ink = "muted",
    })),
  })
end

return M
