-- lua/nvim-go/imports.lua
-- Import management for Go (Uber style grouping)

local ts = require("nvim-go.treesitter")
local util = require("nvim-go.util")

local M = {}

-- Standard library packages (partial list for categorization)
local stdlib_prefixes = {
  "archive",
  "bufio",
  "bytes",
  "compress",
  "container",
  "context",
  "crypto",
  "database",
  "debug",
  "embed",
  "encoding",
  "errors",
  "expvar",
  "flag",
  "fmt",
  "go",
  "hash",
  "html",
  "image",
  "index",
  "io",
  "log",
  "maps",
  "math",
  "mime",
  "net",
  "os",
  "path",
  "plugin",
  "reflect",
  "regexp",
  "runtime",
  "slices",
  "sort",
  "strconv",
  "strings",
  "sync",
  "syscall",
  "testing",
  "text",
  "time",
  "unicode",
  "unsafe",
}

--- Check if a package path is from the standard library.
---@param path string Import path
---@return boolean
function M.is_stdlib(path)
  -- Standard library packages don't have dots in the first segment
  local first_segment = path:match("^([^/]+)")
  if not first_segment then
    return false
  end

  -- Check if it's a known stdlib prefix
  for _, prefix in ipairs(stdlib_prefixes) do
    if first_segment == prefix then
      return true
    end
  end

  -- Heuristic: stdlib packages don't have dots
  return not first_segment:match("%.")
end

--- Organize imports according to Uber style guide.
--- Groups: 1. Standard library, 2. External packages, 3. Internal packages
---@param opts table|nil Command options
function M.organize(opts)
  opts = opts or {}
  local bufnr = vim.api.nvim_get_current_buf()

  if vim.bo[bufnr].filetype ~= "go" then
    util.notify("Not a Go file", vim.log.levels.WARN)
    return
  end

  -- Get current module path for internal package detection
  local module_path = M.get_module_path(bufnr)

  -- Find import declaration
  local import_info = M.find_import_declaration(bufnr)
  if not import_info then
    util.notify("No import declaration found", vim.log.levels.INFO)
    return
  end

  -- Parse and categorize imports
  local imports = M.parse_imports(bufnr, import_info)
  local categorized = M.categorize_imports(imports, module_path)

  -- Build new import block
  local lines = M.build_import_block(categorized)

  -- Replace the import declaration
  util.replace_lines(bufnr, import_info.start_row, import_info.end_row + 1, lines)

  vim.schedule(function()
    util.format_buffer(bufnr)
  end)

  util.notify("Organized imports")
end

--- Get the module path from go.mod.
---@param bufnr number Buffer number
---@return string|nil Module path
function M.get_module_path(bufnr)
  local file_path = util.get_file_path(bufnr)
  local dir = vim.fn.fnamemodify(file_path, ":h")

  -- Search up for go.mod
  while dir ~= "/" and dir ~= "" do
    local go_mod = dir .. "/go.mod"
    if vim.fn.filereadable(go_mod) == 1 then
      local lines = vim.fn.readfile(go_mod, "", 10)
      for _, line in ipairs(lines) do
        local module = line:match("^module%s+(.+)$")
        if module then
          return module:match("^%s*(.-)%s*$") -- trim
        end
      end
    end
    dir = vim.fn.fnamemodify(dir, ":h")
  end

  return nil
end

--- Find the import declaration in the buffer.
---@param bufnr number Buffer number
---@return table|nil Import declaration info
function M.find_import_declaration(bufnr)
  local root = ts.get_root(bufnr)
  if not root then
    return nil
  end

  local query_string = [[
    (import_declaration) @import
  ]]

  local query = vim.treesitter.query.parse("go", query_string)

  for _, node, _ in query:iter_captures(root, bufnr, 0, -1) do
    local start_row, _, end_row, _ = node:range()
    return {
      node = node,
      start_row = start_row,
      end_row = end_row,
    }
  end

  return nil
end

--- Parse imports from the import declaration.
---@param bufnr number Buffer number
---@param import_info table Import declaration info
---@return table[] List of import specs
function M.parse_imports(bufnr, import_info)
  local imports = {}
  local node = import_info.node

  local query_string = [[
    (import_spec
      name: (package_identifier)? @alias
      path: (interpreted_string_literal) @path)
  ]]

  local query = vim.treesitter.query.parse("go", query_string)

  local current_import = {}
  for id, child_node, _ in query:iter_captures(node, bufnr) do
    local capture_name = query.captures[id]

    if capture_name == "alias" then
      current_import.alias = vim.treesitter.get_node_text(child_node, bufnr)
    elseif capture_name == "path" then
      local path = vim.treesitter.get_node_text(child_node, bufnr)
      current_import.path = path:gsub('"', "")
      current_import.raw_path = path
      table.insert(imports, current_import)
      current_import = {}
    end
  end

  return imports
end

--- Categorize imports into groups.
---@param imports table[] List of imports
---@param module_path string|nil Current module path
---@return table Categorized imports
function M.categorize_imports(imports, module_path)
  local categorized = {
    stdlib = {},
    external = {},
    internal = {},
  }

  for _, imp in ipairs(imports) do
    if M.is_stdlib(imp.path) then
      table.insert(categorized.stdlib, imp)
    elseif module_path and imp.path:sub(1, #module_path) == module_path then
      table.insert(categorized.internal, imp)
    else
      table.insert(categorized.external, imp)
    end
  end

  -- Sort each category
  local function sort_imports(list)
    table.sort(list, function(a, b)
      return a.path < b.path
    end)
  end

  sort_imports(categorized.stdlib)
  sort_imports(categorized.external)
  sort_imports(categorized.internal)

  return categorized
end

--- Build the import block from categorized imports.
---@param categorized table Categorized imports
---@return string[] Lines
function M.build_import_block(categorized)
  local lines = {}
  local has_content = false

  table.insert(lines, "import (")

  -- Standard library
  if #categorized.stdlib > 0 then
    for _, imp in ipairs(categorized.stdlib) do
      table.insert(lines, M.format_import(imp))
    end
    has_content = true
  end

  -- External packages
  if #categorized.external > 0 then
    if has_content then
      table.insert(lines, "")
    end
    for _, imp in ipairs(categorized.external) do
      table.insert(lines, M.format_import(imp))
    end
    has_content = true
  end

  -- Internal packages
  if #categorized.internal > 0 then
    if has_content then
      table.insert(lines, "")
    end
    for _, imp in ipairs(categorized.internal) do
      table.insert(lines, M.format_import(imp))
    end
  end

  table.insert(lines, ")")

  return lines
end

--- Format a single import line.
---@param imp table Import spec
---@return string Formatted import line
function M.format_import(imp)
  if imp.alias then
    return string.format('\t%s "%s"', imp.alias, imp.path)
  else
    return string.format('\t"%s"', imp.path)
  end
end

--- Add an import to the current file.
---@param path string Import path
---@param alias string|nil Optional alias
function M.add_import(path, alias)
  local bufnr = vim.api.nvim_get_current_buf()

  local import_info = M.find_import_declaration(bufnr)

  if not import_info then
    -- No import declaration, create one
    local pkg = ts.get_package_name(bufnr)
    if not pkg then
      util.notify("Could not find package declaration", vim.log.levels.ERROR)
      return
    end

    -- Find package line
    local root = ts.get_root(bufnr)
    if not root then
      return
    end

    local query_string = [[
      (package_clause) @pkg
    ]]
    local query = vim.treesitter.query.parse("go", query_string)

    for _, node, _ in query:iter_captures(root, bufnr, 0, -1) do
      local _, _, end_row, _ = node:range()

      local lines
      if alias then
        lines = { "", "import (", string.format('\t%s "%s"', alias, path), ")" }
      else
        lines = { "", "import (", string.format('\t"%s"', path), ")" }
      end

      util.insert_lines(bufnr, end_row, lines)
      break
    end
  else
    -- Add to existing import block
    local lines = util.get_lines(bufnr, import_info.start_row, import_info.end_row + 1)

    -- Find position to insert (before closing paren)
    local insert_idx = #lines
    for i = #lines, 1, -1 do
      if lines[i]:match("^%)") then
        insert_idx = i
        break
      end
    end

    local new_line
    if alias then
      new_line = string.format('\t%s "%s"', alias, path)
    else
      new_line = string.format('\t"%s"', path)
    end

    table.insert(lines, insert_idx, new_line)

    util.replace_lines(bufnr, import_info.start_row, import_info.end_row + 1, lines)
  end

  -- Re-organize
  M.organize()
end

--- Remove an import from the current file.
---@param path string Import path to remove
function M.remove_import(path)
  local bufnr = vim.api.nvim_get_current_buf()

  local import_info = M.find_import_declaration(bufnr)
  if not import_info then
    return
  end

  local imports = M.parse_imports(bufnr, import_info)
  local new_imports = {}

  for _, imp in ipairs(imports) do
    if imp.path ~= path then
      table.insert(new_imports, imp)
    end
  end

  if #new_imports == #imports then
    util.notify("Import not found: " .. path, vim.log.levels.WARN)
    return
  end

  if #new_imports == 0 then
    -- Remove entire import declaration
    util.replace_lines(bufnr, import_info.start_row, import_info.end_row + 1, {})
  else
    local module_path = M.get_module_path(bufnr)
    local categorized = M.categorize_imports(new_imports, module_path)
    local lines = M.build_import_block(categorized)
    util.replace_lines(bufnr, import_info.start_row, import_info.end_row + 1, lines)
  end

  util.notify("Removed import: " .. path)
end

return M
