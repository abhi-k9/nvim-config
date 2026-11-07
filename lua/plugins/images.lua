-- Only the image renderer is configured. Loading waits for an explicit preview;
-- all ordinary file reads and document events remain with the existing config.
return {
  "folke/snacks.nvim",
  lazy = true,
  opts = function()
    return {
      image = {
        enabled = require("config.settings").get("images.enabled", false) == true,
        formats = {},
        doc = { enabled = false },
        math = { enabled = false },
        convert = { notify = false },
      },
    }
  end,
}
