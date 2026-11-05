-- User profile for fungOS.
--
-- This file is data plus presentation-only recipes. It cannot grant a
-- capability, read records, or publish on Unibus.

return {
  schema_version = 1,

  density = "comfortable",

  theme = {
    radius = 10,
  },

  apps = {
    ["dev.fungos.unibus"] = {
      density = "compact",
      hide = { "rail.tags" },
      order = { "rail.accounts", "rail.inboxes" },
    },

    ["dev.fungos.contacts"] = {
      density = "comfortable",
    },
  },
}
