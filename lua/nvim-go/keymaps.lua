-- lua/nvim-go/keymaps.lua
-- Keymap configuration for nvim-go

local config = require("nvim-go.config")

local M = {}

--- Default keymap definitions.
---@type table<string, table>
local default_keymaps = {
  -- Code actions
  ["a"] = { cmd = "GoCodeAction", desc = "Show code actions" },

  -- Constructor/Builder
  ["c"] = { cmd = "GoGenConstructor", desc = "Generate constructor" },
  ["b"] = { cmd = "GoGenBuilder", desc = "Generate builder" },

  -- Tags
  ["tj"] = { cmd = "GoAddJsonTags", desc = "Add JSON tags" },
  ["ty"] = { cmd = "GoAddYamlTags", desc = "Add YAML tags" },
  ["td"] = { cmd = "GoAddDbTags", desc = "Add DB tags" },
  ["tv"] = { cmd = "GoAddValidateTags", desc = "Add validate tags" },
  ["ta"] = { cmd = "GoAddAllTags", desc = "Add all tags" },
  ["tr"] = { cmd = "GoRemoveTags", desc = "Remove all tags" },

  -- Accessors
  ["gg"] = { cmd = "GoGenGetters", desc = "Generate getters" },
  ["gs"] = { cmd = "GoGenSetters", desc = "Generate setters" },
  ["ga"] = { cmd = "GoGenGettersSetters", desc = "Generate getters & setters" },

  -- Interface
  ["ii"] = { cmd = "GoImplInterface", desc = "Implement interface" },
  ["ie"] = { cmd = "GoExtractInterface", desc = "Extract interface" },

  -- Testing
  ["tt"] = { cmd = "GoGenTest", desc = "Generate test" },
  ["tb"] = { cmd = "GoGenBenchmark", desc = "Generate benchmark" },
  ["tm"] = { cmd = "GoGenMock", desc = "Generate mock" },

  -- Utilities
  ["e"] = { cmd = "GoGenError", desc = "Generate error type" },
  ["n"] = { cmd = "GoGenEnum", desc = "Generate enum String()" },
  ["f"] = { cmd = "GoFillStruct", desc = "Fill struct" },
  ["r"] = { cmd = "GoToggleReceiver", desc = "Toggle receiver type" },
  ["o"] = { cmd = "GoOrganizeImports", desc = "Organize imports" },
  ["d"] = { cmd = "GoGenDoc", desc = "Generate documentation" },
}

--- Setup buffer-local keymaps for Go files.
---@param bufnr number Buffer number
function M.setup_buffer(bufnr)
  local cfg = config.get()
  local prefix = cfg.keymaps.prefix

  for key, mapping in pairs(default_keymaps) do
    local lhs = prefix .. key
    local rhs = "<cmd>" .. mapping.cmd .. "<CR>"

    vim.keymap.set("n", lhs, rhs, {
      buffer = bufnr,
      desc = "[Go] " .. mapping.desc,
      silent = true,
    })
  end
end

--- Get all keymaps for documentation/which-key.
---@return table Keymap definitions
function M.get_keymaps()
  local cfg = config.get()
  local prefix = cfg.keymaps.prefix
  local result = {}

  for key, mapping in pairs(default_keymaps) do
    result[prefix .. key] = {
      cmd = mapping.cmd,
      desc = mapping.desc,
    }
  end

  return result
end

--- Setup which-key integration.
function M.setup_which_key()
  local ok, wk = pcall(require, "which-key")
  if not ok then
    return
  end

  local cfg = config.get()
  local prefix = cfg.keymaps.prefix

  -- Register group
  wk.register({
    [prefix] = {
      name = "+Go",
      t = { name = "+Tags" },
      g = { name = "+Getters/Setters" },
      i = { name = "+Interface" },
    },
  })
end

return M
