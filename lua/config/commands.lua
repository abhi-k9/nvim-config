-- Keep these available before (or without) the optional plugin layer.
vim.api.nvim_create_user_command("WorkspaceInfo", function()
  require("config.workspace").show()
end, { desc = "Inspect directories, scope, language servers and debugging" })
vim.api.nvim_create_user_command("ConfigHelp", function(opts)
  require("config.guides").show(opts.args)
end, {
  nargs = "?",
  complete = function(prefix)
    return require("config.guides").complete(prefix)
  end,
  desc = "Read a configuration workflow guide",
})
vim.api.nvim_create_user_command("DapLaunch", function()
  require("config.dap_launch").choose()
end, { desc = "Choose a debug launch with setup details" })
vim.api.nvim_create_user_command("DapLaunchInfo", function()
  require("config.dap_launch").info()
end, { desc = "Inspect launch settings without starting a session" })
vim.api.nvim_create_user_command("DapEditLaunch", function()
  require("config.dap_launch").edit()
end, { desc = "Open the configured launch file in a split" })
