local config = require("cpp-companion.internal.config")
local decl_sync = require("cpp-companion.internal.declarationsync")

local M = {}

M.setup = config.setup

M.sync_declaration_and_definition = decl_sync.sync_declaration_and_definition

M.insert_definition = decl_sync.insert_definition

return M
