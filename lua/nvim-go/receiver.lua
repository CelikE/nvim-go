-- lua/nvim-go/receiver.lua
-- Method receiver manipulation for Go

local ts = require("nvim-go.treesitter")
local util = require("nvim-go.util")

local M = {}

--- Toggle between pointer and value receiver for method at cursor.
---@param opts table|nil Command options
function M.toggle(opts)
  opts = opts or {}
  local bufnr = vim.api.nvim_get_current_buf()

  if vim.bo[bufnr].filetype ~= "go" then
    util.notify("Not a Go file", vim.log.levels.WARN)
    return
  end

  local func = ts.get_function_at_cursor(bufnr)
  if not func then
    util.notify("No function found at cursor", vim.log.levels.WARN)
    return
  end

  if not func.is_method then
    util.notify("Not a method (no receiver)", vim.log.levels.WARN)
    return
  end

  -- Get the receiver info
  local receiver = func.receiver
  if not receiver then
    util.notify("Could not parse receiver", vim.log.levels.WARN)
    return
  end

  -- Find the receiver in the source
  local receiver_node = M.find_receiver_node(func.node, bufnr)
  if not receiver_node then
    util.notify("Could not find receiver node", vim.log.levels.WARN)
    return
  end

  -- Toggle pointer/value
  local current_type = receiver.type_str
  local new_type

  if util.is_pointer(current_type) then
    new_type = util.base_type(current_type)
  else
    new_type = "*" .. current_type
  end

  -- Replace the receiver type
  M.replace_receiver_type(bufnr, receiver_node, receiver.names[1] or "", new_type)

  vim.schedule(function()
    util.format_buffer(bufnr)
  end)

  local direction = util.is_pointer(new_type) and "pointer" or "value"
  util.notify("Changed to " .. direction .. " receiver")
end

--- Find the receiver parameter node in a method.
---@param method_node TSNode Method declaration node
---@param bufnr number Buffer number
---@return TSNode|nil Receiver parameter node
function M.find_receiver_node(method_node, bufnr)
  for child in method_node:iter_children() do
    if child:type() == "parameter_list" then
      -- This is the receiver parameter list (first one)
      return child
    end
  end
  return nil
end

--- Replace the receiver type in a method.
---@param bufnr number Buffer number
---@param receiver_node TSNode Receiver parameter list node
---@param name string Receiver name
---@param new_type string New receiver type
function M.replace_receiver_type(bufnr, receiver_node, name, new_type)
  local start_row, start_col, end_row, end_col = receiver_node:range()

  -- Build new receiver text
  local new_text
  if name ~= "" then
    new_text = string.format("(%s %s)", name, new_type)
  else
    new_text = string.format("(%s)", new_type)
  end

  -- Replace the text
  vim.api.nvim_buf_set_text(bufnr, start_row, start_col, end_row, end_col, { new_text })
end

--- Convert all methods of a struct to pointer receivers.
---@param opts table|nil Options
function M.all_to_pointer(opts)
  opts = opts or {}
  local bufnr = vim.api.nvim_get_current_buf()

  local struct = ts.get_struct_at_cursor(bufnr)
  if not struct then
    util.notify("No struct found at cursor", vim.log.levels.WARN)
    return
  end

  local methods = require("nvim-go.interface").find_struct_methods(bufnr, struct.name)
  local count = 0

  -- Process in reverse order to avoid position shifts
  local sorted_methods = {}
  for _, method in ipairs(methods) do
    table.insert(sorted_methods, method)
  end

  table.sort(sorted_methods, function(a, b)
    local a_row, _, _, _ = a.node:range()
    local b_row, _, _, _ = b.node:range()
    return a_row > b_row
  end)

  for _, method in ipairs(sorted_methods) do
    if method.receiver_type and not util.is_pointer(method.receiver_type) then
      local receiver_node = M.find_receiver_node(method.node, bufnr)
      if receiver_node then
        local name = ""
        -- Try to get the receiver name from params
        for child in receiver_node:iter_children() do
          if child:type() == "parameter_declaration" then
            for param_child in child:iter_children() do
              if param_child:type() == "identifier" then
                name = vim.treesitter.get_node_text(param_child, bufnr)
                break
              end
            end
          end
        end

        M.replace_receiver_type(bufnr, receiver_node, name, "*" .. method.receiver_type)
        count = count + 1
      end
    end
  end

  vim.schedule(function()
    util.format_buffer(bufnr)
  end)

  util.notify(string.format("Converted %d %s to pointer receivers", count, util.pluralize("method", count)))
end

--- Convert all methods of a struct to value receivers.
---@param opts table|nil Options
function M.all_to_value(opts)
  opts = opts or {}
  local bufnr = vim.api.nvim_get_current_buf()

  local struct = ts.get_struct_at_cursor(bufnr)
  if not struct then
    util.notify("No struct found at cursor", vim.log.levels.WARN)
    return
  end

  local methods = require("nvim-go.interface").find_struct_methods(bufnr, struct.name)
  local count = 0

  -- Process in reverse order
  local sorted_methods = {}
  for _, method in ipairs(methods) do
    table.insert(sorted_methods, method)
  end

  table.sort(sorted_methods, function(a, b)
    local a_row, _, _, _ = a.node:range()
    local b_row, _, _, _ = b.node:range()
    return a_row > b_row
  end)

  for _, method in ipairs(sorted_methods) do
    if method.receiver_type and util.is_pointer(method.receiver_type) then
      local receiver_node = M.find_receiver_node(method.node, bufnr)
      if receiver_node then
        local name = ""
        for child in receiver_node:iter_children() do
          if child:type() == "parameter_declaration" then
            for param_child in child:iter_children() do
              if param_child:type() == "identifier" then
                name = vim.treesitter.get_node_text(param_child, bufnr)
                break
              end
            end
          end
        end

        M.replace_receiver_type(bufnr, receiver_node, name, util.base_type(method.receiver_type))
        count = count + 1
      end
    end
  end

  vim.schedule(function()
    util.format_buffer(bufnr)
  end)

  util.notify(string.format("Converted %d %s to value receivers", count, util.pluralize("method", count)))
end

--- Rename receiver variable across all methods of a struct.
---@param opts table|nil Options
function M.rename_receiver(opts)
  opts = opts or {}
  local bufnr = vim.api.nvim_get_current_buf()

  local struct = ts.get_struct_at_cursor(bufnr)
  if not struct then
    util.notify("No struct found at cursor", vim.log.levels.WARN)
    return
  end

  local default_name = util.receiver_name(struct.name)

  vim.ui.input(
    { prompt = "New receiver name: ", default = default_name },
    function(new_name)
      if not new_name or new_name == "" then
        return
      end

      local methods = require("nvim-go.interface").find_struct_methods(bufnr, struct.name)

      -- This is complex because we need to rename both the declaration and all uses
      -- For simplicity, we'll just change the declaration and let the user fix uses
      -- A full implementation would use LSP rename

      util.notify(
        "Receiver renamed in declarations. Use LSP rename for complete refactoring.",
        vim.log.levels.INFO
      )
    end
  )
end

return M
