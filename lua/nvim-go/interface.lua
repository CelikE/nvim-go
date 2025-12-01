-- lua/nvim-go/interface.lua
-- Interface implementation and extraction for Go

local ts = require("nvim-go.treesitter")
local util = require("nvim-go.util")

local M = {}

--- Implement interface methods for a struct.
--- Prompts user for interface name if not on an interface.
---@param opts table|nil Command options
function M.implement(opts)
	opts = opts or {}
	local bufnr = vim.api.nvim_get_current_buf()

	if vim.bo[bufnr].filetype ~= "go" then
		util.notify("Not a Go file", vim.log.levels.WARN)
		return
	end

	-- First, check if cursor is on a struct
	local struct = ts.get_struct_at_cursor(bufnr)

	-- Also check if we're on an interface
	local iface = ts.get_interface_at_cursor(bufnr)

	if struct and not iface then
		-- We're on a struct, prompt for interface name
		vim.ui.input({ prompt = "Interface to implement: " }, function(input)
			if input and input ~= "" then
				M.implement_interface_for_struct(bufnr, struct, input)
			end
		end)
	elseif iface then
		-- We're on an interface, prompt for struct name
		vim.ui.input({ prompt = "Struct to implement on: " }, function(input)
			if input and input ~= "" then
				M.generate_stubs_for_interface(bufnr, iface, input)
			end
		end)
	else
		util.notify("Place cursor on a struct or interface", vim.log.levels.WARN)
	end
end

--- Generate method stubs for an interface on a struct.
---@param bufnr number Buffer number
---@param iface table Interface info
---@param struct_name string Name of struct to implement on
function M.generate_stubs_for_interface(bufnr, iface, struct_name)
	local lines = M.build_interface_stubs(iface, struct_name)

	-- Find end of file or after last function
	local line_count = vim.api.nvim_buf_line_count(bufnr)

	util.insert_lines(bufnr, line_count, lines)

	vim.schedule(function()
		util.format_buffer(bufnr)
	end)

	util.notify(string.format("Implemented %s for %s", iface.name, struct_name))
end

--- Implement a named interface for a struct.
---@param bufnr number Buffer number
---@param struct table Struct info
---@param iface_name string Interface name
function M.implement_interface_for_struct(bufnr, struct, iface_name)
	-- Try to find the interface in the current file
	local root = ts.get_root(bufnr)
	if not root then
		util.notify("Failed to parse buffer", vim.log.levels.ERROR)
		return
	end

	-- Updated query for modern tree-sitter-go:
	-- We capture 'interface_type' directly as @methods_node
	local query_string = [[
    (type_declaration
      (type_spec
        name: (type_identifier) @name
        type: (interface_type) @methods_node)) @interface
  ]]

	local query = vim.treesitter.query.parse("go", query_string)
	local iface = nil

	-- 1. Find the interface node by name
	for id, node, _ in query:iter_captures(root, bufnr, 0, -1) do
		local capture_name = query.captures[id]
		if capture_name == "name" then
			local name = vim.treesitter.get_node_text(node, bufnr)
			if name == iface_name then
				-- Found the interface declaration
				local parent = node:parent():parent() -- type_spec -> type_declaration
				local start_row, _, end_row, _ = parent:range()

				iface = {
					name = iface_name,
					node = parent,
					start_row = start_row,
					end_row = end_row,
					methods = {},
				}

				-- 2. Now find the interface_type node (@methods_node) associated with this name
				-- We search specifically within the parent scope to match the correct one
				for child_id, child_node, _ in query:iter_captures(parent, bufnr, start_row, end_row + 1) do
					if query.captures[child_id] == "methods_node" then
						-- 3. Robust Manual Parsing (Type-Agnostic)
						-- We iterate children of the interface_type directly.
						-- We do NOT check for "method_spec" type to avoid crashing on grammar changes.
						-- Instead, we look for the pattern: Name(field_identifier) -> Params(parameter_list) -> Result

						for method_node in child_node:iter_children() do
							local method = { params = {} }
							local found_name = false
							local found_params = false

							-- Inspect the components of this line
							for part in method_node:iter_children() do
								local type = part:type()

								if type == "field_identifier" and not found_name then
									method.name = vim.treesitter.get_node_text(part, bufnr)
									found_name = true
								elseif type == "parameter_list" and not found_params then
									-- Found the parameters
									method.params = ts.parse_parameter_list(part, bufnr)
									found_params = true
								elseif found_params and type ~= "comment" then
									-- Anything after parameters is the result (return type)
									-- It might be a type_identifier, parameter_list (tuple return), etc.
									method.result = vim.treesitter.get_node_text(part, bufnr)
								end
							end

							if method.name then
								table.insert(iface.methods, method)
							end
						end
					end
				end
				break
			end
		end
	end

	if iface then
		-- Methods are already a list in this approach
	end

	if not iface or #iface.methods == 0 then
		-- Interface not found in current file or has no methods, try common interfaces
		if not iface then
			-- Only notify if we didn't find the interface definition at all
			util.notify(
				string.format("Interface %s not found in file (or empty). Checking common interfaces...", iface_name),
				vim.log.levels.INFO
			)
		end

		local common_iface = M.get_common_interface(iface_name)
		if common_iface then
			iface = common_iface
		else
			if not iface then -- If we didn't find it in file AND it's not common
				util.notify("Unknown interface: " .. iface_name, vim.log.levels.ERROR)
				return
			end
			-- If we found it in file but it had no methods, we just proceed (maybe it's a marker interface)
		end
	end

	local lines = M.build_interface_stubs(iface, struct.name)

	-- [[ CHANGE: Insert at end of file instead of after struct ]]
	local line_count = vim.api.nvim_buf_line_count(bufnr)
	util.insert_lines(bufnr, line_count, lines)

	vim.schedule(function()
		util.format_buffer(bufnr)
	end)

	util.notify(string.format("Implemented %s for %s", iface_name, struct.name))
end

--- Get a common Go interface definition.
---@param name string Interface name
---@return table|nil Interface info
function M.get_common_interface(name)
	local common = {
		Stringer = {
			name = "fmt.Stringer", -- Qualified name
			methods = {
				{ name = "String", params = {}, result = "string" },
			},
		},
		["error"] = {
			name = "error",
			methods = {
				{ name = "Error", params = {}, result = "string" },
			},
		},
		Reader = {
			name = "io.Reader", -- Qualified name
			methods = {
				{
					name = "Read",
					params = { { names = { "p" }, type_str = "[]byte" } },
					result = "(n int, err error)",
				},
			},
		},
		Writer = {
			name = "io.Writer", -- Qualified name
			methods = {
				{
					name = "Write",
					params = { { names = { "p" }, type_str = "[]byte" } },
					result = "(n int, err error)",
				},
			},
		},
		Closer = {
			name = "io.Closer", -- Qualified name
			methods = {
				{ name = "Close", params = {}, result = "error" },
			},
		},
		ReadWriter = {
			name = "io.ReadWriter", -- Qualified name
			methods = {
				{
					name = "Read",
					params = { { names = { "p" }, type_str = "[]byte" } },
					result = "(n int, err error)",
				},
				{
					name = "Write",
					params = { { names = { "p" }, type_str = "[]byte" } },
					result = "(n int, err error)",
				},
			},
		},
		ReadCloser = {
			name = "io.ReadCloser", -- Qualified name
			methods = {
				{
					name = "Read",
					params = { { names = { "p" }, type_str = "[]byte" } },
					result = "(n int, err error)",
				},
				{ name = "Close", params = {}, result = "error" },
			},
		},
		WriteCloser = {
			name = "io.WriteCloser", -- Qualified name
			methods = {
				{
					name = "Write",
					params = { { names = { "p" }, type_str = "[]byte" } },
					result = "(n int, err error)",
				},
				{ name = "Close", params = {}, result = "error" },
			},
		},
		Handler = {
			name = "http.Handler", -- Qualified name
			methods = {
				{
					name = "ServeHTTP",
					params = {
						{ names = { "w" }, type_str = "http.ResponseWriter" },
						{ names = { "r" }, type_str = "*http.Request" },
					},
					result = nil,
				},
			},
		},
	}

	return common[name]
end

--- Build method stubs for implementing an interface.
---@param iface table Interface info
---@param struct_name string Struct name
---@return string[] Lines of code
function M.build_interface_stubs(iface, struct_name)
	local lines = {}
	local receiver = util.receiver_name(struct_name)

	-- Add compile-time interface check (Uber style)
	table.insert(lines, "")
	table.insert(lines, string.format("// Ensure %s implements %s.", struct_name, iface.name))
	table.insert(lines, string.format("var _ %s = (*%s)(nil)", iface.name, struct_name))

	for _, method in ipairs(iface.methods) do
		table.insert(lines, "")

		-- Build parameter string
		local param_parts = {}
		if method.params then
			for _, param in ipairs(method.params) do
				local names = table.concat(param.names or {}, ", ")
				if names ~= "" then
					table.insert(param_parts, names .. " " .. param.type_str)
				else
					table.insert(param_parts, param.type_str)
				end
			end
		end
		local param_str = table.concat(param_parts, ", ")

		-- Build return type
		local result_str = method.result or ""

		-- Doc comment
		table.insert(lines, string.format("// %s implements %s.", method.name, iface.name))

		-- Method signature
		if result_str ~= "" then
			table.insert(
				lines,
				string.format("func (%s *%s) %s(%s) %s {", receiver, struct_name, method.name, param_str, result_str)
			)
		else
			table.insert(lines, string.format("func (%s *%s) %s(%s) {", receiver, struct_name, method.name, param_str))
		end

		-- Add panic placeholder
		table.insert(lines, '\tpanic("not implemented")')
		table.insert(lines, "}")
	end

	return lines
end

--- Extract an interface from struct methods.
---@param opts table|nil Command options
function M.extract(opts)
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

	-- Find all methods for this struct
	local methods = M.find_struct_methods(bufnr, struct.name)

	if #methods == 0 then
		util.notify("No methods found for " .. struct.name, vim.log.levels.WARN)
		return
	end

	-- Prompt for interface name
	vim.ui.input({ prompt = "Interface name: ", default = struct.name .. "er" }, function(input)
		if input and input ~= "" then
			local lines = M.build_extracted_interface(input, methods)
			util.insert_lines(bufnr, struct.start_row - 1, lines)

			vim.schedule(function()
				util.format_buffer(bufnr)
			end)

			util.notify("Extracted interface " .. input)
		end
	end)
end

--- Find all methods for a struct type.
---@param bufnr number Buffer number
---@param struct_name string Struct name
---@return table[] List of method info
function M.find_struct_methods(bufnr, struct_name)
	local root = ts.get_root(bufnr)
	if not root then
		return {}
	end

	local methods = {}
	local query_string = [[
    (method_declaration
      receiver: (parameter_list
        (parameter_declaration
          type: (_) @receiver_type))
      name: (field_identifier) @name
      parameters: (parameter_list) @params
      result: (_)? @result) @method
  ]]

	local query = vim.treesitter.query.parse("go", query_string)

	for id, node, _ in query:iter_captures(root, bufnr, 0, -1) do
		local capture_name = query.captures[id]

		if capture_name == "method" then
			local method = { node = node }

			for child_id, child_node, _ in query:iter_captures(node, bufnr) do
				local child_name = query.captures[child_id]

				if child_name == "receiver_type" then
					local recv_type = vim.treesitter.get_node_text(child_node, bufnr)
					-- Check if this is our struct (with or without pointer)
					if recv_type == struct_name or recv_type == "*" .. struct_name then
						method.receiver_type = recv_type
					end
				elseif child_name == "name" then
					method.name = vim.treesitter.get_node_text(child_node, bufnr)
				elseif child_name == "params" then
					method.params = ts.parse_parameter_list(child_node, bufnr)
				elseif child_name == "result" then
					method.result = vim.treesitter.get_node_text(child_node, bufnr)
				end
			end

			-- Only include methods for our struct that are exported
			if method.receiver_type and method.name and util.is_exported(method.name) then
				table.insert(methods, method)
			end
		end
	end

	return methods
end

--- Build interface definition from extracted methods.
---@param name string Interface name
---@param methods table[] Method info list
---@return string[] Lines of code
function M.build_extracted_interface(name, methods)
	local lines = {}

	table.insert(lines, "")
	table.insert(lines, string.format("// %s defines the interface for...", name))
	table.insert(lines, string.format("type %s interface {", name))

	for _, method in ipairs(methods) do
		-- Build parameter string
		local param_parts = {}
		for _, param in ipairs(method.params or {}) do
			local names = table.concat(param.names or {}, ", ")
			if names ~= "" then
				table.insert(param_parts, names .. " " .. param.type_str)
			else
				table.insert(param_parts, param.type_str)
			end
		end
		local param_str = table.concat(param_parts, ", ")

		-- Build method signature
		if method.result then
			table.insert(lines, string.format("\t%s(%s) %s", method.name, param_str, method.result))
		else
			table.insert(lines, string.format("\t%s(%s)", method.name, param_str))
		end
	end

	table.insert(lines, "}")
	table.insert(lines, "")

	return lines
end

return M
