-- lua/nvim-go/mock.lua
-- Mock generation for Go interfaces

local ts = require("nvim-go.treesitter")
local util = require("nvim-go.util")

local M = {}

--- Generate a mock implementation for an interface.
---@param opts table|nil Command options
function M.generate(opts)
  opts = opts or {}
  local bufnr = vim.api.nvim_get_current_buf()

  if vim.bo[bufnr].filetype ~= "go" then
    util.notify("Not a Go file", vim.log.levels.WARN)
    return
  end

  local iface = ts.get_interface_at_cursor(bufnr)
  if not iface then
    util.notify("No interface found at cursor", vim.log.levels.WARN)
    return
  end

  local lines = M.build_mock(iface)

  util.insert_lines(bufnr, iface.end_row, lines)

  vim.schedule(function()
    util.format_buffer(bufnr)
  end)

  util.notify("Generated mock for " .. iface.name)
end

--- Build mock implementation for an interface.
---@param iface table Interface info
---@return string[] Lines of code
function M.build_mock(iface)
  local lines = {}
  local iface_name = iface.name
  local mock_name = "Mock" .. iface_name
  local receiver = util.receiver_name(mock_name)

  -- Mock struct with function fields
  table.insert(lines, "")
  table.insert(
    lines,
    string.format("// %s is a mock implementation of %s.", mock_name, iface_name)
  )
  table.insert(lines, string.format("type %s struct {", mock_name))

  for _, method in ipairs(iface.methods) do
    local func_field = method.name .. "Func"

    -- Build function type
    local param_types = {}
    for _, param in ipairs(method.params or {}) do
      table.insert(param_types, param.type_str)
    end
    local param_str = table.concat(param_types, ", ")

    local result_str = method.result or ""

    if result_str ~= "" then
      table.insert(
        lines,
        string.format("\t%s func(%s) %s", func_field, param_str, result_str)
      )
    else
      table.insert(lines, string.format("\t%s func(%s)", func_field, param_str))
    end

    -- Add call tracking
    local calls_field = method.name .. "Calls"
    table.insert(lines, string.format("\t%s int", calls_field))
  end

  table.insert(lines, "}")
  table.insert(lines, "")

  -- Compile-time interface check
  table.insert(
    lines,
    string.format("var _ %s = (*%s)(nil)", iface_name, mock_name)
  )

  -- Method implementations
  for _, method in ipairs(iface.methods) do
    table.insert(lines, "")

    -- Build parameters with names
    local param_parts = {}
    local arg_names = {}

    for _, param in ipairs(method.params or {}) do
      for _, name in ipairs(param.names or {}) do
        table.insert(param_parts, name .. " " .. param.type_str)
        table.insert(arg_names, name)
      end
      -- Handle unnamed parameters
      if #param.names == 0 then
        local arg_name = "arg" .. #arg_names
        table.insert(param_parts, arg_name .. " " .. param.type_str)
        table.insert(arg_names, arg_name)
      end
    end
    local param_str = table.concat(param_parts, ", ")
    local args_str = table.concat(arg_names, ", ")

    local result_str = method.result or ""

    -- Method signature
    if result_str ~= "" then
      table.insert(
        lines,
        string.format(
          "func (%s *%s) %s(%s) %s {",
          receiver,
          mock_name,
          method.name,
          param_str,
          result_str
        )
      )
    else
      table.insert(
        lines,
        string.format(
          "func (%s *%s) %s(%s) {",
          receiver,
          mock_name,
          method.name,
          param_str
        )
      )
    end

    -- Increment call counter
    table.insert(
      lines,
      string.format("\t%s.%sCalls++", receiver, method.name)
    )

    -- Call the mock function if set
    local func_field = method.name .. "Func"

    table.insert(
      lines,
      string.format("\tif %s.%s != nil {", receiver, func_field)
    )

    if result_str ~= "" then
      table.insert(
        lines,
        string.format("\t\treturn %s.%s(%s)", receiver, func_field, args_str)
      )
    else
      table.insert(
        lines,
        string.format("\t\t%s.%s(%s)", receiver, func_field, args_str)
      )
      table.insert(lines, "\t\treturn")
    end

    table.insert(lines, "\t}")

    -- Default return
    if result_str ~= "" then
      local default_return = M.build_default_return(result_str)
      table.insert(lines, "\treturn " .. default_return)
    end

    table.insert(lines, "}")
  end

  return lines
end

--- Build default return values for a result type.
---@param result_str string Result type string
---@return string Default return expression
function M.build_default_return(result_str)
  -- Handle parenthesized multiple returns
  if result_str:match("^%(") then
    local parts = {}
    for ret_type in result_str:gmatch("[%w%*%[%]%.]+") do
      table.insert(parts, util.zero_value(ret_type))
    end
    return table.concat(parts, ", ")
  end

  return util.zero_value(result_str)
end

--- Generate mock in a separate mock file.
---@param opts table|nil Options
function M.generate_mock_file(opts)
  opts = opts or {}
  local bufnr = vim.api.nvim_get_current_buf()

  local iface = ts.get_interface_at_cursor(bufnr)
  if not iface then
    util.notify("No interface found at cursor", vim.log.levels.WARN)
    return
  end

  local file_path = util.get_file_path(bufnr)
  local dir = util.get_file_dir(bufnr)
  local mock_file = dir .. "/mock_" .. iface.name:lower() .. ".go"

  local pkg_name = ts.get_package_name(bufnr) or "main"

  local lines = {
    string.format("package %s", pkg_name),
    "",
    "// Code generated by nvim-go. DO NOT EDIT.",
    "",
  }

  -- Add mock implementation
  local mock_lines = M.build_mock(iface)
  for _, line in ipairs(mock_lines) do
    table.insert(lines, line)
  end

  vim.fn.writefile(lines, mock_file)
  vim.cmd("edit " .. mock_file)

  vim.schedule(function()
    util.format_buffer()
  end)

  util.notify("Created " .. vim.fn.fnamemodify(mock_file, ":t"))
end

return M
