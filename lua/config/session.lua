-- auto-session's pre-save hooks run after panel cleanup and cannot distinguish
-- manual from automatic saves. Apply our automatic-only veto at its public
-- save boundary instead, before it can change the visible layout.
local M = {}
local owners = setmetatable({}, { __mode = "kv" })

function M.suppressed(session_name)
  local predicate = require("config.settings").get("sessions.suppress")
  return type(predicate) == "function"
    and predicate({ cwd = vim.fn.getcwd(), session_name = session_name }) == true
end

function M.attach(session)
  if type(session.save_session) ~= "function" then return false end
  local owned = owners[session]
  if owned and session.save_session == owned.wrapper then return true end
  owned = { original = session.save_session }
  local function wrapper(name, opts, ...)
    if opts and opts.is_autosave and M.suppressed(name) then return false end
    return owned.original(name, opts, ...)
  end
  owned.wrapper = wrapper
  session.save_session = wrapper
  owners[session] = owned
  return true
end

function M.detach(session)
  local owned = owners[session]
  if owned and session.save_session == owned.wrapper then session.save_session = owned.original end
  owners[session] = nil
end

return M
