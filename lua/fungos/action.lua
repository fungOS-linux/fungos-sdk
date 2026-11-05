-- fungos.action — action intents emitted by Spore UI Lua.
--
-- The UI never invokes an action. It describes one. The host stamps the caller,
-- checks grants/approval, routes to the Spore action implementation, and returns
-- a fresh snapshot.
--
-- An intent is intentionally tiny and serializable:
--
--   { action = "mail.archive", payload = { thread_id = "..." } }

local action = {}

--- Build an action intent.
function action.intent(id, payload)
  return { action = id, payload = payload }
end

--- Alias for view code that reads better as `action.call`.
action.call = action.intent

--- Validate the shape of an intent before emitting it into a scene.
function action.valid(intent)
  return type(intent) == "table"
    and type(intent.action) == "string"
    and intent.action ~= ""
    and (intent.payload == nil or type(intent.payload) == "table")
end

--- Attach an intent to a node without making the node itself authoritative.
function action.attach(node, id, payload)
  node.action = action.intent(id, payload)
  return node
end

return action
