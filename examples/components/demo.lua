local ui = require("fungos.ui")

local M = { name = "example.components", version = "0.1.0" }

function M.render(snapshot)
  local children = {
    ui.text("components-demo-title", "Shared components", { size = 22, height = 30, ink = "primary" }),
    ui.component("fungos.ui/badge", {
      id = "components-demo-badge",
      label = "fungos.ui",
      ink = "primary",
    }),
  }
  local rows = {}
  for _, contact in ipairs(snapshot.contacts or {}) do
    ui.push(rows, ui.component("fungos.ui/list-row", {
      id = "contact-" .. contact.id,
      title = contact.name,
      subtitle = contact.subtitle,
      meta = contact.meta,
      initials = contact.initials,
      action = contact.action,
    }))
  end
  if #rows == 0 then
    ui.push(rows, ui.component("fungos.ui/empty", {
      id = "components-demo-empty",
      title = "No contacts",
      detail = "Add one from the contacts Spore.",
    }))
  end
  children[#children + 1] = ui.component("fungos.ui/card", {
    id = "components-demo-card",
    title = "Contacts",
    detail = "Same component package, different Spore.",
  }, rows)
  return ui.layout(ui.column("components-demo", {
    width = 720,
    gap = 10,
    padding = { left = 20, right = 20, top = 20, bottom = 20 },
  }, children), 720, 640)
end

return M
