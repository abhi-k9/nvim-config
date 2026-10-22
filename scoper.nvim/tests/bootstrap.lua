-- Shared by the standalone Scoper suite and the host config's test init.
-- Publish only a complete clone; concurrent runners own separate staging paths.
return function()
  if pcall(require, "plenary.busted") then return end
  local install = vim.fn.stdpath("cache") .. "/test-deps/plenary.nvim"
  local function ready(path)
    return vim.fn.filereadable(path .. "/lua/plenary/busted.lua") == 1
      and vim.fn.filereadable(path .. "/plugin/plenary.vim") == 1
  end
  local function fail(message)
    io.stderr:write("tests: " .. message .. "\n")
    vim.cmd("cquit 1")
  end
  if not ready(install) then
    if vim.uv.fs_lstat(install) then
      fail("incomplete Plenary cache: " .. install .. "; remove it when no tests are running")
      return
    end
    local staging = install .. ".tmp-" .. vim.fn.getpid() .. "-" .. vim.uv.hrtime()
    local out = vim.fn.system({
      "git",
      "clone",
      "--depth=1",
      "https://github.com/nvim-lua/plenary.nvim",
      staging,
    })
    local cloned = vim.v.shell_error == 0 and ready(staging)
    local published, err
    if cloned and not vim.uv.fs_lstat(install) then
      published, err = vim.uv.fs_rename(staging, install)
    end
    vim.fn.delete(staging, "rf")
    if not published and not ready(install) then
      local detail = err
        or (out ~= "" and out)
        or (cloned and "destination already exists" or "clone failed or incomplete")
      fail("cannot install Plenary: " .. detail)
      return
    end
  end
  vim.opt.rtp:append(install)
end
