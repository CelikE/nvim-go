-- lua/nvim-go/doc.lua
-- Go documentation comment generation

local ts = require("nvim-go.treesitter")
local util = require("nvim-go.util")

local M = {}

--- Generate documentation comment for function/type at cursor.
---@param opts table|nil Command options
function M.generate(opts)
  opts = opts or {}
  local bufnr = vim.api.nvim_get_current_buf()

  if vim.bo[bufnr].filetype ~= "go" then
    util.notify("Not a Go file", vim.log.levels.WARN)
    return
  end

  -- Try function first
  local func = ts.get_function_at_cursor(bufnr)
  if func then
    M.generate_func_doc(bufnr, func)
    return
  end

  -- Try struct
  local struct = ts.get_struct_at_cursor(bufnr)
  if struct then
    M.generate_struct_doc(bufnr, struct)
    return
  end

  -- Try interface
  local iface = ts.get_interface_at_cursor(bufnr)
  if iface then
    M.generate_interface_doc(bufnr, iface)
    return
  end

  util.notify("No documentable element at cursor", vim.log.levels.WARN)
end

--- Generate documentation for a function.
---@param bufnr number Buffer number
---@param func table Function info
function M.generate_func_doc(bufnr, func)
  local lines = M.build_func_doc(func)

  -- Check if there's already a doc comment
  local existing = M.get_existing_doc(bufnr, func.start_row)
  if existing then
    -- Replace existing doc
    util.replace_lines(bufnr, existing.start_row, existing.end_row + 1, lines)
  else
    -- Insert new doc
    util.insert_lines(bufnr, func.start_row - 1, lines)
  end

  util.notify("Generated documentation for " .. func.name)
end

--- Generate documentation for a struct.
---@param bufnr number Buffer number
---@param struct table Struct info
function M.generate_struct_doc(bufnr, struct)
  local lines = M.build_struct_doc(struct)

  local existing = M.get_existing_doc(bufnr, struct.start_row)
  if existing then
    util.replace_lines(bufnr, existing.start_row, existing.end_row + 1, lines)
  else
    util.insert_lines(bufnr, struct.start_row - 1, lines)
  end

  util.notify("Generated documentation for " .. struct.name)
end

--- Generate documentation for an interface.
---@param bufnr number Buffer number
---@param iface table Interface info
function M.generate_interface_doc(bufnr, iface)
  local lines = M.build_interface_doc(iface)

  local existing = M.get_existing_doc(bufnr, iface.start_row)
  if existing then
    util.replace_lines(bufnr, existing.start_row, existing.end_row + 1, lines)
  else
    util.insert_lines(bufnr, iface.start_row - 1, lines)
  end

  util.notify("Generated documentation for " .. iface.name)
end

--- Check for existing doc comment before a line.
---@param bufnr number Buffer number
---@param decl_row number Declaration start row
---@return table|nil Existing doc comment info
function M.get_existing_doc(bufnr, decl_row)
  if decl_row <= 0 then
    return nil
  end

  -- Look backwards for comment lines
  local lines = util.get_lines(bufnr, 0, decl_row)
  local end_row = decl_row - 1
  local start_row = end_row

  -- Check if the line before declaration is a comment
  for i = #lines, 1, -1 do
    local line = lines[i]
    if line:match("^%s*//") then
      start_row = i - 1
    elseif line:match("^%s*$") then
      -- Empty line, stop if we've found comments
      if start_row < end_row then
        break
      end
      -- Otherwise continue looking
      end_row = i - 2
      start_row = end_row
    else
      break
    end
  end

  if start_row < end_row then
    return {
      start_row = start_row,
      end_row = end_row,
    }
  end

  return nil
end

--- Build documentation for a function.
---@param func table Function info
---@return string[] Doc comment lines
function M.build_func_doc(func)
  local lines = {}
  local name = func.name

  -- Function description
  if func.is_method then
    table.insert(lines, string.format("// %s ...", name))
  else
    -- Follow Go convention: "FuncName does X"
    local desc = M.generate_description(name)
    table.insert(lines, string.format("// %s %s", name, desc))
  end

  -- Document parameters if complex
  if func.params and #func.params > 0 then
    local has_complex_params = false
    for _, param in ipairs(func.params) do
      if param.type_str:match("func") or param.type_str:match("interface") then
        has_complex_params = true
        break
      end
    end

    if has_complex_params then
      table.insert(lines, "//")
      for _, param in ipairs(func.params) do
        for _, pname in ipairs(param.names or {}) do
          table.insert(lines, string.format("// %s: ...", pname))
        end
      end
    end
  end

  return lines
end

--- Build documentation for a struct.
---@param struct table Struct info
---@return string[] Doc comment lines
function M.build_struct_doc(struct)
  local lines = {}
  local name = struct.name

  -- Type description
  local desc = M.generate_description(name)
  table.insert(lines, string.format("// %s %s", name, desc))

  return lines
end

--- Build documentation for an interface.
---@param iface table Interface info
---@return string[] Doc comment lines
function M.build_interface_doc(iface)
  local lines = {}
  local name = iface.name

  -- Interface description
  table.insert(lines, string.format("// %s defines the interface for ...", name))

  return lines
end

--- Generate a description based on the name.
---@param name string Identifier name
---@return string Description
function M.generate_description(name)
  -- Try to generate a sensible description based on common patterns

  -- Check for common prefixes
  if name:match("^New") then
    local type_name = name:sub(4)
    return string.format("creates a new %s instance.", type_name)
  end

  if name:match("^Get") then
    local field = name:sub(4)
    return string.format("returns the %s.", util.to_snake_case(field):gsub("_", " "))
  end

  if name:match("^Set") then
    local field = name:sub(4)
    return string.format("sets the %s.", util.to_snake_case(field):gsub("_", " "))
  end

  if name:match("^Is") or name:match("^Has") or name:match("^Can") then
    return "reports whether ..."
  end

  if name:match("^With") then
    return "returns a copy with ..."
  end

  if name:match("^Parse") then
    return "parses ..."
  end

  if name:match("^Format") then
    return "formats ..."
  end

  if name:match("^Validate") then
    return "validates ..."
  end

  if name:match("^Handle") then
    return "handles ..."
  end

  if name:match("^Process") then
    return "processes ..."
  end

  if name:match("^Convert") then
    return "converts ..."
  end

  if name:match("^Load") then
    return "loads ..."
  end

  if name:match("^Save") then
    return "saves ..."
  end

  if name:match("^Delete") or name:match("^Remove") then
    return "removes ..."
  end

  if name:match("^Create") then
    return "creates ..."
  end

  if name:match("^Update") then
    return "updates ..."
  end

  if name:match("^Find") then
    return "finds ..."
  end

  if name:match("^List") then
    return "lists ..."
  end

  -- For types ending in "er", they're often interfaces or doers
  if name:match("er$") then
    return "represents ..."
  end

  -- Default
  return "..."
end

--- Generate package documentation.
---@param opts table|nil Options
function M.generate_package_doc(opts)
  opts = opts or {}
  local bufnr = vim.api.nvim_get_current_buf()

  local pkg_name = ts.get_package_name(bufnr)
  if not pkg_name then
    util.notify("Could not find package name", vim.log.levels.ERROR)
    return
  end

  -- Check if there's already a package doc
  local root = ts.get_root(bufnr)
  if not root then
    return
  end

  local query_string = [[
    (package_clause) @pkg
  ]]
  local query = vim.treesitter.query.parse("go", query_string)

  for _, node, _ in query:iter_captures(root, bufnr, 0, -1) do
    local start_row, _, _, _ = node:range()

    local lines = {
      string.format("// Package %s provides ...", pkg_name),
      "//",
      "// Example usage:",
      "//",
      "//\t...",
    }

    -- Check for existing doc
    local existing = M.get_existing_doc(bufnr, start_row)
    if existing then
      util.replace_lines(bufnr, existing.start_row, existing.end_row + 1, lines)
    else
      util.insert_lines(bufnr, start_row - 1, lines)
    end

    util.notify("Generated package documentation")
    break
  end
end

return M
