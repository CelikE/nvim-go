-- lua/nvim-go/enum.lua
-- Enum (iota) generation for Go

local ts = require("nvim-go.treesitter")
local util = require("nvim-go.util")

local M = {}

--- Generate String() method for an enum at cursor.
---@param opts table|nil Command options
function M.generate(opts)
  opts = opts or {}
  local bufnr = vim.api.nvim_get_current_buf()

  if vim.bo[bufnr].filetype ~= "go" then
    util.notify("Not a Go file", vim.log.levels.WARN)
    return
  end

  local enum = ts.get_enum_at_cursor(bufnr)
  if not enum then
    util.notify("No enum (const with iota) found at cursor", vim.log.levels.WARN)
    return
  end

  if not enum.type_name then
    vim.ui.input({ prompt = "Enum type name: " }, function(type_name)
      if type_name and type_name ~= "" then
        enum.type_name = type_name
        M.insert_enum_methods(bufnr, enum)
      end
    end)
  else
    M.insert_enum_methods(bufnr, enum)
  end
end

--- Insert enum methods into buffer.
---@param bufnr number Buffer number
---@param enum table Enum info
function M.insert_enum_methods(bufnr, enum)
  local lines = M.build_string_method(enum)

  util.insert_lines(bufnr, enum.end_row, lines)

  vim.schedule(function()
    util.format_buffer(bufnr)
  end)

  util.notify("Generated String() for " .. enum.type_name)
end

--- Build String() method for an enum type.
---@param enum table Enum info with type_name and values
---@return string[] Lines of code
function M.build_string_method(enum)
  local lines = {}
  local type_name = enum.type_name
  local receiver = util.receiver_name(type_name)
  local values = enum.values

  -- Build string array
  table.insert(lines, "")
  local var_name = util.unexport_name(type_name) .. "Strings"

  table.insert(
    lines,
    string.format("// %s maps %s values to their string representations.", var_name, type_name)
  )
  table.insert(lines, string.format("var %s = [...]string{", var_name))

  for _, value in ipairs(values) do
    -- Convert constant name to readable string
    local str_value = M.format_enum_string(value, type_name)
    table.insert(lines, string.format('\t"%s",', str_value))
  end

  table.insert(lines, "}")
  table.insert(lines, "")

  -- String method
  table.insert(
    lines,
    string.format("// String returns the string representation of %s.", type_name)
  )
  table.insert(
    lines,
    string.format("func (%s %s) String() string {", receiver, type_name)
  )
  table.insert(
    lines,
    string.format("\tif %s < 0 || int(%s) >= len(%s) {", receiver, receiver, var_name)
  )
  table.insert(
    lines,
    string.format('\t\treturn fmt.Sprintf("%s(%%d)", %s)', type_name, receiver)
  )
  table.insert(lines, "\t}")
  table.insert(lines, string.format("\treturn %s[%s]", var_name, receiver))
  table.insert(lines, "}")

  return lines
end

--- Format an enum constant name as a readable string.
---@param name string Constant name
---@param type_name string Type name to strip
---@return string Formatted string
function M.format_enum_string(name, type_name)
  -- Remove type prefix if present
  local str = name

  if str:sub(1, #type_name) == type_name then
    str = str:sub(#type_name + 1)
  end

  -- Convert to readable format
  -- StatusPending -> Pending
  -- STATUS_PENDING -> Pending

  -- Handle SCREAMING_SNAKE_CASE
  if str:match("^[A-Z_]+$") then
    str = str:lower():gsub("_(%l)", function(c)
      return c:upper()
    end):gsub("^%l", string.upper)
  end

  -- Handle PascalCase - add spaces between words
  str = str:gsub("(%l)(%u)", "%1 %2")

  return str
end

--- Generate a complete enum type with iota.
---@param opts table|nil Command options
function M.generate_enum_type(opts)
  opts = opts or {}
  local bufnr = vim.api.nvim_get_current_buf()

  if vim.bo[bufnr].filetype ~= "go" then
    util.notify("Not a Go file", vim.log.levels.WARN)
    return
  end

  vim.ui.input({ prompt = "Enum type name: " }, function(type_name)
    if not type_name or type_name == "" then
      return
    end

    vim.ui.input({ prompt = "Values (comma-separated): " }, function(values_str)
      if not values_str or values_str == "" then
        return
      end

      local values = {}
      for value in values_str:gmatch("[^,]+") do
        local trimmed = value:match("^%s*(.-)%s*$")
        if trimmed ~= "" then
          table.insert(values, trimmed)
        end
      end

      if #values == 0 then
        util.notify("No values provided", vim.log.levels.WARN)
        return
      end

      local lines = M.build_enum_type(type_name, values)

      local cursor = vim.api.nvim_win_get_cursor(0)
      local row = cursor[1] - 1

      util.insert_lines(bufnr, row, lines)

      vim.schedule(function()
        util.format_buffer(bufnr)
      end)

      util.notify("Generated enum type " .. type_name)
    end)
  end)
end

--- Build a complete enum type definition.
---@param type_name string Type name
---@param values string[] Enum values
---@return string[] Lines of code
function M.build_enum_type(type_name, values)
  local lines = {}

  -- Type definition
  table.insert(lines, "")
  table.insert(
    lines,
    string.format("// %s represents...", type_name)
  )
  table.insert(lines, string.format("type %s int", type_name))
  table.insert(lines, "")

  -- Const block
  table.insert(lines, string.format("// %s values.", type_name))
  table.insert(lines, "const (")

  for i, value in ipairs(values) do
    local const_name = type_name .. util.export_name(value)
    if i == 1 then
      table.insert(lines, string.format("\t%s %s = iota", const_name, type_name))
    else
      table.insert(lines, string.format("\t%s", const_name))
    end
  end

  table.insert(lines, ")")

  -- Build enum info for String method
  local enum = {
    type_name = type_name,
    values = {},
  }

  for _, value in ipairs(values) do
    table.insert(enum.values, type_name .. util.export_name(value))
  end

  -- Add String method
  local string_lines = M.build_string_method(enum)
  for _, line in ipairs(string_lines) do
    table.insert(lines, line)
  end

  return lines
end

--- Generate IsValid method for an enum.
---@param opts table|nil Options
function M.generate_is_valid(opts)
  opts = opts or {}
  local bufnr = vim.api.nvim_get_current_buf()

  local enum = ts.get_enum_at_cursor(bufnr)
  if not enum or not enum.type_name then
    util.notify("No enum found at cursor", vim.log.levels.WARN)
    return
  end

  local lines = M.build_is_valid_method(enum)

  util.insert_lines(bufnr, enum.end_row, lines)

  vim.schedule(function()
    util.format_buffer(bufnr)
  end)

  util.notify("Generated IsValid() for " .. enum.type_name)
end

--- Build IsValid method for an enum.
---@param enum table Enum info
---@return string[] Lines of code
function M.build_is_valid_method(enum)
  local lines = {}
  local type_name = enum.type_name
  local receiver = util.receiver_name(type_name)
  local max_value = enum.values[#enum.values]

  table.insert(lines, "")
  table.insert(
    lines,
    string.format("// IsValid returns true if %s is a valid value.", receiver)
  )
  table.insert(
    lines,
    string.format("func (%s %s) IsValid() bool {", receiver, type_name)
  )
  table.insert(
    lines,
    string.format("\treturn %s >= 0 && %s <= %s", receiver, receiver, max_value)
  )
  table.insert(lines, "}")

  return lines
end

return M
