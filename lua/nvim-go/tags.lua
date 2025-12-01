-- lua/nvim-go/tags.lua
-- Struct tag management for Go

local ts = require("nvim-go.treesitter")
local util = require("nvim-go.util")
local config = require("nvim-go.config")

local M = {}

--- Add JSON tags to struct fields.
---@param opts table|nil Command options
function M.add_json(opts)
  M.add_tags("json", opts)
end

--- Add YAML tags to struct fields.
---@param opts table|nil Command options
function M.add_yaml(opts)
  M.add_tags("yaml", opts)
end

--- Add DB (sqlx/gorm) tags to struct fields.
---@param opts table|nil Command options
function M.add_db(opts)
  M.add_tags("db", opts)
end

--- Add validation tags to struct fields.
---@param opts table|nil Command options
function M.add_validate(opts)
  M.add_tags("validate", opts)
end

--- Add all common tags to struct fields.
---@param opts table|nil Command options
function M.add_all(opts)
  opts = opts or {}
  local bufnr = vim.api.nvim_get_current_buf()

  local struct = ts.get_struct_at_cursor(bufnr)
  if not struct then
    util.notify("No struct found at cursor", vim.log.levels.WARN)
    return
  end

  local cfg = config.get()
  local tag_types = { "json", "yaml", "db" }

  M.apply_tags_to_struct(bufnr, struct, tag_types, cfg.tags)

  vim.schedule(function()
    util.format_buffer(bufnr)
  end)

  util.notify("Added tags to " .. struct.name)
end

--- Remove all tags from struct fields.
---@param opts table|nil Command options
function M.remove_all(opts)
  opts = opts or {}
  local bufnr = vim.api.nvim_get_current_buf()

  local struct = ts.get_struct_at_cursor(bufnr)
  if not struct then
    util.notify("No struct found at cursor", vim.log.levels.WARN)
    return
  end

  M.remove_tags_from_struct(bufnr, struct)

  vim.schedule(function()
    util.format_buffer(bufnr)
  end)

  util.notify("Removed tags from " .. struct.name)
end

--- Add specific tag type to struct fields.
---@param tag_type string Tag type (json, yaml, db, validate)
---@param opts table|nil Command options
function M.add_tags(tag_type, opts)
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

  local cfg = config.get()
  M.apply_tags_to_struct(bufnr, struct, { tag_type }, cfg.tags)

  vim.schedule(function()
    util.format_buffer(bufnr)
  end)

  util.notify("Added " .. tag_type .. " tags to " .. struct.name)
end

--- Apply tags to a struct.
---@param bufnr number Buffer number
---@param struct table Struct info
---@param tag_types string[] Tag types to add
---@param tag_config table Tag configuration
function M.apply_tags_to_struct(bufnr, struct, tag_types, tag_config)
  local lines = util.get_lines(bufnr, struct.start_row, struct.end_row + 1)

  for _, field in ipairs(struct.fields) do
    if not field.embedded and #field.names > 0 then
      local field_start, _, field_end, _ = field.node:range()

      -- Calculate line index relative to struct start
      local line_idx = field_start - struct.start_row + 1
      if line_idx >= 1 and line_idx <= #lines then
        local line = lines[line_idx]

        -- Parse existing tags
        local existing_tags = field.tag or {}

        -- Add new tags
        for _, tag_type in ipairs(tag_types) do
          local cfg = tag_config[tag_type] or { transform = "camelcase", options = {} }
          local field_name = field.names[1] -- Use first name for tag

          local tag_value = util.transform_name(field_name, cfg.transform)

          -- Add options if any
          if cfg.options and #cfg.options > 0 then
            tag_value = tag_value .. "," .. table.concat(cfg.options, ",")
          end

          existing_tags[tag_type] = tag_value
        end

        -- Build new line with tags
        local new_line = M.rebuild_field_line(line, existing_tags)
        lines[line_idx] = new_line
      end
    end
  end

  util.replace_lines(bufnr, struct.start_row, struct.end_row + 1, lines)
end

--- Remove all tags from a struct.
---@param bufnr number Buffer number
---@param struct table Struct info
function M.remove_tags_from_struct(bufnr, struct)
  local lines = util.get_lines(bufnr, struct.start_row, struct.end_row + 1)

  for _, field in ipairs(struct.fields) do
    if not field.embedded and #field.names > 0 then
      local field_start, _, _, _ = field.node:range()
      local line_idx = field_start - struct.start_row + 1

      if line_idx >= 1 and line_idx <= #lines then
        local line = lines[line_idx]
        -- Remove tag by removing backtick section
        local new_line = line:gsub("%s*`[^`]*`%s*", "")
        lines[line_idx] = new_line
      end
    end
  end

  util.replace_lines(bufnr, struct.start_row, struct.end_row + 1, lines)
end

--- Rebuild a field line with new tags.
---@param line string Original line
---@param tags table Tags to apply
---@return string New line
function M.rebuild_field_line(line, tags)
  -- Remove existing tag if any
  local base_line = line:gsub("%s*`[^`]*`%s*", "")

  -- Trim trailing whitespace
  base_line = base_line:gsub("%s+$", "")

  -- Build new tag string
  local tag_str = util.build_tag_string(tags)

  if tag_str == "" then
    return base_line
  end

  -- Check for inline comment
  local comment_start = base_line:find("//")
  if comment_start then
    local before_comment = base_line:sub(1, comment_start - 1):gsub("%s+$", "")
    local comment = base_line:sub(comment_start)
    return before_comment .. " " .. tag_str .. " " .. comment
  end

  return base_line .. " " .. tag_str
end

--- Modify a specific tag on struct fields.
---@param tag_type string Tag type to modify
---@param modifier function Function that takes tag value and returns new value
---@param opts table|nil Options
function M.modify_tag(tag_type, modifier, opts)
  opts = opts or {}
  local bufnr = vim.api.nvim_get_current_buf()

  local struct = ts.get_struct_at_cursor(bufnr)
  if not struct then
    util.notify("No struct found at cursor", vim.log.levels.WARN)
    return
  end

  local lines = util.get_lines(bufnr, struct.start_row, struct.end_row + 1)

  for _, field in ipairs(struct.fields) do
    if not field.embedded and field.tag and field.tag[tag_type] then
      local field_start, _, _, _ = field.node:range()
      local line_idx = field_start - struct.start_row + 1

      if line_idx >= 1 and line_idx <= #lines then
        local line = lines[line_idx]
        local existing_tags = field.tag

        -- Apply modifier
        existing_tags[tag_type] = modifier(existing_tags[tag_type])

        local new_line = M.rebuild_field_line(line, existing_tags)
        lines[line_idx] = new_line
      end
    end
  end

  util.replace_lines(bufnr, struct.start_row, struct.end_row + 1, lines)
end

--- Add omitempty option to JSON tags.
---@param opts table|nil Options
function M.add_omitempty(opts)
  M.modify_tag("json", function(value)
    if not value:match("omitempty") then
      return value .. ",omitempty"
    end
    return value
  end, opts)

  util.notify("Added omitempty to JSON tags")
end

--- Remove omitempty option from JSON tags.
---@param opts table|nil Options
function M.remove_omitempty(opts)
  M.modify_tag("json", function(value)
    return value:gsub(",?omitempty", ""):gsub("^,", "")
  end, opts)

  util.notify("Removed omitempty from JSON tags")
end

return M
