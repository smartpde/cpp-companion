local M = {}
---
---@class MinPlugin A plugin to download and register on the package path
---@alias PluginName string The plugin name, will be used as part of the git clone destination
---@alias PluginUrl string The git url at which a plugin is located, can be a path. See https://git-scm.com/book/en/v2/Git-on-the-Server-The-Protocols for details
---@alias MinPlugins table<PluginName, PluginUrl>

-- Gets the current directory of this file
local base_root_path = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
---Gets the root directory of the minimal init and if path is specified appends the given path to the root allowing for
---subdirectories within the current cwd
---@param path string? The additional path to append to the root, not required
---@return string root The root path suffixed with the path provided or an empty suffix if none was given
function M.root(path)
  return base_root_path .. "/.deps/" .. (path or "")
end

local function head(path)
  return vim.fn.fnamemodify(path, ":h")
end

---Downloads a plugin from a given url and registers it on the "runtimepath"
---@param plugin_name PluginName
---@param plugin_url PluginUrl
function M.load_plugin(plugin_name, plugin_url)
  local package_root = M.root("plugins/")
  local install_destination = package_root .. plugin_name
  vim.opt.runtimepath:append(install_destination)

  if not vim.loop.fs_stat(package_root) then
    vim.fn.mkdir(package_root, "p")
  end

  -- If the plugin install path already exists, we don't need to clone it again.
  if not vim.loop.fs_stat(install_destination) then
    print(string.format(">> Downloading plugin '%s' to '%s'", plugin_name, install_destination))
    vim.fn.system({
      "git",
      "clone",
      "--depth=1",
      plugin_url,
      install_destination,
    })
    if vim.v.shell_error > 0 then
      error(
        string.format(">> Failed to clone plugin: '%s' to '%s'!", plugin_name, install_destination),
        vim.log.levels.ERROR
      )
    end
  end
end

---Do the initial setup. Downloads plugins, ensures the minimal init does not pollute the filesystem by keeping
---everything self contained to the CWD of the minimal init file. Run prior to running tests, reproducing issues, etc.
---@param plugins? MinPlugins
function M.setup(plugins)
  vim.opt.packpath = {} -- Empty the package path so we use only the plugins specified

  -- Install required plugins
  if plugins ~= nil then
    for plugin_name, plugin_url in pairs(plugins) do
      M.load_plugin(plugin_name, plugin_url)
    end
  end
end

M.setup({
  plenary = "https://github.com/nvim-lua/plenary.nvim.git",
  treesitter = "https://github.com/nvim-treesitter/nvim-treesitter",
  debuglog = "https://github.com/smartpde/debuglog"
})
vim.cmd([[
runtime! plugin/plenary.vim
]])

-- WARN: Do all plugin setup, test runs, reproductions, etc. AFTER calling setup with a list of plugins!
-- Basically, do all that stuff AFTER this line.

--## Set proper settings ##
-- Register plugin on the runtimepath, base_root_path is the directory where this file exists
vim.opt.runtimepath:prepend(head(base_root_path))
vim.opt.termguicolors = true

require("debuglog").setup()
require("nvim-treesitter.configs").setup({
  ensure_installed = { "cpp" },
  sync_install = true,
})

require("cpp-companion").setup({
  enable_debugging = true,
})
