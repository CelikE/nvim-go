-- lua/nvim-go/error.lua
-- Custom error type generation for Go

local util = require("nvim-go.util")

local M = {}

--- Generate a custom error type.
---@param opts table|nil Command options
function M.generate(opts)
  opts = opts or {}
  local bufnr = vim.api.nvim_get_current_buf()

  if vim.bo[bufnr].filetype ~= "go" then
    util.notify("Not a Go file", vim.log.levels.WARN)
    return
  end

  vim.ui.input({ prompt = "Error type name: " }, function(name)
    if not name or name == "" then
      return
    end

    vim.ui.input({ prompt = "Error message field (leave empty for simple): " }, function(msg_field)
      local lines
      if msg_field and msg_field ~= "" then
        lines = M.build_error_with_fields(name, msg_field)
      else
        lines = M.build_simple_error(name)
      end

      local cursor = vim.api.nvim_win_get_cursor(0)
      local row = cursor[1] - 1

      util.insert_lines(bufnr, row, lines)

      vim.schedule(function()
        util.format_buffer(bufnr)
      end)

      util.notify("Generated error type " .. name)
    end)
  end)
end

--- Build a simple sentinel error.
---@param name string Error name
---@return string[] Lines of code
function M.build_simple_error(name)
  local lines = {}
  local var_name = "Err" .. util.export_name(name)
  local msg = util.to_snake_case(name):gsub("_", " ")

  table.insert(lines, "")
  table.insert(
    lines,
    string.format("// %s is returned when...", var_name)
  )
  table.insert(
    lines,
    string.format('var %s = errors.New("%s")', var_name, msg)
  )

  return lines
end

--- Build an error type with fields.
---@param name string Error type name
---@param msg_field string Message field name
---@return string[] Lines of code
function M.build_error_with_fields(name, msg_field)
  local lines = {}
  local type_name = util.export_name(name) .. "Error"
  local receiver = util.receiver_name(type_name)

  -- Error type struct
  table.insert(lines, "")
  table.insert(
    lines,
    string.format("// %s represents an error when...", type_name)
  )
  table.insert(lines, string.format("type %s struct {", type_name))
  table.insert(lines, string.format("\t%s string", msg_field))
  table.insert(lines, "\tErr error // Wrapped error")
  table.insert(lines, "}")
  table.insert(lines, "")

  -- Error method
  table.insert(
    lines,
    string.format("// Error implements the error interface.")
  )
  table.insert(
    lines,
    string.format("func (%s *%s) Error() string {", receiver, type_name)
  )
  table.insert(
    lines,
    string.format("\tif %s.Err != nil {", receiver)
  )
  table.insert(
    lines,
    string.format(
      '\t\treturn fmt.Sprintf("%%s: %%v", %s.%s, %s.Err)',
      receiver,
      msg_field,
      receiver
    )
  )
  table.insert(lines, "\t}")
  table.insert(lines, string.format("\treturn %s.%s", receiver, msg_field))
  table.insert(lines, "}")
  table.insert(lines, "")

  -- Unwrap method for errors.Is/As support
  table.insert(
    lines,
    string.format("// Unwrap returns the wrapped error.")
  )
  table.insert(
    lines,
    string.format("func (%s *%s) Unwrap() error {", receiver, type_name)
  )
  table.insert(lines, string.format("\treturn %s.Err", receiver))
  table.insert(lines, "}")

  return lines
end

--- Generate error wrapping helper.
---@param opts table|nil Options
function M.generate_wrap_helper(opts)
  opts = opts or {}
  local bufnr = vim.api.nvim_get_current_buf()

  local lines = {
    "",
    "// wrapError wraps an error with additional context.",
    "func wrapError(err error, msg string) error {",
    "\tif err == nil {",
    "\t\treturn nil",
    "\t}",
    '\treturn fmt.Errorf("%s: %w", msg, err)',
    "}",
  }

  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1

  util.insert_lines(bufnr, row, lines)

  vim.schedule(function()
    util.format_buffer(bufnr)
  end)

  util.notify("Generated error wrap helper")
end

--- Generate a set of related sentinel errors.
---@param opts table|nil Options
function M.generate_sentinel_errors(opts)
  opts = opts or {}
  local bufnr = vim.api.nvim_get_current_buf()

  vim.ui.input({ prompt = "Base name for errors (e.g., User): " }, function(base_name)
    if not base_name or base_name == "" then
      return
    end

    local lines = M.build_sentinel_errors(base_name)

    local cursor = vim.api.nvim_win_get_cursor(0)
    local row = cursor[1] - 1

    util.insert_lines(bufnr, row, lines)

    vim.schedule(function()
      util.format_buffer(bufnr)
    end)

    util.notify("Generated sentinel errors for " .. base_name)
  end)
end

--- Build common sentinel errors for a domain.
---@param base_name string Base name for errors
---@return string[] Lines of code
function M.build_sentinel_errors(base_name)
  local lines = {}
  local base = util.export_name(base_name)

  local errors_list = {
    { name = "NotFound", msg = " not found" },
    { name = "AlreadyExists", msg = " already exists" },
    { name = "Invalid", msg = " is invalid" },
    { name = "Unauthorized", msg = " access unauthorized" },
    { name = "Forbidden", msg = " access forbidden" },
  }

  table.insert(lines, "")
  table.insert(lines, string.format("// %s errors.", base))
  table.insert(lines, "var (")

  for _, err in ipairs(errors_list) do
    local var_name = "Err" .. base .. err.name
    local msg = base:lower() .. err.msg

    table.insert(
      lines,
      string.format('\t%s = errors.New("%s")', var_name, msg)
    )
  end

  table.insert(lines, ")")

  return lines
end

return M
