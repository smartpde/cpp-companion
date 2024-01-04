local config = require("cpp-companion.internal.config")

local M = {}

function M.by_extension_lib_resolver(file_path)
  local lib = {
    headers = {},
    sources = {},
  }
  local cfg = config.get()
  local root_path = vim.fn.fnamemodify(file_path, ":r")
  for _, ext in ipairs(cfg.header_extensions) do
    table.insert(lib.headers, root_path .. "." .. ext)
  end
  for _, ext in ipairs(cfg.source_extensions) do
    table.insert(lib.sources, root_path .. "." .. ext)
  end
  return lib
end

return M
