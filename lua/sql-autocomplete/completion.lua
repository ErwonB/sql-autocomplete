local utils = require('sql-autocomplete.utils')
local regex = require('sql-autocomplete.regex')
local ts = require('sql-autocomplete.ts')
local config = require('sql-autocomplete.config')

local M = {}


--- Analyzes SQL context around the cursor to determine completion type and relevant tables or databases.
--- @return table A context table containing completion type and metadata.
local function analyze_sql_context()
    local context
    local buf = vim.api.nvim_get_current_buf()
    local completion_mode = config.options.completion_mode

    local ok, parser = pcall(vim.treesitter.get_parser, buf, 'sql')
    if not ok or not parser or completion_mode == 'regex' then
        context = regex.analyze_sql_context()
    else
        context = ts.analyze_sql_context()
    end

    return context or {}
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
        local context = analyze_sql_context()

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
            local candidate_entries

            if context.alias_prefix and context.alias_prefix ~= "" then
                candidate_entries = vim.tbl_filter(function(item)
                    return string.upper(item.alias) == string.upper(context.alias_prefix)
                end, context.buffer_fields)
            else
                candidate_entries = context.buffer_fields
            end

            local seen_lists = {}
            local unique_field_lists = {}

            for _, entry in ipairs(candidate_entries) do
                local list = entry.field_list
                if not seen_lists[list] then
                    seen_lists[list] = true
                    table.insert(unique_field_lists, list)
                end
            end

            local seen_fields = {}
            local final_flat_list = {}

            for _, list in ipairs(unique_field_lists) do
                for _, field_name in ipairs(list) do
                    if not seen_fields[field_name] then
                        seen_fields[field_name] = true
                        table.insert(final_flat_list, field_name)
                    end
                end
            end

            res = res or {}
            vim.list_extend(res, final_flat_list)
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
        local context = analyze_sql_context()

        local items = {}
        local res

        if context.type == 'columns' then
            if context.alias_prefix then
                context.tables = vim.tbl_filter(function(item)
                    return item.alias == string.upper(context.alias_prefix)
                end, context.tables)
            end
            res = utils.get_columns(context.tables)
            local candidate_entries

            if context.alias_prefix and context.alias_prefix ~= "" then
                candidate_entries = vim.tbl_filter(function(item)
                    return string.upper(item.alias) == string.upper(context.alias_prefix)
                end, context.buffer_fields)
            else
                candidate_entries = context.buffer_fields
            end

            local seen_lists = {}
            local unique_field_lists = {}

            for _, entry in ipairs(candidate_entries) do
                local list = entry.field_list
                if not seen_lists[list] then
                    seen_lists[list] = true
                    table.insert(unique_field_lists, list)
                end
            end

            local seen_fields = {}
            local final_flat_list = {}

            for _, list in ipairs(unique_field_lists) do
                for _, field_name in ipairs(list) do
                    if not seen_fields[field_name] then
                        seen_fields[field_name] = true
                        table.insert(final_flat_list, field_name)
                    end
                end
            end

            res = res or {}
            vim.list_extend(res, final_flat_list)
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
