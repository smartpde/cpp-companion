local M = {}

local defaults = {
  header_extensions = {"h"},
  source_extensions = {"cc"},
}

local config

function M.setup(opts)
  opts = opts or {}
  config = vim.tbl_deep_extend("force", defaults, opts)
end

function M.get()
  if not config then
    error("cpp-companion is not initialized, call `require('cpp-companion').setup()`")
  end
  return config
end

return M
