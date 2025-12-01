-- lua/nvim-go/constructor.lua
-- Constructor generation for Go structs

local ts = require("nvim-go.treesitter")
local util = require("nvim-go.util")
local config = require("nvim-go.config")

local M = {}

local function to_camel_case(str)
	str = str:gsub("^%s*(.-)%s*$", "%1") -- Trim whitespace

	-- 1. Handle all uppercase/digits (e.g., "ID", "ISBN", "URL", "ID2")
	if str:match("^[%u%d]+$") then
		return str:lower()
	end

	-- 2. Handle Acronyms followed by words (e.g., "HTTPServer" -> "httpServer")
	-- We capture the leading uppercase run
	local prefix = str:match("^(%u+)")
	if prefix and #prefix > 1 then
		-- If the whole string was upper, we would have caught it in step 1.
		-- So this must be "HTTPServer". We want "HTTP" lower, "S" upper.
		local acronym = prefix:sub(1, #prefix - 1)
		local last = prefix:sub(#prefix)
		return acronym:lower() .. last .. str:sub(#prefix + 1)
	end

	-- 3. Default: lowercase just the first character
	return str:gsub("^%u", string.lower)
end

---@class ConstructorOptions
---@field with_validation boolean Add nil/validation checks
---@field return_pointer boolean Return pointer to struct
---@field functional_options boolean Use functional options pattern

--- Generate a constructor for the struct at cursor.
---@param opts table|nil Command options
function M.generate(opts)
	opts = opts or {}
	local bufnr = vim.api.nvim_get_current_buf()

	-- Ensure we're in a Go file
	if vim.bo[bufnr].filetype ~= "go" then
		util.notify("Not a Go file", vim.log.levels.WARN)
		return
	end

	-- Get struct at cursor
	local struct = ts.get_struct_at_cursor(bufnr)
	if not struct then
		util.notify("No struct found at cursor", vim.log.levels.WARN)
		return
	end

	local cfg = config.get()
	local lines = M.build_constructor(struct, {
		prefix = cfg.constructor.prefix,
		comment = cfg.constructor.comment,
		return_pointer = true,
	})

	-- Insert after struct definition
	util.insert_lines(bufnr, struct.end_row, lines)

	-- Format buffer
	vim.schedule(function()
		util.format_buffer(bufnr)
	end)

	util.notify("Generated constructor for " .. struct.name)
end

--- Build constructor code lines.
---@param struct table Struct info from treesitter
---@param opts ConstructorOptions|nil Options
---@return string[] Lines of code
function M.build_constructor(struct, opts)
	opts = opts or {}
	local prefix = opts.prefix or "New"
	local add_comment = opts.comment ~= false
	local return_pointer = opts.return_pointer ~= false

	local lines = {}
	local struct_name = struct.name
	local func_name = prefix .. struct_name

	-- Build parameter list
	local params = {}
	local assignments = {}

	for _, field in ipairs(struct.fields) do
		if not field.embedded then
			for _, name in ipairs(field.names) do
				-- [[ FIX APPLIED HERE ]] --
				local param_name = to_camel_case(name)

				-- Avoid parameter name collision with receiver
				if param_name == util.receiver_name(struct_name) then
					param_name = param_name .. "Val"
				end

				table.insert(params, param_name .. " " .. field.type_str)
				table.insert(assignments, string.format("\t\t%s: %s,", name, param_name))
			end
		end
	end

	-- Add doc comment
	if add_comment then
		table.insert(lines, "")
		table.insert(lines, string.format("// %s creates a new %s instance.", func_name, struct_name))
	else
		table.insert(lines, "")
	end

	-- Build function signature
	local return_type = return_pointer and ("*" .. struct_name) or struct_name
	local param_str = table.concat(params, ", ")

	-- Handle long parameter lists (Uber style: wrap at ~100 chars)
	local sig_line = string.format("func %s(%s) %s {", func_name, param_str, return_type)

	if #sig_line > 100 and #params > 1 then
		-- Multi-line parameters
		table.insert(lines, string.format("func %s(", func_name))
		for i, param in ipairs(params) do
			local suffix = i < #params and "," or ","
			table.insert(lines, "\t" .. param .. suffix)
		end
		table.insert(lines, string.format(") %s {", return_type))
	else
		table.insert(lines, sig_line)
	end

	-- Build return statement
	if return_pointer then
		table.insert(lines, string.format("\treturn &%s{", struct_name))
	else
		table.insert(lines, string.format("\treturn %s{", struct_name))
	end

	for _, assignment in ipairs(assignments) do
		table.insert(lines, assignment)
	end

	table.insert(lines, "\t}")
	table.insert(lines, "}")

	return lines
end

--- Generate constructor with functional options pattern.
---@param opts table|nil Command options
function M.generate_with_options(opts)
	opts = opts or {}
	local bufnr = vim.api.nvim_get_current_buf()

	local struct = ts.get_struct_at_cursor(bufnr)
	if not struct then
		util.notify("No struct found at cursor", vim.log.levels.WARN)
		return
	end

	local lines = M.build_functional_options_constructor(struct)
	util.insert_lines(bufnr, struct.end_row, lines)

	vim.schedule(function()
		util.format_buffer(bufnr)
	end)

	util.notify("Generated functional options constructor for " .. struct.name)
end

--- Build functional options pattern constructor.
---@param struct table Struct info
---@return string[] Lines of code
function M.build_functional_options_constructor(struct)
	local lines = {}
	local struct_name = struct.name
	local opt_type = struct_name .. "Option"
	local receiver = util.receiver_name(struct_name)

	-- Option type definition
	table.insert(lines, "")
	table.insert(lines, string.format("// %s is a functional option for %s.", opt_type, struct_name))
	table.insert(lines, string.format("type %s func(*%s)", opt_type, struct_name))
	table.insert(lines, "")

	-- Generate option functions for each field
	for _, field in ipairs(struct.fields) do
		if not field.embedded then
			for _, name in ipairs(field.names) do
				local func_name = "With" .. util.export_name(name)
				-- [[ FIX APPLIED HERE ]] --
				local param_name = to_camel_case(name)

				table.insert(lines, string.format("// %s sets the %s field.", func_name, name))
				table.insert(
					lines,
					string.format("func %s(%s %s) %s {", func_name, param_name, field.type_str, opt_type)
				)
				table.insert(lines, string.format("\treturn func(%s *%s) {", receiver, struct_name))
				table.insert(lines, string.format("\t\t%s.%s = %s", receiver, name, param_name))
				table.insert(lines, "\t}")
				table.insert(lines, "}")
				table.insert(lines, "")
			end
		end
	end

	-- Constructor function
	table.insert(lines, string.format("// New%s creates a new %s with the given options.", struct_name, struct_name))
	table.insert(lines, string.format("func New%s(opts ...%s) *%s {", struct_name, opt_type, struct_name))
	table.insert(lines, string.format("\t%s := &%s{}", receiver, struct_name))
	table.insert(lines, "\tfor _, opt := range opts {")
	table.insert(lines, string.format("\t\topt(%s)", receiver))
	table.insert(lines, "\t}")
	table.insert(lines, string.format("\treturn %s", receiver))
	table.insert(lines, "}")

	return lines
end

return M
