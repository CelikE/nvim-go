-- lua/nvim-go/test.lua
-- Test generation for Go functions

local ts = require("nvim-go.treesitter")
local util = require("nvim-go.util")
local config = require("nvim-go.config")

local M = {}

--- Generate a table-driven test for the function at cursor.
---@param opts table|nil Command options
function M.generate(opts)
  opts = opts or {}
  local bufnr = vim.api.nvim_get_current_buf()

  if vim.bo[bufnr].filetype ~= "go" then
    util.notify("Not a Go file", vim.log.levels.WARN)
    return
  end

  local func = ts.get_function_at_cursor(bufnr)
  if not func then
    util.notify("No function found at cursor", vim.log.levels.WARN)
    return
  end

  local cfg = config.get()
  local lines

  if cfg.test.template == "table" then
    lines = M.build_table_driven_test(func, cfg.test.parallel)
  else
    lines = M.build_simple_test(func)
  end

  -- Insert at end of file
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  util.insert_lines(bufnr, line_count - 1, lines)

  vim.schedule(function()
    util.format_buffer(bufnr)
  end)

  util.notify("Generated test for " .. func.name)
end

--- Generate a benchmark for the function at cursor.
---@param opts table|nil Command options
function M.generate_benchmark(opts)
  opts = opts or {}
  local bufnr = vim.api.nvim_get_current_buf()

  if vim.bo[bufnr].filetype ~= "go" then
    util.notify("Not a Go file", vim.log.levels.WARN)
    return
  end

  local func = ts.get_function_at_cursor(bufnr)
  if not func then
    util.notify("No function found at cursor", vim.log.levels.WARN)
    return
  end

  local lines = M.build_benchmark(func)

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  util.insert_lines(bufnr, line_count - 1, lines)

  vim.schedule(function()
    util.format_buffer(bufnr)
  end)

  util.notify("Generated benchmark for " .. func.name)
end

--- Build a table-driven test (Uber style).
---@param func table Function info
---@param parallel boolean Use t.Parallel()
---@return string[] Lines of code
function M.build_table_driven_test(func, parallel)
  local lines = {}
  local func_name = func.name
  local test_name = "Test" .. util.export_name(func_name)

  -- Determine test case fields from function signature
  local input_fields = {}
  local want_fields = {}

  for _, param in ipairs(func.params or {}) do
    for _, name in ipairs(param.names or {}) do
      table.insert(input_fields, { name = name, type_str = param.type_str })
    end
  end

  -- Parse result type
  if func.result then
    local result = func.result
    -- Handle multiple returns
    if result:match("^%(") then
      -- Multiple returns like "(int, error)"
      local i = 1
      for ret_type in result:gmatch("[%w%*%[%]%.]+") do
        if ret_type == "error" then
          table.insert(want_fields, { name = "wantErr", type_str = "bool" })
        else
          table.insert(want_fields, { name = "want" .. (i > 1 and i or ""), type_str = ret_type })
          i = i + 1
        end
      end
    else
      -- Single return
      if result == "error" then
        table.insert(want_fields, { name = "wantErr", type_str = "bool" })
      else
        table.insert(want_fields, { name = "want", type_str = result })
      end
    end
  end

  table.insert(lines, "")
  table.insert(lines, string.format("func %s(t *testing.T) {", test_name))

  if parallel then
    table.insert(lines, "\tt.Parallel()")
    table.insert(lines, "")
  end

  -- Test case struct
  table.insert(lines, "\ttests := []struct {")
  table.insert(lines, "\t\tname string")

  for _, field in ipairs(input_fields) do
    table.insert(lines, string.format("\t\t%s %s", field.name, field.type_str))
  end

  for _, field in ipairs(want_fields) do
    table.insert(lines, string.format("\t\t%s %s", field.name, field.type_str))
  end

  table.insert(lines, "\t}{")

  -- Example test case
  table.insert(lines, "\t\t{")
  table.insert(lines, '\t\t\tname: "success",')

  for _, field in ipairs(input_fields) do
    local zero = util.zero_value(field.type_str)
    table.insert(lines, string.format("\t\t\t%s: %s,", field.name, zero))
  end

  for _, field in ipairs(want_fields) do
    local zero = util.zero_value(field.type_str)
    table.insert(lines, string.format("\t\t\t%s: %s,", field.name, zero))
  end

  table.insert(lines, "\t\t},")
  table.insert(lines, "\t}")
  table.insert(lines, "")

  -- Test loop
  table.insert(lines, "\tfor _, tt := range tests {")
  table.insert(lines, "\t\tt.Run(tt.name, func(t *testing.T) {")

  if parallel then
    table.insert(lines, "\t\t\tt.Parallel()")
    table.insert(lines, "")
  end

  -- Build function call
  local args = {}
  for _, field in ipairs(input_fields) do
    table.insert(args, "tt." .. field.name)
  end
  local args_str = table.concat(args, ", ")

  -- Handle different return scenarios
  local has_error = false
  local result_vars = {}

  for _, field in ipairs(want_fields) do
    if field.name == "wantErr" then
      has_error = true
      table.insert(result_vars, "err")
    else
      table.insert(result_vars, "got")
    end
  end

  if #result_vars > 0 then
    local result_str = table.concat(result_vars, ", ")

    if func.is_method and func.receiver then
      -- Method call
      local receiver_type = func.receiver.type_str
      local zero = util.zero_value(receiver_type)
      table.insert(
        lines,
        string.format("\t\t\t%s := %s.%s(%s)", result_str, zero, func_name, args_str)
      )
    else
      -- Function call
      table.insert(
        lines,
        string.format("\t\t\t%s := %s(%s)", result_str, func_name, args_str)
      )
    end
  else
    if func.is_method and func.receiver then
      local receiver_type = func.receiver.type_str
      local zero = util.zero_value(receiver_type)
      table.insert(
        lines,
        string.format("\t\t\t%s.%s(%s)", zero, func_name, args_str)
      )
    else
      table.insert(
        lines,
        string.format("\t\t\t%s(%s)", func_name, args_str)
      )
    end
  end

  table.insert(lines, "")

  -- Error check
  if has_error then
    table.insert(lines, "\t\t\tif (err != nil) != tt.wantErr {")
    table.insert(
      lines,
      '\t\t\t\tt.Errorf("%s() error = %%v, wantErr %%v", err, tt.wantErr)'
    )
    table.insert(lines, "\t\t\t\treturn")
    table.insert(lines, "\t\t\t}")
  end

  -- Value comparison
  for _, field in ipairs(want_fields) do
    if field.name ~= "wantErr" then
      table.insert(lines, string.format("\t\t\tif got != tt.%s {", field.name))
      table.insert(
        lines,
        string.format(
          '\t\t\t\tt.Errorf("%s() = %%v, want %%v", got, tt.%s)',
          func_name,
          field.name
        )
      )
      table.insert(lines, "\t\t\t}")
    end
  end

  table.insert(lines, "\t\t})")
  table.insert(lines, "\t}")
  table.insert(lines, "}")

  return lines
end

--- Build a simple test (not table-driven).
---@param func table Function info
---@return string[] Lines of code
function M.build_simple_test(func)
  local lines = {}
  local func_name = func.name
  local test_name = "Test" .. util.export_name(func_name)

  table.insert(lines, "")
  table.insert(lines, string.format("func %s(t *testing.T) {", test_name))

  -- Build args
  local args = {}
  for _, param in ipairs(func.params or {}) do
    for _, name in ipairs(param.names or {}) do
      local zero = util.zero_value(param.type_str)
      table.insert(lines, string.format("\t%s := %s", name, zero))
      table.insert(args, name)
    end
  end

  local args_str = table.concat(args, ", ")

  table.insert(lines, "")

  if func.result then
    table.insert(
      lines,
      string.format("\tgot := %s(%s)", func_name, args_str)
    )
    table.insert(lines, "")
    table.insert(lines, "\t// TODO: Add assertions")
    table.insert(lines, "\t_ = got")
  else
    table.insert(lines, string.format("\t%s(%s)", func_name, args_str))
  end

  table.insert(lines, "}")

  return lines
end

--- Build a benchmark function.
---@param func table Function info
---@return string[] Lines of code
function M.build_benchmark(func)
  local lines = {}
  local func_name = func.name
  local bench_name = "Benchmark" .. util.export_name(func_name)

  table.insert(lines, "")
  table.insert(lines, string.format("func %s(b *testing.B) {", bench_name))

  -- Setup variables outside loop
  local args = {}
  for _, param in ipairs(func.params or {}) do
    for _, name in ipairs(param.names or {}) do
      local zero = util.zero_value(param.type_str)
      table.insert(lines, string.format("\t%s := %s", name, zero))
      table.insert(args, name)
    end
  end

  local args_str = table.concat(args, ", ")

  table.insert(lines, "")
  table.insert(lines, "\tb.ResetTimer()")
  table.insert(lines, "\tfor i := 0; i < b.N; i++ {")

  if func.result then
    -- Prevent compiler optimization
    table.insert(lines, string.format("\t\t_ = %s(%s)", func_name, args_str))
  else
    table.insert(lines, string.format("\t\t%s(%s)", func_name, args_str))
  end

  table.insert(lines, "\t}")
  table.insert(lines, "}")

  return lines
end

--- Generate test file for current file.
---@param opts table|nil Options
function M.generate_test_file(opts)
  opts = opts or {}
  local bufnr = vim.api.nvim_get_current_buf()
  local file_path = util.get_file_path(bufnr)

  if not file_path:match("%.go$") or file_path:match("_test%.go$") then
    util.notify("Not a Go source file", vim.log.levels.WARN)
    return
  end

  local test_file = file_path:gsub("%.go$", "_test.go")

  -- Check if test file already exists
  if vim.fn.filereadable(test_file) == 1 then
    vim.cmd("edit " .. test_file)
    return
  end

  -- Get package name
  local pkg_name = ts.get_package_name(bufnr) or "main"

  -- Create test file content
  local lines = {
    string.format("package %s", pkg_name),
    "",
    "import (",
    '\t"testing"',
    ")",
  }

  -- Write and open test file
  vim.fn.writefile(lines, test_file)
  vim.cmd("edit " .. test_file)

  util.notify("Created " .. vim.fn.fnamemodify(test_file, ":t"))
end

return M
