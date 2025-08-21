local utils = require('utils')

local M = {}

-- Function to get text before the cursor until an empty line or semicolon
local function get_text_before_cursor()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line = cursor[1]
    local col = cursor[2]
    local text_before = {}

    -- Add the text from the current line before the cursor
    local current_line = vim.api.nvim_get_current_line()
    table.insert(text_before, string.lower(current_line:sub(1, col)))

    while line > 1 do
        line = line - 1
        current_line = vim.api.nvim_buf_get_lines(0, line - 1, line, false)[1]
        if current_line == "" or current_line:match(";") then
            break
        end
        table.insert(text_before, 1, string.lower(current_line))
    end

    -- Join the collected lines in reverse order
    return table.concat(text_before, " "):match("^%s*(.-)%s*$") -- Trim whitespace
end

-- Function to get text after the cursor until an empty line or semicolon
local function get_text_after_cursor()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line = cursor[1]
    local col = cursor[2]
    local text_after = ""

    -- Add the text from the current line after the cursor
    local current_line = vim.api.nvim_get_current_line()
    text_after = text_after .. " " .. current_line:sub(col + 1)

    while line < vim.api.nvim_buf_line_count(0) and not current_line:match(";") do
        line = line + 1
        current_line = vim.api.nvim_buf_get_lines(0, line - 1, line, false)[1]
        if current_line == "" or current_line:match(";") then
            break
        end
        text_after = text_after .. " " .. current_line
    end

    return string.lower(text_after:match("^%s*(.-)%s*$"))
end

-- Function to be used as `completefunc`
function M.complete_func(findstart)
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
        local before_cursor = get_text_before_cursor()
        local after_cursor = get_text_after_cursor()

        -- print("Text before cursor: " .. before_cursor)
        -- print("Text after cursor: " .. after_cursor)

        local patterns = {
            'from%s*([%w_]+)%.',
            'from',
            'join%s*([%w_]+)%.',
            'join',
            'show%s+table%s+([%w_]+)%.',
            'show%s+view%s+([%w_]+)%.',
            'show%s+macro%s+([%w_]+)%.'
        }

        local db_name = nil
        local max_start = 0
        for _, pat in ipairs(patterns) do
            local start, _, cap = before_cursor:find(pat)
            if start and start > max_start then
                max_start = start
                db_name = cap
            end
        end

        -- Detect if we're between "select" and "from"
        local res_tuple_dbname_tbname = {}
        local select_from_pattern = 'select'
        local select_table_pattern = 'from%s+([%w_]+)%.([%w_]+)%s*([%w_]*)'
        local select_join_pattern = 'join%s+([%w_]+)%.([%w_]+)%s*([%w_]*)'
        local search_db_tb = after_cursor
        local contains_select = before_cursor:match(select_from_pattern)
        -- Detect if we're after where (retrieve database + tablename from before_cursor
        local contains_where = before_cursor:match("where")
        if (contains_where) then
            search_db_tb = before_cursor
        end

        local db, tb, alias = search_db_tb:match(select_table_pattern)
        if db and tb then
            table.insert(res_tuple_dbname_tbname,
                { db_name = string.upper(db), tb_name = string.upper(tb), alias = string.upper(alias) })
        end


        for l_db, l_tb, l_alias in search_db_tb:gmatch(select_join_pattern) do
            if l_db and l_tb then
                table.insert(res_tuple_dbname_tbname,
                    { db_name = string.upper(l_db), tb_name = string.upper(l_tb), alias = string.upper(l_alias) })
            end
        end

        -- print(vim.inspect(res_tuple_dbname_tbname))

        if (contains_select or contains_where) and next(res_tuple_dbname_tbname) then
            if contains_select then --check if there is an alias and match only for it in the resule sent to the function
                local a = before_cursor:match(".*%s+([%w_]+)%.$")
                if a then
                    res_tuple_dbname_tbname = vim.tbl_filter(function(item)
                        return item.alias == string.upper(a)
                    end, res_tuple_dbname_tbname)
                end
            end
            local columns = utils.get_columns(res_tuple_dbname_tbname)
            return columns
        elseif db_name then
            local tables = utils.get_tables(string.upper(db_name))
            return tables
        else
            local databases = utils.get_databases()
            return databases
        end
        return {}
    end
end

-- Set up the plugin
function M.setup()
    -- Set `completefunc` to our custom function
    vim.api.nvim_set_option_value('completefunc', 'v:lua.require\'completion\'.complete_func', { buf = 0 })

    -- Set up a keybinding to trigger completion
    vim.api.nvim_buf_set_keymap(0, 'i', '<C-x><C-u>', '<cmd>lua require("completion").trigger_fzf()<CR>',
        { noremap = true, silent = true })
end

local function handle_selection(selected, buf, row, col)
    if vim.api.nvim_buf_is_valid(buf) then
        -- Get the current line content
        local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
        -- Insert the selected text at the specified column
        local new_line = line:sub(1, col) .. table.concat(selected, "\n") .. line:sub(col + 1)
        -- Set the modified line back into the buffer
        vim.api.nvim_buf_set_lines(buf, row, row + 1, false, { new_line })

        vim.api.nvim_win_set_cursor(0, { row + 1, col + #table.concat(selected, "\n") })
    else
        print("Invalid buffer")
    end
end

-- Function to trigger fzf with the completion items
function M.trigger_fzf()
    local items = M.complete_func(0)

    -- get info for current buffer
    local buf = vim.api.nvim_get_current_buf()
    local cursor_pos = vim.api.nvim_win_get_cursor(0) -- {row, col} (1-based indexing)
    local row = cursor_pos[1] - 1                     -- Convert to 0-based indexing for nvim_buf_set_lines
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
        options = '--multi',
    })


    wrapped['sink*'] = function(selected)
        local result = {}
        for _, item in ipairs(selected) do
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

        handle_selection({ final_result }, buf, row, col)
        vim.api.nvim_feedkeys('i', 'n', false)
    end

    fzf_run(wrapped)
end

return M
