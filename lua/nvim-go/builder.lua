-- lua/nvim-go/builder.lua
-- Builder pattern generation for Go structs

local ts = require("nvim-go.treesitter")
local util = require("nvim-go.util")

local M = {}

--- Generate a builder pattern for the struct at cursor.
---@param opts table|nil Command options
function M.generate(opts)
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

  local lines = M.build_builder(struct)
  util.insert_lines(bufnr, struct.end_row, lines)

  vim.schedule(function()
    util.format_buffer(bufnr)
  end)

  util.notify("Generated builder for " .. struct.name)
end

--- Build builder pattern code.
---@param struct table Struct info from treesitter
---@return string[] Lines of code
function M.build_builder(struct)
  local lines = {}
  local struct_name = struct.name
  local builder_name = struct_name .. "Builder"
  local receiver = util.receiver_name(builder_name)

  -- Builder struct definition
  table.insert(lines, "")
  table.insert(
    lines,
    string.format("// %s provides a fluent interface for building %s.", builder_name, struct_name)
  )
  table.insert(lines, string.format("type %s struct {", builder_name))

  for _, field in ipairs(struct.fields) do
    if not field.embedded then
      for _, name in ipairs(field.names) do
        local private_name = util.unexport_name(name)
        table.insert(lines, string.format("\t%s %s", private_name, field.type_str))
      end
    end
  end

  table.insert(lines, "}")
  table.insert(lines, "")

  -- NewBuilder function
  table.insert(
    lines,
    string.format("// New%s creates a new %s.", builder_name, builder_name)
  )
  table.insert(lines, string.format("func New%s() *%s {", builder_name, builder_name))
  table.insert(lines, string.format("\treturn &%s{}", builder_name))
  table.insert(lines, "}")

  -- Setter methods for each field
  for _, field in ipairs(struct.fields) do
    if not field.embedded then
      for _, name in ipairs(field.names) do
        local private_name = util.unexport_name(name)
        local method_name = util.export_name(name)
        local param_name = private_name

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
            "func (%s *%s) %s(%s %s) *%s {",
            receiver,
            builder_name,
            method_name,
            param_name,
            field.type_str,
            builder_name
          )
        )
        table.insert(
          lines,
          string.format("\t%s.%s = %s", receiver, private_name, param_name)
        )
        table.insert(lines, string.format("\treturn %s", receiver))
        table.insert(lines, "}")
      end
    end
  end

  -- Build method
  table.insert(lines, "")
  table.insert(
    lines,
    string.format("// Build creates a %s from the builder.", struct_name)
  )
  table.insert(
    lines,
    string.format("func (%s *%s) Build() *%s {", receiver, builder_name, struct_name)
  )
  table.insert(lines, string.format("\treturn &%s{", struct_name))

  for _, field in ipairs(struct.fields) do
    if not field.embedded then
      for _, name in ipairs(field.names) do
        local private_name = util.unexport_name(name)
        table.insert(
          lines,
          string.format("\t\t%s: %s.%s,", name, receiver, private_name)
        )
      end
    end
  end

  table.insert(lines, "\t}")
  table.insert(lines, "}")

  return lines
end

return M
