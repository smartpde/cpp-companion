local config = require("cpp-companion.internal.config")
local libresolvers = require("cpp-companion.internal.libresolvers")
local decl_sync = require("cpp-companion.internal.declarationsync")

local M = {}

M.setup = function(opts)
  opts = opts or {}
  opts.lib_resolver = opts.lib_resolver or libresolvers.by_extension_lib_resolver
  config.setup(opts)
end

M.sync_declaration_and_definition = decl_sync.sync_declaration_and_definition

M.insert_definition = decl_sync.insert_definition

return M
