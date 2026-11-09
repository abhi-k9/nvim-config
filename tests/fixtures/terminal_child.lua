-- Test-only child of a real PTY. No editor config or third-party plugins load.
local function report()
  io.stdout:write("TERMINAL_AUDIT " .. vim.json.encode({
    cwd = vim.uv.cwd(),
    marker = vim.env.NVIM_TERMINAL_AUDIT_MARKER,
  }) .. "\n")
  io.stdout:flush()
end

report()
if arg[1] == "probe" then return end
for line in io.lines() do
  local code = line:match("^exit:(%d+)")
  if code then os.exit(tonumber(code)) end
  if line == "probe" then report() end
end
