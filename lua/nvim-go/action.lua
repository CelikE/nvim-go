-- lua/nvim-go/action.lua
-- Code actions menu for Go

local ts = require("nvim-go.treesitter")
local util = require("nvim-go.util")

local M = {}

---@class GoAction
---@field title string Action title
---@field fn function Action function
---@field available function|nil Check if action is available

--- Show available code actions at cursor.
---@param opts table|nil Command options
function M.show(opts)
  opts = opts or {}
  local bufnr = vim.api.nvim_get_current_buf()

  if vim.bo[bufnr].filetype ~= "go" then
    util.notify("Not a Go file", vim.log.levels.WARN)
    return
  end

  local actions = M.get_available_actions(bufnr)

  if #actions == 0 then
    util.notify("No code actions available", vim.log.levels.INFO)
    return
  end

  -- Build selection list
  local items = {}
  for _, action in ipairs(actions) do
    table.insert(items, action.title)
  end

  vim.ui.select(items, {
    prompt = "Go Code Actions:",
    format_item = function(item)
      return item
    end,
  }, function(choice, idx)
    if choice and idx then
      local action = actions[idx]
      if action.fn then
        action.fn()
      end
    end
  end)
end

--- Get available actions for the current cursor position.
---@param bufnr number Buffer number
---@return GoAction[] List of available actions
function M.get_available_actions(bufnr)
  local actions = {}

  -- Check what's at cursor
  local struct = ts.get_struct_at_cursor(bufnr)
  local func = ts.get_function_at_cursor(bufnr)
  local iface = ts.get_interface_at_cursor(bufnr)
  local enum = ts.get_enum_at_cursor(bufnr)

  -- Struct actions
  if struct then
    table.insert(actions, {
      title = "Generate constructor",
      fn = function()
        require("nvim-go.constructor").generate()
      end,
    })

    table.insert(actions, {
      title = "Generate builder pattern",
      fn = function()
        require("nvim-go.builder").generate()
      end,
    })

    table.insert(actions, {
      title = "Generate functional options constructor",
      fn = function()
        require("nvim-go.constructor").generate_with_options()
      end,
    })

    table.insert(actions, {
      title = "Add JSON tags",
      fn = function()
        require("nvim-go.tags").add_json()
      end,
    })

    table.insert(actions, {
      title = "Add YAML tags",
      fn = function()
        require("nvim-go.tags").add_yaml()
      end,
    })

    table.insert(actions, {
      title = "Add DB tags",
      fn = function()
        require("nvim-go.tags").add_db()
      end,
    })

    table.insert(actions, {
      title = "Add all tags (JSON, YAML, DB)",
      fn = function()
        require("nvim-go.tags").add_all()
      end,
    })

    table.insert(actions, {
      title = "Remove all tags",
      fn = function()
        require("nvim-go.tags").remove_all()
      end,
    })

    table.insert(actions, {
      title = "Generate getters",
      fn = function()
        require("nvim-go.accessor").generate_getters()
      end,
    })

    table.insert(actions, {
      title = "Generate setters",
      fn = function()
        require("nvim-go.accessor").generate_setters()
      end,
    })

    table.insert(actions, {
      title = "Generate getters and setters",
      fn = function()
        require("nvim-go.accessor").generate_all()
      end,
    })

    table.insert(actions, {
      title = "Implement interface",
      fn = function()
        require("nvim-go.interface").implement()
      end,
    })

    table.insert(actions, {
      title = "Extract interface from methods",
      fn = function()
        require("nvim-go.interface").extract()
      end,
    })

    table.insert(actions, {
      title = "Generate documentation",
      fn = function()
        require("nvim-go.doc").generate()
      end,
    })

    table.insert(actions, {
      title = "Add field to struct",
      fn = function()
        require("nvim-go.struct").add_field()
      end,
    })

    table.insert(actions, {
      title = "Convert all methods to pointer receivers",
      fn = function()
        require("nvim-go.receiver").all_to_pointer()
      end,
    })

    table.insert(actions, {
      title = "Convert all methods to value receivers",
      fn = function()
        require("nvim-go.receiver").all_to_value()
      end,
    })
  end

  -- Function/method actions
  if func then
    table.insert(actions, {
      title = "Generate test",
      fn = function()
        require("nvim-go.test").generate()
      end,
    })

    table.insert(actions, {
      title = "Generate benchmark",
      fn = function()
        require("nvim-go.test").generate_benchmark()
      end,
    })

    table.insert(actions, {
      title = "Generate documentation",
      fn = function()
        require("nvim-go.doc").generate()
      end,
    })

    if func.is_method then
      table.insert(actions, {
        title = "Toggle pointer/value receiver",
        fn = function()
          require("nvim-go.receiver").toggle()
        end,
      })
    end
  end

  -- Interface actions
  if iface then
    table.insert(actions, {
      title = "Generate mock",
      fn = function()
        require("nvim-go.mock").generate()
      end,
    })

    table.insert(actions, {
      title = "Generate mock in separate file",
      fn = function()
        require("nvim-go.mock").generate_mock_file()
      end,
    })

    table.insert(actions, {
      title = "Implement interface for struct",
      fn = function()
        require("nvim-go.interface").implement()
      end,
    })

    table.insert(actions, {
      title = "Generate documentation",
      fn = function()
        require("nvim-go.doc").generate()
      end,
    })
  end

  -- Enum actions
  if enum then
    table.insert(actions, {
      title = "Generate String() method",
      fn = function()
        require("nvim-go.enum").generate()
      end,
    })

    table.insert(actions, {
      title = "Generate IsValid() method",
      fn = function()
        require("nvim-go.enum").generate_is_valid()
      end,
    })
  end

  -- General actions (always available)
  table.insert(actions, {
    title = "Organize imports (Uber style)",
    fn = function()
      require("nvim-go.imports").organize()
    end,
  })

  table.insert(actions, {
    title = "Generate error type",
    fn = function()
      require("nvim-go.error").generate()
    end,
  })

  table.insert(actions, {
    title = "Generate enum type",
    fn = function()
      require("nvim-go.enum").generate_enum_type()
    end,
  })

  table.insert(actions, {
    title = "Generate package documentation",
    fn = function()
      require("nvim-go.doc").generate_package_doc()
    end,
  })

  table.insert(actions, {
    title = "Create test file",
    fn = function()
      require("nvim-go.test").generate_test_file()
    end,
  })

  return actions
end

--- Register with nvim-cmp or other completion sources.
function M.register_completion_source()
  -- Could be extended to provide completion for common patterns
end

return M
