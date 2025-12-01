-- lua/nvim-go/config.lua
-- Configuration management for nvim-go plugin

local M = {}

---@class NvimGoConfig
---@field keymaps NvimGoKeymapConfig
---@field constructor NvimGoConstructorConfig
---@field tags NvimGoTagsConfig
---@field test NvimGoTestConfig
---@field style NvimGoStyleConfig

---@class NvimGoKeymapConfig
---@field enabled boolean
---@field prefix string

---@class NvimGoConstructorConfig
---@field prefix string Constructor function name prefix
---@field comment boolean Add doc comment to constructor

---@class NvimGoTagsConfig
---@field json NvimGoTagConfig
---@field yaml NvimGoTagConfig
---@field db NvimGoTagConfig
---@field validate NvimGoTagConfig

---@class NvimGoTagConfig
---@field transform string Field name transformation: "snakecase", "camelcase", "lispcase", "pascalcase", "keep"
---@field options string[] Additional tag options

---@class NvimGoTestConfig
---@field template string Test template style: "table", "simple"
---@field parallel boolean Generate tests with t.Parallel()

---@class NvimGoStyleConfig
---@field uber boolean Follow Uber Go Style Guide conventions

---@type NvimGoConfig
local defaults = {
  keymaps = {
    enabled = true,
    prefix = "<leader>g",
  },
  constructor = {
    prefix = "New",
    comment = true,
  },
  tags = {
    json = {
      transform = "camelcase",
      options = {},
    },
    yaml = {
      transform = "camelcase",
      options = {},
    },
    db = {
      transform = "snakecase",
      options = {},
    },
    validate = {
      transform = "keep",
      options = {},
    },
  },
  test = {
    template = "table",
    parallel = true,
  },
  style = {
    uber = true,
  },
}

---@type NvimGoConfig
local config = vim.deepcopy(defaults)

--- Setup configuration with user options.
---@param opts table|nil User options to merge with defaults
function M.setup(opts)
  config = vim.tbl_deep_extend("force", defaults, opts or {})
end

--- Get the current configuration.
---@return NvimGoConfig
function M.get()
  return config
end

--- Get a specific configuration value by path.
---@param path string Dot-separated path to config value
---@return any
function M.get_value(path)
  local parts = vim.split(path, ".", { plain = true })
  local value = config

  for _, part in ipairs(parts) do
    if type(value) ~= "table" then
      return nil
    end
    value = value[part]
  end

  return value
end

return M
