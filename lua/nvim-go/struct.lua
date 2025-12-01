-- lua/nvim-go/struct.lua
-- Struct manipulation utilities for Go

local ts = require("nvim-go.treesitter")
local util = require("nvim-go.util")

local M = {}

--- Fill a struct literal with zero values.
---@param opts table|nil Command options
function M.fill(opts)
  opts = opts or {}
  local bufnr = vim.api.nvim_get_current_buf()

  if vim.bo[bufnr].filetype ~= "go" then
    util.notify("Not a Go file", vim.log.levels.WARN)
    return
  end

  -- Find struct literal at cursor
  local literal = M.get_struct_literal_at_cursor(bufnr)
  if not literal then
    util.notify("No struct literal found at cursor", vim.log.levels.WARN)
    return
  end

  -- Find the struct type definition
  local struct_def = M.find_struct_definition(bufnr, literal.type_name)
  if not struct_def then
    util.notify(
      "Could not find struct definition for " .. literal.type_name,
      vim.log.levels.WARN
    )
    return
  end

  -- Generate filled literal
  local lines = M.build_filled_literal(literal, struct_def)

  util.replace_lines(bufnr, literal.start_row, literal.end_row + 1, lines)

  vim.schedule(function()
    util.format_buffer(bufnr)
  end)

  util.notify("Filled struct literal")
end

--- Toggle struct literal between single and multi-line format.
---@param opts table|nil Command options
function M.split_join(opts)
  opts = opts or {}
  local bufnr = vim.api.nvim_get_current_buf()

  if vim.bo[bufnr].filetype ~= "go" then
    util.notify("Not a Go file", vim.log.levels.WARN)
    return
  end

  local literal = M.get_struct_literal_at_cursor(bufnr)
  if not literal then
    util.notify("No struct literal found at cursor", vim.log.levels.WARN)
    return
  end

  local lines
  if literal.is_multiline then
    lines = M.build_single_line_literal(literal)
  else
    lines = M.build_multi_line_literal(literal)
  end

  util.replace_lines(bufnr, literal.start_row, literal.end_row + 1, lines)

  vim.schedule(function()
    util.format_buffer(bufnr)
  end)
end

--- Get struct literal at cursor position.
---@param bufnr number Buffer number
---@return table|nil Literal info
function M.get_struct_literal_at_cursor(bufnr)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1

  local root = ts.get_root(bufnr)
  if not root then
    return nil
  end

  -- Query for composite literals
  local query_string = [[
    (composite_literal
      type: (_) @type
      body: (literal_value) @body) @literal
  ]]

  local query = vim.treesitter.query.parse("go", query_string)

  for id, node, _ in query:iter_captures(root, bufnr, 0, -1) do
    local capture_name = query.captures[id]

    if capture_name == "literal" then
      local start_row, start_col, end_row, end_col = node:range()

      if row >= start_row and row <= end_row then
        local literal = {
          node = node,
          start_row = start_row,
          start_col = start_col,
          end_row = end_row,
          end_col = end_col,
          is_multiline = end_row > start_row,
          fields = {},
        }

        -- Get type name
        for child_id, child_node, _ in query:iter_captures(node, bufnr, start_row, end_row + 1) do
          local child_name = query.captures[child_id]

          if child_name == "type" then
            literal.type_name = vim.treesitter.get_node_text(child_node, bufnr)
          elseif child_name == "body" then
            literal.fields = M.parse_literal_fields(child_node, bufnr)
          end
        end

        -- Get the full text
        literal.text = vim.treesitter.get_node_text(node, bufnr)

        return literal
      end
    end
  end

  return nil
end

--- Parse fields from a literal_value node.
---@param node TSNode Literal value node
---@param bufnr number Buffer number
---@return table[] Field info list
function M.parse_literal_fields(node, bufnr)
  local fields = {}

  for child in node:iter_children() do
    if child:type() == "keyed_element" then
      local field = {}

      for element_child in child:iter_children() do
        local child_type = element_child:type()

        if child_type == "field_identifier" or child_type == "literal_element" then
          local text = vim.treesitter.get_node_text(element_child, bufnr)
          if not field.name then
            field.name = text
          else
            field.value = text
          end
        else
          local text = vim.treesitter.get_node_text(element_child, bufnr)
          if text ~= ":" then
            field.value = text
          end
        end
      end

      if field.name then
        table.insert(fields, field)
      end
    elseif child:type() == "literal_element" then
      -- Positional element
      local text = vim.treesitter.get_node_text(child, bufnr)
      table.insert(fields, { value = text })
    end
  end

  return fields
end

--- Find struct definition in the buffer.
---@param bufnr number Buffer number
---@param type_name string Struct type name
---@return table|nil Struct info
function M.find_struct_definition(bufnr, type_name)
  -- Handle pointer types
  type_name = util.base_type(type_name)

  -- Handle package-qualified types
  if type_name:match("%.") then
    -- Can't resolve external package types easily
    return nil
  end

  local root = ts.get_root(bufnr)
  if not root then
    return nil
  end

  local query_string = [[
    (type_declaration
      (type_spec
        name: (type_identifier) @name
        type: (struct_type
          (field_declaration_list) @fields))) @struct
  ]]

  local query = vim.treesitter.query.parse("go", query_string)

  for id, node, _ in query:iter_captures(root, bufnr, 0, -1) do
    local capture_name = query.captures[id]

    if capture_name == "name" then
      local name = vim.treesitter.get_node_text(node, bufnr)
      if name == type_name then
        local parent = node:parent():parent()
        local start_row, _, end_row, _ = parent:range()

        local struct = {
          name = name,
          node = parent,
          start_row = start_row,
          end_row = end_row,
          fields = {},
        }

        -- Get fields
        for child_id, child_node, _ in query:iter_captures(parent, bufnr, start_row, end_row + 1) do
          local child_name = query.captures[child_id]
          if child_name == "fields" then
            struct.fields = ts.parse_field_list(child_node, bufnr)
          end
        end

        return struct
      end
    end
  end

  return nil
end

--- Build a filled struct literal.
---@param literal table Literal info
---@param struct table Struct definition
---@return string[] Lines
function M.build_filled_literal(literal, struct)
  local lines = {}
  local indent = util.get_indentation(
    vim.api.nvim_buf_get_lines(0, literal.start_row, literal.start_row + 1, false)[1] or ""
  )

  -- Get existing field names
  local existing = {}
  for _, field in ipairs(literal.fields) do
    if field.name then
      existing[field.name] = field.value
    end
  end

  -- Build multi-line literal
  table.insert(lines, indent .. literal.type_name .. "{")

  for _, field in ipairs(struct.fields) do
    if not field.embedded then
      for _, name in ipairs(field.names) do
        local value = existing[name] or util.zero_value(field.type_str)
        table.insert(lines, string.format("%s\t%s: %s,", indent, name, value))
      end
    end
  end

  table.insert(lines, indent .. "}")

  return lines
end

--- Build single-line struct literal.
---@param literal table Literal info
---@return string[] Lines (single line)
function M.build_single_line_literal(literal)
  local parts = {}

  for _, field in ipairs(literal.fields) do
    if field.name then
      table.insert(parts, string.format("%s: %s", field.name, field.value))
    else
      table.insert(parts, field.value)
    end
  end

  local indent = util.get_indentation(
    vim.api.nvim_buf_get_lines(0, literal.start_row, literal.start_row + 1, false)[1] or ""
  )

  return { indent .. literal.type_name .. "{" .. table.concat(parts, ", ") .. "}" }
end

--- Build multi-line struct literal.
---@param literal table Literal info
---@return string[] Lines
function M.build_multi_line_literal(literal)
  local lines = {}
  local indent = util.get_indentation(
    vim.api.nvim_buf_get_lines(0, literal.start_row, literal.start_row + 1, false)[1] or ""
  )

  table.insert(lines, indent .. literal.type_name .. "{")

  for _, field in ipairs(literal.fields) do
    if field.name then
      table.insert(lines, string.format("%s\t%s: %s,", indent, field.name, field.value))
    else
      table.insert(lines, string.format("%s\t%s,", indent, field.value))
    end
  end

  table.insert(lines, indent .. "}")

  return lines
end

--- Add a new field to a struct definition.
---@param opts table|nil Options
function M.add_field(opts)
  opts = opts or {}
  local bufnr = vim.api.nvim_get_current_buf()

  local struct = ts.get_struct_at_cursor(bufnr)
  if not struct then
    util.notify("No struct found at cursor", vim.log.levels.WARN)
    return
  end

  vim.ui.input({ prompt = "Field name: " }, function(name)
    if not name or name == "" then
      return
    end

    vim.ui.input({ prompt = "Field type: " }, function(type_str)
      if not type_str or type_str == "" then
        return
      end

      -- Find the last field line
      local insert_row = struct.end_row - 1 -- Before closing brace

      local indent = "\t"
      local line = string.format("%s%s %s", indent, name, type_str)

      util.insert_lines(bufnr, insert_row, { line })

      vim.schedule(function()
        util.format_buffer(bufnr)
      end)

      util.notify("Added field " .. name)
    end)
  end)
end

return M
