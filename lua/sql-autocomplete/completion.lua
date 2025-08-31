local utils = require('sql-autocomplete.utils')

local M = {}

--- Retrieves lowercase text before the cursor until an empty line or semicolon.
--- @return string The trimmed, lowercase text before the cursor.
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

--- Retrieves lowercase text after the cursor until an empty line or semicolon.
--- @return string The trimmed, lowercase text after the cursor.
local function get_text_after_cursor()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line = cursor[1]
    local col = cursor[2]

    -- Add the text from the current line after the cursor
    local lines_after = {}
    local current_line = vim.api.nvim_get_current_line()
    table.insert(lines_after, current_line:sub(col + 1))

    while line < vim.api.nvim_buf_line_count(0) and not current_line:match(";") do
        line = line + 1
        current_line = vim.api.nvim_buf_get_lines(0, line - 1, line, false)[1]
        if current_line == "" or current_line:match(";") then
            break
        end
        table.insert(lines_after, current_line)
    end

    local result_string = table.concat(lines_after, " ")
    return string.lower(result_string:match("^%s*(.-)%s*$") or "")
end

--- Analyzes SQL context around the cursor to determine completion type and relevant tables or databases.
--- @param before_cursor string Text before the cursor.
--- @param after_cursor string Text after the cursor.
--- @return table A context table containing completion type and metadata.
local function analyze_sql_context(before_cursor, after_cursor)
    local context = {}

    -- Pattern to find tables/views from 'from' and 'join' clauses, capturing db, table, and alias
    local table_clause_pattern = '[(from|join)]%s+([%w_]+)%.([%w_]+)%s*([%w_]*)'

    local contains_select = before_cursor:match('select')
    local contains_where = before_cursor:match('where')

    local search_text = contains_where and before_cursor or after_cursor

    -- Check for column completion context (between SELECT and FROM, or after WHERE)
    if contains_select or contains_where then
        context.tables = {}
        -- for db, tbl, alias in search_text:gmatch(table_clause_pattern1) .. search_text:gmatch(table_clause_pattern2) do
        for db, tbl, alias in search_text:gmatch(table_clause_pattern) do
            table.insert(context.tables, {
                db_name = string.upper(db),
                tb_name = string.upper(tbl),
                alias = string.upper(alias or ""),
            })
        end

        if #context.tables > 0 then
            context.type = 'columns'
            context.is_where = contains_where
            context.alias_prefix = before_cursor:match(".*%s+([%w_]+)%.$")
            return context
        end
    end

    local db_patterns = {
        'from%s+([%w_]+)%.',
        'from',
        'join%s*([%w_]+)%.',
        'join',
        'show%s+table%s+([%w_]+)%.',
        'show%s+view%s+([%w_]+)%.',
        'show%s+macro%s+([%w_]+)%.'
    }

    local db_name = nil
    local max_start = 0
    for _, pat in ipairs(db_patterns) do
        local start, _, cap = before_cursor:find(pat)
        if start and start > max_start then
            max_start = start
            db_name = cap
        end
    end

    if db_name then
        context.type = 'tables'
        context.db_name = string.upper(db_name)
        return context
    end

    context.type = 'databases'
    return context
end

--- Provides manual SQL completion items or the start column for completion.
--- @param findstart number Indicates whether to find the start column (1) or return completion items (0).
--- @return number | table Start column or completion result table.
function M.complete_manual(findstart)
    if findstart == 1 then
        local line = vim.api.nvim_get_current_line()
        local col = vim.api.nvim_win_get_cursor(0)[2]
        while col > 0 and line:sub(col, col):match('%w') do
            col = col - 1
        end
        return col
    else
        local before_cursor = get_text_before_cursor()
        local after_cursor = get_text_after_cursor()
        local context = analyze_sql_context(before_cursor, after_cursor)

        local items = {}
        local res
        local fzf_options = ""

        if context.type == 'columns' then
            if context.alias_prefix then
                context.tables = vim.tbl_filter(function(item)
                    return item.alias == string.upper(context.alias_prefix)
                end, context.tables)
            end
            res = utils.get_columns(context.tables)
            fzf_options = "--multi"
        elseif context.type == 'tables' then
            res = utils.get_tables(context.db_name)
        elseif context.type == 'databases' then
            res = utils.get_databases()
        end
        items = res and res or {}

        return {
            items = items,
            fzf_options = fzf_options,
            context = context,
        }
    end
end

--- Provides filtered SQL completion items based on the current context and input base.
--- @param findstart number Indicates whether to find the start column (1) or return completion items (0).
--- @param base string The base string to filter completion items.
--- @return number | table Start column or filtered completion items.
function M.complete_func(findstart, base)
    if findstart == 1 then
        local line = vim.api.nvim_get_current_line()
        local col = vim.api.nvim_win_get_cursor(0)[2]
        while col > 0 and line:sub(col, col):match('%w') do
            col = col - 1
        end
        return col
    else
        local before_cursor = get_text_before_cursor()
        local after_cursor = get_text_after_cursor()
        local context = analyze_sql_context(before_cursor, after_cursor)

        local items = {}
        local res

        if context.type == 'columns' then
            if context.alias_prefix then
                context.tables = vim.tbl_filter(function(item)
                    return item.alias == string.upper(context.alias_prefix)
                end, context.tables)
            end
            res = utils.get_columns(context.tables)
        elseif context.type == 'tables' then
            res = utils.get_tables(context.db_name)
        elseif context.type == 'databases' then
            res = utils.get_databases()
        end
        items = res and res or {}

        local filtered_items = vim.tbl_filter(function(item)
            return vim.startswith(string.lower(item), string.lower(base))
        end, items)

        return filtered_items
    end
end

--- Inserts selected FZF items into the buffer based on SQL context.
--- @param selected table List of selected completion items.
--- @param context table Context metadata for insertion.
--- @return nil
local function handle_fzf_selection(selected, context)
    if not vim.api.nvim_buf_is_valid(context.buf) or #selected == 0 then
        return
    end

    if #selected > 1 then
        table.remove(selected, 1)
    end

    local final_text
    if context.type == 'columns' then
        local alias = (context.alias_prefix and context.alias_prefix ~= "") and (context.alias_prefix .. ".") or ""
        local separator = context.is_where and " and " or ", "
        local prefixed_items = {}
        for i, item in ipairs(selected) do
            local prefix = (i == 1 and "") or alias
            table.insert(prefixed_items, prefix .. item)
        end
        final_text = table.concat(prefixed_items, separator)
    else
        final_text = table.concat(selected, "\n")
    end

    vim.api.nvim_buf_set_text(context.buf, context.start_row, context.start_col, context.end_row, context.end_col,
        { final_text })
    vim.api.nvim_win_set_cursor(0, { context.start_row + 1, context.start_col + #final_text })
    vim.api.nvim_feedkeys('i', 'n', false)
end


--- Triggers FZF-based SQL completion and handles user selection.
--- @return nil
function M.trigger_fzf()
    local cursor_pos = vim.api.nvim_win_get_cursor(0)
    local start_col = M.complete_manual(1)

    local completion_data = M.complete_manual(0)
    if not completion_data or not next(completion_data.items) then
        print("No completions found.")
        return
    end

    completion_data.context.buf = vim.api.nvim_get_current_buf()
    completion_data.context.start_row = cursor_pos[1] - 1
    completion_data.context.end_row = cursor_pos[1] - 1
    completion_data.context.start_col = start_col
    completion_data.context.end_col = cursor_pos[2]


    local fzf_config = {
        source = completion_data.items,
        options = completion_data.fzf_options,
        window = { width = 0.5, height = 0.4, border = 'rounded' },
        -- Use a lambda with a captured context for cleaner state management
        ['sink*'] = function(selected)
            handle_fzf_selection(selected, completion_data.context)
        end,
    }

    vim.fn['fzf#run'](fzf_config)
end

return M
