-- lua/nvim-go/treesitter.lua
-- Treesitter integration for parsing Go code

local M = {}

--- Check if treesitter is available and Go parser is installed.
---@return boolean
function M.is_available()
  local ok, parsers = pcall(require, "nvim-treesitter.parsers")
  if not ok then
    return false
  end
  return parsers.has_parser("go")
end

--- Setup treesitter queries for Go.
function M.setup()
  -- Register custom queries if needed
end

--- Get the root node for the current buffer.
---@param bufnr number|nil Buffer number (defaults to current)
---@return TSNode|nil
function M.get_root(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local parser = vim.treesitter.get_parser(bufnr, "go")
  if not parser then
    return nil
  end

  local tree = parser:parse()[1]
  if not tree then
    return nil
  end

  return tree:root()
end

--- Find the struct definition at or near the cursor position.
---@param bufnr number|nil Buffer number
---@return table|nil Struct info with name, fields, start_row, end_row
function M.get_struct_at_cursor(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1 -- 0-indexed

  local root = M.get_root(bufnr)
  if not root then
    return nil
  end

  -- Query for type declarations with struct types
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

    if capture_name == "struct" then
      local start_row, _, end_row, _ = node:range()

      -- Check if cursor is within this struct
      if row >= start_row and row <= end_row then
        local struct_info = {
          node = node,
          start_row = start_row,
          end_row = end_row,
          fields = {},
        }

        -- Get struct name and fields
        for child_id, child_node, _ in query:iter_captures(node, bufnr, start_row, end_row + 1) do
          local child_name = query.captures[child_id]

          if child_name == "name" then
            struct_info.name = vim.treesitter.get_node_text(child_node, bufnr)
          elseif child_name == "fields" then
            struct_info.fields = M.parse_field_list(child_node, bufnr)
          end
        end

        return struct_info
      end
    end
  end

  return nil
end

--- Parse a field_declaration_list node into field info.
---@param node TSNode Field declaration list node
---@param bufnr number Buffer number
---@return table[] List of field info tables
function M.parse_field_list(node, bufnr)
  local fields = {}

  for child in node:iter_children() do
    if child:type() == "field_declaration" then
      local field = M.parse_field(child, bufnr)
      if field then
        table.insert(fields, field)
      end
    end
  end

  return fields
end

--- Parse a single field_declaration node.
---@param node TSNode Field declaration node
---@param bufnr number Buffer number
---@return table|nil Field info with name, type, tag
function M.parse_field(node, bufnr)
  local field = {
    names = {},
    type_str = "",
    tag = nil,
    node = node,
  }

  for child in node:iter_children() do
    local child_type = child:type()

    if child_type == "field_identifier" then
      table.insert(field.names, vim.treesitter.get_node_text(child, bufnr))
    elseif child_type == "raw_string_literal" or child_type == "interpreted_string_literal" then
      -- This is a struct tag
      local tag_text = vim.treesitter.get_node_text(child, bufnr)
      field.tag = M.parse_tag(tag_text)
      field.tag_node = child
    else
      -- Check if this is a type node
      local type_text = vim.treesitter.get_node_text(child, bufnr)
      if type_text and type_text ~= "" and not type_text:match("^[`\"]") then
        -- Avoid embedded structs without field names for certain operations
        if #field.names == 0 and child_type ~= "comment" then
          -- This might be an embedded field
          field.embedded = true
          field.type_str = type_text
        else
          field.type_str = type_text
        end
      end
    end
  end

  -- Skip fields without names (embedded types handled separately)
  if #field.names == 0 and not field.embedded then
    return nil
  end

  -- For fields with multiple names (e.g., a, b int), we expand them
  if #field.names > 1 then
    -- Return the first, caller can handle expansion if needed
    field.multi_name = true
  end

  return field
end

--- Parse a struct tag string into a table of tag:value pairs.
---@param tag_str string Raw tag string including backticks
---@return table Tag table with tag names as keys
function M.parse_tag(tag_str)
  local tags = {}

  -- Remove backticks or quotes
  tag_str = tag_str:gsub("^[`\"]", ""):gsub("[`\"]$", "")

  -- Parse tag:value pairs
  for tag, value in tag_str:gmatch('(%w+):"([^"]*)"') do
    tags[tag] = value
  end

  return tags
end

--- Find a function/method at cursor position.
---@param bufnr number|nil Buffer number
---@return table|nil Function info
function M.get_function_at_cursor(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1

  local root = M.get_root(bufnr)
  if not root then
    return nil
  end

  local query_string = [[
    (function_declaration
      name: (identifier) @name
      parameters: (parameter_list) @params
      result: (_)? @result
      body: (block) @body) @func

    (method_declaration
      receiver: (parameter_list) @receiver
      name: (field_identifier) @name
      parameters: (parameter_list) @params
      result: (_)? @result
      body: (block) @body) @method
  ]]

  local query = vim.treesitter.query.parse("go", query_string)

  for id, node, _ in query:iter_captures(root, bufnr, 0, -1) do
    local capture_name = query.captures[id]

    if capture_name == "func" or capture_name == "method" then
      local start_row, _, end_row, _ = node:range()

      if row >= start_row and row <= end_row then
        local func_info = {
          node = node,
          is_method = capture_name == "method",
          start_row = start_row,
          end_row = end_row,
        }

        -- Extract function details
        for child_id, child_node, _ in query:iter_captures(node, bufnr, start_row, end_row + 1) do
          local child_name = query.captures[child_id]

          if child_name == "name" then
            func_info.name = vim.treesitter.get_node_text(child_node, bufnr)
          elseif child_name == "params" then
            func_info.params = M.parse_parameter_list(child_node, bufnr)
          elseif child_name == "result" then
            func_info.result = vim.treesitter.get_node_text(child_node, bufnr)
          elseif child_name == "receiver" then
            func_info.receiver = M.parse_parameter_list(child_node, bufnr)[1]
          end
        end

        return func_info
      end
    end
  end

  return nil
end

--- Parse a parameter list node.
---@param node TSNode Parameter list node
---@param bufnr number Buffer number
---@return table[] List of parameter info
function M.parse_parameter_list(node, bufnr)
  local params = {}

  for child in node:iter_children() do
    if child:type() == "parameter_declaration" then
      local param = {
        names = {},
        type_str = "",
      }

      for param_child in child:iter_children() do
        local child_type = param_child:type()

        if child_type == "identifier" then
          table.insert(param.names, vim.treesitter.get_node_text(param_child, bufnr))
        else
          -- Type node
          local type_text = vim.treesitter.get_node_text(param_child, bufnr)
          if type_text and type_text ~= "" then
            param.type_str = type_text
          end
        end
      end

      if param.type_str ~= "" then
        table.insert(params, param)
      end
    end
  end

  return params
end

--- Find an interface definition at cursor.
---@param bufnr number|nil Buffer number
---@return table|nil Interface info
function M.get_interface_at_cursor(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1

  local root = M.get_root(bufnr)
  if not root then
    return nil
  end

  local query_string = [[
    (type_declaration
      (type_spec
        name: (type_identifier) @name
        type: (interface_type
          (method_spec_list) @methods))) @interface
  ]]

  local query = vim.treesitter.query.parse("go", query_string)

  for id, node, _ in query:iter_captures(root, bufnr, 0, -1) do
    local capture_name = query.captures[id]

    if capture_name == "interface" then
      local start_row, _, end_row, _ = node:range()

      if row >= start_row and row <= end_row then
        local iface_info = {
          node = node,
          start_row = start_row,
          end_row = end_row,
          methods = {},
        }

        for child_id, child_node, _ in query:iter_captures(node, bufnr, start_row, end_row + 1) do
          local child_name = query.captures[child_id]

          if child_name == "name" then
            iface_info.name = vim.treesitter.get_node_text(child_node, bufnr)
          elseif child_name == "methods" then
            iface_info.methods = M.parse_interface_methods(child_node, bufnr)
          end
        end

        return iface_info
      end
    end
  end

  return nil
end

--- Parse interface method specifications.
---@param node TSNode Method spec list node
---@param bufnr number Buffer number
---@return table[] List of method info
function M.parse_interface_methods(node, bufnr)
  local methods = {}

  for child in node:iter_children() do
    if child:type() == "method_spec" then
      local method = {}

      for method_child in child:iter_children() do
        local child_type = method_child:type()

        if child_type == "field_identifier" then
          method.name = vim.treesitter.get_node_text(method_child, bufnr)
        elseif child_type == "parameter_list" then
          method.params = M.parse_parameter_list(method_child, bufnr)
        elseif child_type == "simple_type" or child_type:match("_type$") then
          method.result = vim.treesitter.get_node_text(method_child, bufnr)
        end
      end

      -- Get the full signature text
      method.signature = vim.treesitter.get_node_text(child, bufnr)

      if method.name then
        table.insert(methods, method)
      end
    end
  end

  return methods
end

--- Find all type declarations (const blocks with iota).
---@param bufnr number|nil Buffer number
---@return table|nil Enum info at cursor
function M.get_enum_at_cursor(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1

  local root = M.get_root(bufnr)
  if not root then
    return nil
  end

  -- Find const declarations with iota
  local query_string = [[
    (const_declaration
      (const_spec
        name: (identifier) @const_name
        type: (type_identifier)? @type_name
        value: (expression_list
          (iota)))) @const_block
  ]]

  local query = vim.treesitter.query.parse("go", query_string)

  -- First, find the const block
  local const_query = [[
    (const_declaration) @const
  ]]
  local const_q = vim.treesitter.query.parse("go", const_query)

  for _, node, _ in const_q:iter_captures(root, bufnr, 0, -1) do
    local start_row, _, end_row, _ = node:range()

    if row >= start_row and row <= end_row then
      -- Check if this const block uses iota
      local text = vim.treesitter.get_node_text(node, bufnr)
      if text:match("iota") then
        local enum_info = {
          node = node,
          start_row = start_row,
          end_row = end_row,
          values = {},
        }

        -- Parse const specs
        for child in node:iter_children() do
          if child:type() == "const_spec" then
            local const_spec = {}
            for spec_child in child:iter_children() do
              if spec_child:type() == "identifier" then
                const_spec.name = vim.treesitter.get_node_text(spec_child, bufnr)
              elseif spec_child:type() == "type_identifier" then
                enum_info.type_name = vim.treesitter.get_node_text(spec_child, bufnr)
              end
            end
            if const_spec.name then
              table.insert(enum_info.values, const_spec.name)
            end
          end
        end

        return enum_info
      end
    end
  end

  return nil
end

--- Get the package name for the current buffer.
---@param bufnr number|nil Buffer number
---@return string|nil Package name
function M.get_package_name(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local root = M.get_root(bufnr)
  if not root then
    return nil
  end

  local query_string = [[
    (package_clause
      (package_identifier) @name)
  ]]

  local query = vim.treesitter.query.parse("go", query_string)

  for _, node, _ in query:iter_captures(root, bufnr, 0, -1) do
    return vim.treesitter.get_node_text(node, bufnr)
  end

  return nil
end

--- Get all imports in the current buffer.
---@param bufnr number|nil Buffer number
---@return table[] List of import info
function M.get_imports(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local root = M.get_root(bufnr)
  if not root then
    return {}
  end

  local imports = {}
  local query_string = [[
    (import_declaration
      (import_spec_list
        (import_spec
          name: (package_identifier)? @alias
          path: (interpreted_string_literal) @path))) @import_block

    (import_declaration
      (import_spec
        name: (package_identifier)? @alias
        path: (interpreted_string_literal) @path)) @import_single
  ]]

  local query = vim.treesitter.query.parse("go", query_string)

  local current_import = {}
  for id, node, _ in query:iter_captures(root, bufnr, 0, -1) do
    local capture_name = query.captures[id]

    if capture_name == "path" then
      current_import.path = vim.treesitter.get_node_text(node, bufnr):gsub('"', "")
      table.insert(imports, current_import)
      current_import = {}
    elseif capture_name == "alias" then
      current_import.alias = vim.treesitter.get_node_text(node, bufnr)
    end
  end

  return imports
end

return M
