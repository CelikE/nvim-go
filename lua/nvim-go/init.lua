-- lua/nvim-go/init.lua
-- Main module for nvim-go plugin
-- Provides the setup function and exports all submodules

local M = {}

-- Plugin version
M.version = "1.0.0"

--- Setup the nvim-go plugin with user configuration.
---@param opts table|nil User configuration options
function M.setup(opts)
  local config = require("nvim-go.config")
  config.setup(opts)

  -- Initialize treesitter queries if available
  local ok, _ = pcall(require, "nvim-treesitter")
  if ok then
    require("nvim-go.treesitter").setup()
  end
end

-- Export submodules for programmatic access
M.constructor = require("nvim-go.constructor")
M.builder = require("nvim-go.builder")
M.tags = require("nvim-go.tags")
M.accessor = require("nvim-go.accessor")
M.interface = require("nvim-go.interface")
M.test = require("nvim-go.test")
M.mock = require("nvim-go.mock")
M.error = require("nvim-go.error")
M.enum = require("nvim-go.enum")
M.struct = require("nvim-go.struct")
M.receiver = require("nvim-go.receiver")
M.imports = require("nvim-go.imports")
M.doc = require("nvim-go.doc")
M.action = require("nvim-go.action")

return M
