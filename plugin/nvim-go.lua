-- nvim-go.lua
-- Main plugin entry point for nvim-go
-- A comprehensive Go development plugin for NeoVim

if vim.g.loaded_nvim_go then
  return
end
vim.g.loaded_nvim_go = true

-- Ensure we're running on NeoVim 0.8+
if vim.fn.has("nvim-0.8") ~= 1 then
  vim.notify("nvim-go requires NeoVim 0.8 or higher", vim.log.levels.ERROR)
  return
end

-- Create user commands
local commands = {
  -- Struct operations
  { name = "GoGenConstructor", fn = "constructor.generate", desc = "Generate constructor for struct under cursor" },
  { name = "GoGenBuilder", fn = "builder.generate", desc = "Generate builder pattern for struct under cursor" },
  { name = "GoAddJsonTags", fn = "tags.add_json", desc = "Add JSON tags to struct fields" },
  { name = "GoAddYamlTags", fn = "tags.add_yaml", desc = "Add YAML tags to struct fields" },
  { name = "GoAddDbTags", fn = "tags.add_db", desc = "Add DB tags to struct fields" },
  { name = "GoAddValidateTags", fn = "tags.add_validate", desc = "Add validation tags to struct fields" },
  { name = "GoAddAllTags", fn = "tags.add_all", desc = "Add all common tags to struct fields" },
  { name = "GoRemoveTags", fn = "tags.remove_all", desc = "Remove all tags from struct fields" },
  { name = "GoGenGetters", fn = "accessor.generate_getters", desc = "Generate getter methods for struct" },
  { name = "GoGenSetters", fn = "accessor.generate_setters", desc = "Generate setter methods for struct" },
  { name = "GoGenGettersSetters", fn = "accessor.generate_all", desc = "Generate both getters and setters" },

  -- Interface operations
  { name = "GoImplInterface", fn = "interface.implement", desc = "Implement interface methods for struct" },
  { name = "GoExtractInterface", fn = "interface.extract", desc = "Extract interface from struct methods" },

  -- Code generation
  { name = "GoGenTest", fn = "test.generate", desc = "Generate table-driven test for function" },
  { name = "GoGenBenchmark", fn = "test.generate_benchmark", desc = "Generate benchmark for function" },
  { name = "GoGenMock", fn = "mock.generate", desc = "Generate mock for interface" },
  { name = "GoGenError", fn = "error.generate", desc = "Generate custom error type" },
  { name = "GoGenEnum", fn = "enum.generate", desc = "Generate String method for iota enum" },

  -- Struct utilities
  { name = "GoFillStruct", fn = "struct.fill", desc = "Fill struct literal with zero values" },
  { name = "GoSplitStruct", fn = "struct.split_join", desc = "Toggle struct literal single/multi line" },

  -- Receiver operations
  { name = "GoToggleReceiver", fn = "receiver.toggle", desc = "Toggle between pointer and value receiver" },

  -- Import management
  { name = "GoOrganizeImports", fn = "imports.organize", desc = "Organize imports (Uber style grouping)" },

  -- Documentation
  { name = "GoGenDoc", fn = "doc.generate", desc = "Generate Go doc comment for function/type" },

  -- Code actions (general)
  { name = "GoCodeAction", fn = "action.show", desc = "Show available Go code actions" },
}

for _, cmd in ipairs(commands) do
  vim.api.nvim_create_user_command(cmd.name, function(opts)
    local ok, mod = pcall(require, "nvim-go." .. cmd.fn:match("^[^.]+"))
    if not ok then
      vim.notify("Failed to load module: " .. cmd.fn, vim.log.levels.ERROR)
      return
    end
    local fn_name = cmd.fn:match("%.(.+)$")
    if mod[fn_name] then
      mod[fn_name](opts)
    else
      vim.notify("Function not found: " .. cmd.fn, vim.log.levels.ERROR)
    end
  end, { desc = cmd.desc, range = true })
end

-- Setup autocommands for Go files
vim.api.nvim_create_augroup("NvimGo", { clear = true })

vim.api.nvim_create_autocmd("FileType", {
  group = "NvimGo",
  pattern = "go",
  callback = function(args)
    -- Set buffer-local keymaps if user enabled them
    local config = require("nvim-go.config").get()
    if config.keymaps.enabled then
      require("nvim-go.keymaps").setup_buffer(args.buf)
    end
  end,
})
