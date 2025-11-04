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

function M.analyze_sql_context()
    local context              = {}
    local before_cursor        = get_text_before_cursor()
    local after_cursor         = get_text_after_cursor()
    -- Pattern to find tables/views from 'from' and 'join' clauses, capturing db, table, and alias
    local table_clause_pattern = '[(from|join)]%s+([%w_]+)%.([%w_]+)%s*([%w_]*)'

    local contains_select      = before_cursor:match('select')
    local contains_where       = before_cursor:match('where') or before_cursor:match('order%s+by')

    local search_text          = contains_where and before_cursor or after_cursor

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

return M
