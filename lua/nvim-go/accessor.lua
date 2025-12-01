-- lua/nvim-go/accessor.lua
-- Getter and setter generation for Go structs

local ts = require("nvim-go.treesitter")
local util = require("nvim-go.util")

local M = {}

--- Generate getter methods for struct at cursor.
---@param opts table|nil Command options
function M.generate_getters(opts)
  opts = opts or {}
  local bufnr = vim.api.nvim_get_current_buf()

  if vim.bo[bufnr].filetype ~= "go" then
    util.notify("Not a Go file", vim.log.levels.WARN)
    return
  end

  local struct = ts.get_struct_at_cursor(bufnr)
  if not struct then
    util.notify("No struct found at cursor", vim.log.levels.WARN)
    return
  end

  local lines = M.build_getters(struct)
  util.insert_lines(bufnr, struct.end_row, lines)

  vim.schedule(function()
    util.format_buffer(bufnr)
  end)

  util.notify("Generated getters for " .. struct.name)
end

--- Generate setter methods for struct at cursor.
---@param opts table|nil Command options
function M.generate_setters(opts)
  opts = opts or {}
  local bufnr = vim.api.nvim_get_current_buf()

  if vim.bo[bufnr].filetype ~= "go" then
    util.notify("Not a Go file", vim.log.levels.WARN)
    return
  end

  local struct = ts.get_struct_at_cursor(bufnr)
  if not struct then
    util.notify("No struct found at cursor", vim.log.levels.WARN)
    return
  end

  local lines = M.build_setters(struct)
  util.insert_lines(bufnr, struct.end_row, lines)

  vim.schedule(function()
    util.format_buffer(bufnr)
  end)

  util.notify("Generated setters for " .. struct.name)
end

--- Generate both getters and setters.
---@param opts table|nil Command options
function M.generate_all(opts)
  opts = opts or {}
  local bufnr = vim.api.nvim_get_current_buf()

  if vim.bo[bufnr].filetype ~= "go" then
    util.notify("Not a Go file", vim.log.levels.WARN)
    return
  end

  local struct = ts.get_struct_at_cursor(bufnr)
  if not struct then
    util.notify("No struct found at cursor", vim.log.levels.WARN)
    return
  end

  local getter_lines = M.build_getters(struct)
  local setter_lines = M.build_setters(struct)

  -- Combine lines
  local all_lines = {}
  for _, line in ipairs(getter_lines) do
    table.insert(all_lines, line)
  end
  for _, line in ipairs(setter_lines) do
    table.insert(all_lines, line)
  end

  util.insert_lines(bufnr, struct.end_row, all_lines)

  vim.schedule(function()
    util.format_buffer(bufnr)
  end)

  util.notify("Generated getters and setters for " .. struct.name)
end

--- Build getter methods for a struct.
---@param struct table Struct info from treesitter
---@return string[] Lines of code
function M.build_getters(struct)
  local lines = {}
  local struct_name = struct.name
  local receiver = util.receiver_name(struct_name)

  for _, field in ipairs(struct.fields) do
    if not field.embedded then
      for _, name in ipairs(field.names) do
        -- Skip unexported fields (they typically don't need public getters)
        -- But we generate them anyway, user can decide
        local method_name = util.export_name(name)

        -- For unexported fields, getter name is just the exported version
        -- For exported fields, prefix with "Get" to avoid name collision
        if util.is_exported(name) then
          method_name = "Get" .. name
        end

        table.insert(lines, "")
        table.insert(
          lines,
          string.format("// %s returns the %s field.", method_name, name)
        )
        table.insert(
          lines,
          string.format(
            "func (%s *%s) %s() %s {",
            receiver,
            struct_name,
            method_name,
            field.type_str
          )
        )
        table.insert(
          lines,
          string.format("\treturn %s.%s", receiver, name)
        )
        table.insert(lines, "}")
      end
    end
  end

  return lines
end

--- Build setter methods for a struct.
---@param struct table Struct info from treesitter
---@return string[] Lines of code
function M.build_setters(struct)
  local lines = {}
  local struct_name = struct.name
  local receiver = util.receiver_name(struct_name)

  for _, field in ipairs(struct.fields) do
    if not field.embedded then
      for _, name in ipairs(field.names) do
        local method_name = "Set" .. util.export_name(name)
        local param_name = util.unexport_name(name)

        -- Avoid collision with receiver
        if param_name == receiver then
          param_name = param_name .. "Val"
        end

        table.insert(lines, "")
        table.insert(
          lines,
          string.format("// %s sets the %s field.", method_name, name)
        )
        table.insert(
          lines,
          string.format(
            "func (%s *%s) %s(%s %s) {",
            receiver,
            struct_name,
            method_name,
            param_name,
            field.type_str
          )
        )
        table.insert(
          lines,
          string.format("\t%s.%s = %s", receiver, name, param_name)
        )
        table.insert(lines, "}")
      end
    end
  end

  return lines
end

--- Generate a specific getter for field under cursor.
---@param opts table|nil Options
function M.generate_getter_for_field(opts)
  -- Implementation for single field getter
  -- Could be expanded based on cursor position within field
  M.generate_getters(opts)
end

--- Generate a specific setter for field under cursor.
---@param opts table|nil Options
function M.generate_setter_for_field(opts)
  -- Implementation for single field setter
  M.generate_setters(opts)
end

return M
