local utils = require('utils')

local M = {}

-- Function to be used as `completefunc`
function M.complete_func(findstart, base)
  if findstart == 1 then
    -- Return the start position of the word to be completed
    local line = vim.api.nvim_get_current_line()
    local cursor_pos = vim.api.nvim_win_get_cursor(0)
    local col = cursor_pos[2]
    while col > 0 and line:sub(col, col):match('%w') do
      col = col - 1
    end
    return col
  else
    -- Return the list of completion items
    local cursor_pos = vim.api.nvim_win_get_cursor(0)
    local line = vim.api.nvim_get_current_line()
    local before_cursor = line:sub(1, cursor_pos[2])
    local after_cursor = line:sub(cursor_pos[2] + 1)

    -- Detect if we're after "select * from db1."
    local db_from_pattern = 'from%s+([%w_]+)%.$'
    local db_join_pattern = 'join%s+([%w_]+)%.$'
    local db_show_table = 'show%s+table%s+([%w_]+)%.$'
    local db_show_view = 'show%s+view%s+([%w_]+)%.$'
    local db_show_macro = 'show%s+macro%s+([%w_]+)%.$'
    local db_name = before_cursor:match(db_from_pattern) or before_cursor:match(db_join_pattern) or before_cursor:match(db_show_table) or before_cursor:match(db_show_view) or before_cursor:match(db_show_macro)

    if db_name then
      -- Fetch tables for the database
      local tables = utils.get_tables(db_name)
      return tables
    else
      -- Detect if we're between "select" and "from"
      local select_from_pattern = 'select'
      local select_table_pattern = 'from%s+([%w_]+)%.([%w_]+)'
      local contains_select = before_cursor:match(select_from_pattern)
      local dbname, tbname = after_cursor:match(select_table_pattern)


      if contains_select and dbname and tbname then
          local columns = utils.get_columns(dbname, tbname)
          return columns
      else
        local databases = utils.get_databases()
        return databases
      end
    end
    return {}
  end
end

-- Set up the plugin
function M.setup()
  -- Set `completefunc` to our custom function
  vim.api.nvim_buf_set_option(0, 'completefunc', 'v:lua.require\'completion\'.complete_func')

  -- Set up a keybinding to trigger completion
  vim.api.nvim_buf_set_keymap(0, 'i', '<C-x><C-u>', '<cmd>lua require("completion").trigger_fzf()<CR>', { noremap = true, silent = true })
end

local function handle_selection(selected, buf, row, col)

    if vim.api.nvim_buf_is_valid(buf) then
            -- Get the current line content
        local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
        -- Insert the selected text at the specified column
        local new_line = line:sub(1, col) .. table.concat(selected, "\n") .. line:sub(col + 1)
        -- Set the modified line back into the buffer
        vim.api.nvim_buf_set_lines(buf, row, row + 1, false, { new_line })

        -- Optionally, move the cursor to the end of the inserted text
        vim.api.nvim_win_set_cursor(0, { row + 1, col + #table.concat(selected, "\n") })
    else
      print("Invalid buffer")
    end
end

-- Function to trigger fzf with the completion items
function M.trigger_fzf()
  local items = M.complete_func(0, '')

  -- get info for current buffer
  local buf = vim.api.nvim_get_current_buf()
  local cursor_pos = vim.api.nvim_win_get_cursor(0) -- {row, col} (1-based indexing)
  local row = cursor_pos[1] - 1 -- Convert to 0-based indexing for nvim_buf_set_lines
  local col = cursor_pos[2]
  -- Use fzf to select from the list
  local fzf_run = vim.fn['fzf#run']
local fzf_wrap = vim.fn['fzf#wrap']

local wrapped = fzf_wrap({
  source = items,
   window = {
   width = 0.5,
   height = 0.4,
 },
  options = '--multi'
})


wrapped['sink*'] = function(selected)
    local result = {}
  for i, item in ipairs(selected) do
    if type(item) == "string" then
      item = vim.split(item, "\n")
    end
    item = table.concat(item, "\n")
    table.insert(result, item)
  end

  table.remove(result, 1)

  local final_result
  if #result > 1 then
    final_result = table.concat(result, ", ")
  else
    final_result = result[1]
  end

  handle_selection({final_result}, buf, row, col)
  vim.api.nvim_feedkeys('i', 'n', false)

end

fzf_run(wrapped)

end

return M
