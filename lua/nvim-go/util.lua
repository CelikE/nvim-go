-- lua/nvim-go/util.lua
-- Utility functions for nvim-go plugin

local M = {}

--- Convert a string to snake_case.
---@param str string Input string
---@return string Snake case string
function M.to_snake_case(str)
  -- Handle empty string
  if str == "" then
    return str
  end

  -- Insert underscore before uppercase letters and convert to lowercase
  local result = str:gsub("(%u)", function(c)
    return "_" .. c:lower()
  end)

  -- Remove leading underscore if present
  result = result:gsub("^_", "")

  -- Handle consecutive uppercase letters (e.g., "ID" -> "id", "URL" -> "url")
  result = result:gsub("_(%l)", function(c)
    return "_" .. c
  end)

  return result
end

--- Convert a string to camelCase.
---@param str string Input string
---@return string Camel case string
function M.to_camel_case(str)
  if str == "" then
    return str
  end

  -- First letter lowercase
  local result = str:sub(1, 1):lower() .. str:sub(2)

  return result
end

--- Convert a string to PascalCase.
---@param str string Input string
---@return string Pascal case string
function M.to_pascal_case(str)
  if str == "" then
    return str
  end

  -- First letter uppercase
  return str:sub(1, 1):upper() .. str:sub(2)
end

--- Convert a string to lisp-case (kebab-case).
---@param str string Input string
---@return string Lisp case string
function M.to_lisp_case(str)
  return M.to_snake_case(str):gsub("_", "-")
end

--- Transform a field name based on transformation type.
---@param name string Field name
---@param transform string Transformation type
---@return string Transformed name
function M.transform_name(name, transform)
  if transform == "snakecase" then
    return M.to_snake_case(name)
  elseif transform == "camelcase" then
    return M.to_camel_case(name)
  elseif transform == "pascalcase" then
    return M.to_pascal_case(name)
  elseif transform == "lispcase" then
    return M.to_lisp_case(name)
  else
    return name
  end
end

--- Check if a type is a pointer type.
---@param type_str string Type string
---@return boolean
function M.is_pointer(type_str)
  return type_str:match("^%*") ~= nil
end

--- Get the base type without pointer.
---@param type_str string Type string
---@return string Base type
function M.base_type(type_str)
  return type_str:gsub("^%*", "")
end

--- Add pointer to type if not already a pointer.
---@param type_str string Type string
---@return string Pointer type
function M.make_pointer(type_str)
  if M.is_pointer(type_str) then
    return type_str
  end
  return "*" .. type_str
end

--- Get zero value for a Go type.
---@param type_str string Type string
---@return string Zero value
function M.zero_value(type_str)
  -- Handle pointer types
  if M.is_pointer(type_str) then
    return "nil"
  end

  -- Handle slice and map types
  if type_str:match("^%[%]") or type_str:match("^map%[") then
    return "nil"
  end

  -- Handle channel types
  if type_str:match("^chan ") or type_str:match("^<%-chan ") or type_str:match("^chan<%-") then
    return "nil"
  end

  -- Handle function types
  if type_str:match("^func") then
    return "nil"
  end

  -- Handle interface types
  if type_str:match("^interface") or type_str == "any" or type_str == "error" then
    return "nil"
  end

  -- Handle basic types
  local zero_values = {
    string = '""',
    bool = "false",
    int = "0",
    int8 = "0",
    int16 = "0",
    int32 = "0",
    int64 = "0",
    uint = "0",
    uint8 = "0",
    uint16 = "0",
    uint32 = "0",
    uint64 = "0",
    uintptr = "0",
    byte = "0",
    rune = "0",
    float32 = "0",
    float64 = "0",
    complex64 = "0",
    complex128 = "0",
  }

  local base = M.base_type(type_str)
  if zero_values[base] then
    return zero_values[base]
  end

  -- Handle array types
  if type_str:match("^%[%d+%]") then
    return type_str .. "{}"
  end

  -- Handle struct types (assume custom types are structs)
  return type_str .. "{}"
end

--- Check if a name is exported (starts with uppercase).
---@param name string Name to check
---@return boolean
function M.is_exported(name)
  return name:match("^%u") ~= nil
end

--- Make a name exported.
---@param name string Name to export
---@return string Exported name
function M.export_name(name)
  return name:sub(1, 1):upper() .. name:sub(2)
end

--- Make a name unexported.
---@param name string Name to unexport
---@return string Unexported name
function M.unexport_name(name)
  return name:sub(1, 1):lower() .. name:sub(2)
end

--- Generate a receiver name from a type name.
--- Following Go convention: first letter lowercase.
---@param type_name string Type name
---@return string Receiver name
function M.receiver_name(type_name)
  -- Remove pointer if present
  type_name = M.base_type(type_name)

  -- Get first letter and lowercase it
  return type_name:sub(1, 1):lower()
end

--- Build a struct tag string from a table of tags.
---@param tags table Tag table with tag names as keys
---@return string Tag string with backticks
function M.build_tag_string(tags)
  local parts = {}

  -- Sort tags for consistent output
  local sorted_keys = {}
  for k in pairs(tags) do
    table.insert(sorted_keys, k)
  end
  table.sort(sorted_keys)

  for _, key in ipairs(sorted_keys) do
    local value = tags[key]
    table.insert(parts, string.format('%s:"%s"', key, value))
  end

  if #parts == 0 then
    return ""
  end

  return "`" .. table.concat(parts, " ") .. "`"
end

--- Get the current buffer's file path.
---@param bufnr number|nil Buffer number
---@return string File path
function M.get_file_path(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  return vim.api.nvim_buf_get_name(bufnr)
end

--- Get the current buffer's directory.
---@param bufnr number|nil Buffer number
---@return string Directory path
function M.get_file_dir(bufnr)
  local path = M.get_file_path(bufnr)
  return vim.fn.fnamemodify(path, ":h")
end

--- Insert lines after a specific line number.
---@param bufnr number Buffer number
---@param line number Line number (0-indexed)
---@param lines string[] Lines to insert
function M.insert_lines(bufnr, line, lines)
  vim.api.nvim_buf_set_lines(bufnr, line + 1, line + 1, false, lines)
end

--- Replace lines in a buffer.
---@param bufnr number Buffer number
---@param start_line number Start line (0-indexed)
---@param end_line number End line (0-indexed, exclusive)
---@param lines string[] Replacement lines
function M.replace_lines(bufnr, start_line, end_line, lines)
  vim.api.nvim_buf_set_lines(bufnr, start_line, end_line, false, lines)
end

--- Get lines from a buffer.
---@param bufnr number Buffer number
---@param start_line number Start line (0-indexed)
---@param end_line number End line (0-indexed, exclusive, -1 for end)
---@return string[] Lines
function M.get_lines(bufnr, start_line, end_line)
  return vim.api.nvim_buf_get_lines(bufnr, start_line, end_line, false)
end

--- Notify user with a message.
---@param msg string Message
---@param level number|nil Log level (defaults to INFO)
function M.notify(msg, level)
  level = level or vim.log.levels.INFO
  vim.notify("[nvim-go] " .. msg, level)
end

--- Format Go code in buffer using gofmt or goimports.
---@param bufnr number|nil Buffer number
function M.format_buffer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Try goimports first, fall back to gofmt
  local formatter = vim.fn.executable("goimports") == 1 and "goimports" or "gofmt"

  local lines = M.get_lines(bufnr, 0, -1)
  local input = table.concat(lines, "\n")

  local result = vim.fn.system(formatter, input)

  if vim.v.shell_error == 0 then
    local new_lines = vim.split(result, "\n", { plain = true })
    -- Remove trailing empty line if present
    if new_lines[#new_lines] == "" then
      table.remove(new_lines)
    end
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines)
  end
end

--- Calculate indentation for a line.
---@param line string Line to analyze
---@return string Indentation string
function M.get_indentation(line)
  return line:match("^(%s*)") or ""
end

--- Indent lines with a specific prefix.
---@param lines string[] Lines to indent
---@param indent string Indentation string
---@return string[] Indented lines
function M.indent_lines(lines, indent)
  local result = {}
  for _, line in ipairs(lines) do
    if line == "" then
      table.insert(result, "")
    else
      table.insert(result, indent .. line)
    end
  end
  return result
end

--- Pluralize a word (simple English rules).
---@param word string Word to pluralize
---@param count number Count for pluralization
---@return string Pluralized word
function M.pluralize(word, count)
  if count == 1 then
    return word
  end

  if word:match("s$") or word:match("x$") or word:match("ch$") or word:match("sh$") then
    return word .. "es"
  elseif word:match("y$") and not word:match("[aeiou]y$") then
    return word:sub(1, -2) .. "ies"
  else
    return word .. "s"
  end
end

return M
