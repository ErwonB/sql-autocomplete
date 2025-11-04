local utils = require('sql-autocomplete.utils')

local M = {}

--helper in here for now, to move in after/plugin/ts.lua maybe ?
local function is_last_child(node)
    if not node then return false end
    local parent = node:parent()
    if not parent then return false end
    -- Use all children (not just named) so this works for anonymous tokens too
    local count = parent:child_count()
    if count == 0 then return false end
    return parent:child(count - 1) == node
end


-- Any-variant: at least ONE captured node must be a last child
vim.treesitter.query.add_predicate("any-last?", function(match, _, _, pred)
    local cap = match[pred[2]]
    if cap == nil then return false end

    if type(cap) == "table" then
        for _, n in ipairs(cap) do
            if is_last_child(n) then return true end
        end
        return false
    else
        return is_last_child(cap)
    end
end, { force = true })

local function has_ancestor(node, ancestor_type)
    if not node or not ancestor_type then return false end
    local parent = node:parent()
    while parent do
        if parent:type() == ancestor_type then return true end
        parent = parent:parent()
    end
    return false
end

vim.treesitter.query.add_predicate("not-has-ancestor?", function(match, _, _, pred)
    local cap = match[pred[2]]
    if cap == nil then return true end -- If no capture, consider it as not having (true for negation)

    local ancestor_type = pred[3]
    if not ancestor_type then return true end

    if type(cap) == "table" then
        for _, n in ipairs(cap) do
            if has_ancestor(n, ancestor_type) then return false end
        end
        return true
    else
        return not has_ancestor(cap, ancestor_type)
    end
end, { force = true })

--- end ts helper


local Q = {
    has_sel_or_dml = vim.treesitter.query.parse("sql", [[
    [(delete) (keyword_delete)
     (update) (keyword_update)
     (insert) (keyword_insert)
     (select) (keyword_select)
     (keyword_show) (keyword_merge)
     (from) (keyword_from)] @sel
  ]]),
    has_where = vim.treesitter.query.parse("sql", [[
    [(where) (keyword_where) (order_by)] @where
  ]]),
    has_error = vim.treesitter.query.parse("sql", [[
    (ERROR) @error
  ]]),
    has_last_from = vim.treesitter.query.parse("sql",
        [[([(from) (join) (keyword_from) (keyword_join)] @from (#any-last? @from))]]),
    subq_with_alias = vim.treesitter.query.parse("sql", [[
    (relation
      (subquery) @subquery
      (keyword_as)?
      alias: (identifier)? @subquery_alias
    )
  ]]),
    select_expression = vim.treesitter.query.parse("sql", [[
  ((select_expression
     (term
       alias: (identifier) @col) @item))

  ((select_expression
     (term
       value: (field
         name: (identifier) @col)) @item))

]]),
    relation = vim.treesitter.query.parse("sql", [[
    (
        (relation) @rel
      (#not-has-ancestor? @rel "subquery")
    )
    ]]),
    obj_ref = vim.treesitter.query.parse("sql", [[
(
  (object_reference) @obj
  (#not-has-ancestor? @obj "subquery")
)
]]),


}

local function node_rows(n)
    local sr, _, er, _ = n:range()
    return sr, er + 1
end

local function any_capture(query, node, bufnr, start_row, end_row)
    for _ in query:iter_captures(node, bufnr, start_row, end_row) do
        return true
    end
    return false
end

---
--- Gets the character immediately before the cursor position.
--- @return string|nil The previous character, or nil if at buffer start.
---
local function get_prev_char()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local row_1, col_0 = cursor[1], cursor[2]

    -- Get the line where cursor is
    local line = vim.api.nvim_buf_get_lines(0, row_1 - 1, row_1, false)[1]
    if not line then
        return nil
    end

    return line:sub(col_0, col_0)
end

---
--- Finds the enclosing statement node for a given node.
--- If the node is not inside a statement, finds the immediately preceding statement *only if*
--- that preceding statement is not followed immediately by a semicolon node.
--- @param node table The starting Tree-sitter node.
--- @param bufnr number The buffer number (defaults to 0).
--- @param cursor_row number the row number of the current cursor position
--- @return table|nil The enclosing or relevant preceding statement node, or nil.
---
local function get_enclosing_or_relevant_preceding_statement(node, bufnr, cursor_row)
    bufnr = bufnr or 0
    if not node then return nil end

    local current = node
    local root_node = nil
    -- Get the start position (row, col) of the node containing the cursor
    local original_node_start_row, _, _, _ = node:start()
    original_node_start_row = math.max(original_node_start_row, cursor_row)

    -- 1. Try to find the enclosing statement by going up the tree
    while current do
        local ntype = current:type()
        if ntype == 'statement' then
            return current
        end
        if ntype == 'program' then
            root_node = current
            break
        end
        local parent = current:parent()
        if not parent then
            if ntype == 'program' then root_node = current end
            break
        end
        current = parent
    end

    -- 2. If no enclosing statement found, but we identified the program root
    if root_node then
        local prev_type = nil
        for i = 0, root_node:child_count() - 1 do
            local child = root_node:child(root_node:child_count() - 1 - i)
            if not child then goto continue end

            local _, _, child_end_row, _ = child:range()

            -- Check if this child ENDS strictly before the original node STARTS
            if child_end_row <= original_node_start_row
            then
                -- If this child is a statement, remember it as the potential predecessor
                if child:type() == 'statement' and prev_type ~= ';' then
                    return child
                end
                prev_type = child:type()
            end
            ::continue::
        end
    end

    -- 3. Top node is ERROR not program so only one query not correctly parsed
    if current:type() == 'ERROR' then
        return current
    end

    -- 4. If no relevant statement found
    return nil
end


---
--- Retrieves lowercase text from the start of the statement to the cursor.
--- This is used to replicate the original logic's alias prefix matching.
--- @param statement_node table The enclosing statement node.
--- @return string The trimmed, lowercase text before the cursor.
---
local function get_text_before_cursor(statement_node)
    local cursor = vim.api.nvim_win_get_cursor(0)
    local cursor_row_1 = cursor[1]
    local cursor_col_0 = cursor[2]

    local start_row_0, start_col_0, _, _ = statement_node:start()

    local lines = vim.api.nvim_buf_get_lines(0, start_row_0, cursor_row_1, false)

    if #lines == 0 then
        return ""
    end

    lines[1] = lines[1]:sub(start_col_0 + 1)
    lines[#lines] = lines[#lines]:sub(1, cursor_col_0)

    return table.concat(lines, " "):match("^%s*(.-)%s*$"):lower()
end

---
--- Manual implementation of the missing 'child_by_field_name' helper.
--- @param node table The Tree-sitter node to search.
--- @param field_name string The name of the field to find.
--- @return table|nil The child node, or nil if not found.
---
local function get_child_by_field_name(node, field_name)
    if not node then
        return nil
    end
    for i = 0, node:named_child_count() - 1 do
        if node.field_name_for_child and node:field_name_for_child(i) == field_name then
            return node:named_child(i)
        end
    end
    return nil
end


---
--- Try to build parsable query with dummy field
--- @param bufnr integer buffer number
--- @param row_0 integer row position
--- @param col_0 integer col position
--- @return string modified buffer string
local function try_build_parsable_query(bufnr, row_0, col_0)
    local dummy = "a"
    local before = vim.api.nvim_buf_get_lines(bufnr, 0, row_0, false)
    local line = vim.api.nvim_buf_get_lines(bufnr, row_0, row_0 + 1, false)[1] or ""
    local line_byte_len = #line

    local prefix = vim.api.nvim_buf_get_text(bufnr, row_0, 0, row_0, col_0, {})[1] or ""
    local suffix = vim.api.nvim_buf_get_text(bufnr, row_0, col_0, row_0, line_byte_len, {})[1] or
        ""
    local after = vim.api.nvim_buf_get_lines(bufnr, row_0 + 1, -1, false)

    local parts = {}
    vim.list_extend(parts, before)
    table.insert(parts, prefix .. dummy .. suffix)
    vim.list_extend(parts, after)
    return table.concat(parts, "\n")
end

---
--- Finds all object_reference in a statement_node
--- @param statement_node table The enclosing statement node.
--- @param source integer|string The buffer number or source string for get_node_text and iter_captures. Defaults to 0.
--- @return table A list of { db_name, tb_name, alias } tables.
---
local function find_all_object_reference(statement_node, source)
    source = source or 0
    local tables = {}

    for _, obj_node, _ in Q.obj_ref:iter_captures(statement_node, source, 0, -1) do
        if not obj_node then
            goto continue
        end

        local alias_node = get_child_by_field_name(obj_node, "alias")
        if not alias_node then
            for child in obj_node:iter_children() do
                if child:type() == 'identifier' and child ~= obj_node then
                    alias_node = child
                    break
                end
            end
        end

        if obj_node then
            local _, schema_name, tbl_name = nil, nil, nil

            local db_node = get_child_by_field_name(obj_node, "database")
            local schema_node = get_child_by_field_name(obj_node, "schema")
            local tbl_node = get_child_by_field_name(obj_node, "name")

            if schema_node then
                schema_name = vim.treesitter.get_node_text(schema_node, source)
            end
            if tbl_node then
                tbl_name = vim.treesitter.get_node_text(tbl_node, source)
            end

            -- Handle implicit/unnamed fields if named fields weren't found
            if not db_node and not schema_node and not tbl_node then
                local children = {}
                for child in obj_node:iter_children() do
                    if child:type() == 'identifier' then
                        table.insert(children, child)
                    end
                end
                if #children == 1 then     -- e.g., (object_reference (identifier))
                    tbl_name = vim.treesitter.get_node_text(children[1], source)
                elseif #children == 2 then -- e.g., (object_reference (identifier) (identifier))
                    schema_name = vim.treesitter.get_node_text(children[1], source)
                    tbl_name = vim.treesitter.get_node_text(children[2], source)
                elseif #children == 3 then -- e.g., (object_reference (identifier) (identifier) (identifier))
                    schema_name = vim.treesitter.get_node_text(children[2], source)
                    tbl_name = vim.treesitter.get_node_text(children[3], source)
                end
            end

            local alias_str = alias_node and vim.treesitter.get_node_text(alias_node, source) or ""

            if schema_name and tbl_name then
                table.insert(tables, {
                    db_name = string.upper(schema_name),
                    tb_name = string.upper(tbl_name),
                    alias = string.upper(alias_str),
                })
            end
        end

        ::continue::
    end
    return tables
end

---
--- @param statement_node TSNode The enclosing statement node.
--- @param source integer|string Buffer number or source string for get_node_text/iter_* (defaults to 0).
--- @return table
local function find_all_fields_from_subquery(statement_node, source)
    source = source or 0

    local results = {}


    -- Iterate matches (grouped captures per relation/subquery)
    for _, match, _ in Q.subq_with_alias:iter_matches(statement_node, source, 0, -1) do
        local subquery_node, alias_node
        for capid, n in pairs(match) do
            local capname = Q.subq_with_alias.captures[capid]
            if capname == "subquery" then
                subquery_node = n[1]
            elseif capname == "subquery_alias" then
                alias_node = n[1]
            end
        end

        if subquery_node then
            local subquery_alias = ""
            if alias_node then
                subquery_alias = vim.treesitter.get_node_text(alias_node, source)
            end
            local fields = {}

            for _, sel_expr_match, _ in Q.select_expression:iter_matches(subquery_node, source, 0, -1) do
                local col_node
                for capid, n in pairs(sel_expr_match) do
                    local capname = Q.select_expression.captures[capid]
                    if capname == "col" then
                        col_node = n[1]
                    end
                end

                if col_node then
                    local col_name = vim.treesitter.get_node_text(col_node, source)
                    if col_name and col_name ~= "" then
                        table.insert(fields, col_name)
                    end
                end
            end

            if #fields > 0 then
                table.insert(results, { field_list = fields, alias = subquery_alias })
            end
        end
    end

    return results
end

---
--- Finds all tables and aliases within a given statement node.
--- @param statement_node table The enclosing statement node.
--- @param source integer|string The buffer number or source string for get_node_text and iter_captures. Defaults to 0.
--- @return table A list of { db_name, tb_name, alias } tables.
---
local function find_all_tables_in_scope(statement_node, source)
    source = source or 0
    local tables = {}

    for _, rel_node, _ in Q.relation:iter_captures(statement_node, source, 0, -1) do
        if not rel_node then
            goto continue
        end

        local obj_ref = nil
        for child in rel_node:iter_children() do
            if child:type() == "subquery" then
                goto continue
            end
            if child:type() == "object_reference" then
                obj_ref = child
                break
            end
        end

        local alias_node = get_child_by_field_name(rel_node, "alias")
        if not alias_node then
            -- Find the first identifier child that is not the object_reference
            for child in rel_node:iter_children() do
                if child:type() == 'identifier' and child ~= obj_ref then
                    alias_node = child
                    break
                end
            end
        end

        if obj_ref then
            local _, schema_name, tbl_name = nil, nil, nil

            local db_node = get_child_by_field_name(obj_ref, "database")
            local schema_node = get_child_by_field_name(obj_ref, "schema")
            local tbl_node = get_child_by_field_name(obj_ref, "name")

            if schema_node then
                schema_name = vim.treesitter.get_node_text(schema_node, source)
            end
            if tbl_node then
                tbl_name = vim.treesitter.get_node_text(tbl_node, source)
            end

            -- Handle implicit/unnamed fields if named fields weren't found
            if not db_node and not schema_node and not tbl_node then
                local children = {}
                for child in obj_ref:iter_children() do
                    if child:type() == 'identifier' then
                        table.insert(children, child)
                    end
                end
                if #children == 1 then     -- e.g., (object_reference (identifier))
                    tbl_name = vim.treesitter.get_node_text(children[1], source)
                elseif #children == 2 then -- e.g., (object_reference (identifier) (identifier))
                    schema_name = vim.treesitter.get_node_text(children[1], source)
                    tbl_name = vim.treesitter.get_node_text(children[2], source)
                elseif #children == 3 then -- e.g., (object_reference (identifier) (identifier) (identifier))
                    schema_name = vim.treesitter.get_node_text(children[2], source)
                    tbl_name = vim.treesitter.get_node_text(children[3], source)
                end
            end

            local alias_str = alias_node and vim.treesitter.get_node_text(alias_node, source) or ""

            if schema_name and tbl_name then
                table.insert(tables, {
                    db_name = string.upper(schema_name),
                    tb_name = string.upper(tbl_name),
                    alias = string.upper(alias_str),
                })
            end
        end

        ::continue::
    end
    return tables
end

---
--- Analyzes the SQL context at the cursor using Tree-sitter.
--- @return table The context { type, db_name, tables, alias_prefix, ... }
---
function M.analyze_sql_context()
    local bufnr = vim.api.nvim_get_current_buf()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local row_1, col_0 = cursor[1], cursor[2]
    local context = {}

    -- Get 0-indexed row, 0-indexed col for get_node()
    local cursor_pos_0 = { row_1 - 1, col_0 }
    local cursor_node = vim.treesitter.get_node({ bufnr = 0, pos = cursor_pos_0 })

    if not cursor_node then
        return { type = 'databases' }
    end -- Default

    local statement_node = get_enclosing_or_relevant_preceding_statement(cursor_node, bufnr, row_1 - 1)
    if not statement_node then
        return { type = 'databases' }
    end
    local s_sr, s_er = node_rows(statement_node)

    local cursor_error_node = nil
    for _, node, _ in Q.has_error:iter_captures(cursor_node, bufnr, 0, -1) do
        cursor_error_node = node
        break
    end

    local has_sel_or_dml = any_capture(Q.has_sel_or_dml, statement_node, bufnr, s_sr, s_er)
    if (not has_sel_or_dml) and cursor_error_node and cursor_error_node ~= statement_node then
        local e_sr, e_er = node_rows(cursor_error_node)
        has_sel_or_dml = any_capture(Q.has_sel_or_dml, cursor_error_node, bufnr, e_sr, e_er)
    end

    local has_where = false
    for _, node, _ in Q.has_where:iter_captures(statement_node, bufnr, 0, -1) do
        local s_row, s_col, _, _ = node:start()
        -- Check if the node starts before the cursor
        if s_row < row_1 - 1 or (s_row == row_1 - 1 and s_col < col_0) then
            has_where = true
            break
        end
    end
    if cursor_error_node and cursor_error_node ~= statement_node then
        for _, node, _ in Q.has_where:iter_captures(cursor_error_node, bufnr, 0, -1) do
            local s_row, s_col, _, _ = node:start()
            -- Check if the node starts before the cursor
            if s_row < row_1 - 1 or (s_row == row_1 - 1 and s_col < col_0) then
                has_where = true
                break
            end
        end
    end

    local prev_char = get_prev_char()
    if prev_char == '.' then
        local before_cursor = get_text_before_cursor(statement_node)
        local db_match = before_cursor:match("([%w_]+)%.%s*$")
        if db_match and utils.is_a_db(db_match) then
            context.type = 'tables'
            context.db_name = string.upper(db_match)
            return context
        end
    end

    -- 2. Check for Column Context
    if has_sel_or_dml or has_where then
        local has_error = false
        for _, _, _ in Q.has_error:iter_captures(statement_node, bufnr, 0, -1) do
            has_error = true
            break
        end
        if not has_error then
            context.tables = find_all_tables_in_scope(statement_node, bufnr)
            context.buffer_fields = find_all_fields_from_subquery(statement_node, bufnr)
        elseif has_sel_or_dml and statement_node then
            if has_error then
                -- Find SELECT keyword position in the statement_node
                local kw_node = nil
                for child in statement_node:iter_children() do
                    if child:type() == 'keyword_select' or child:type() == 'select' then
                        kw_node = child
                        break
                    end
                end


                if kw_node then
                    local modified_buf_text = try_build_parsable_query(bufnr, row_1 - 1, col_0)

                    -- Parse the entire modified buffer
                    local lang = "sql"
                    local parser = vim.treesitter.get_string_parser(modified_buf_text, lang)
                    local trees = parser:parse()

                    if trees and #trees > 0 then
                        local tree = trees[1]
                        local root = tree:root()

                        -- Find the statement that contains our cursor position
                        local fixed_statement_node = nil
                        local cursor_pos_in_modified = cursor_pos_0[1]

                        -- Search for statement containing cursor
                        local stmt_query = vim.treesitter.query.parse("sql", "(statement) @stmt")
                        for _, stmt_node, _ in stmt_query:iter_captures(root, modified_buf_text, 0, -1) do
                            local s_start_row, _, s_end_row, s_end_col = stmt_node:range()
                            -- Check if cursor is within this statement
                            if cursor_pos_in_modified >= s_start_row and
                                (cursor_pos_in_modified < s_end_row or
                                    (cursor_pos_in_modified == s_end_row and col_0 <= s_end_col)) then
                                fixed_statement_node = stmt_node
                                break
                            end
                        end

                        -- Fallback: use first statement if no exact match
                        if not fixed_statement_node and root:named_child_count() > 0 then
                            fixed_statement_node = root:named_child(0)
                        end

                        if fixed_statement_node and fixed_statement_node:type() == 'statement' then
                            context.tables = find_all_tables_in_scope(fixed_statement_node, modified_buf_text)
                            context.buffer_fields = find_all_fields_from_subquery(fixed_statement_node, modified_buf_text)
                        end
                    end
                end
            end
        end
        if context.tables and #context.tables == 0 and context.buffer_fields and #context.buffer_fields == 0 then
            if cursor_error_node then
                for _, _, _ in Q.has_last_from:iter_captures(cursor_error_node, bufnr, 0, -1) do
                    return { type = 'databases' }
                end
            end
            context.tables = find_all_object_reference(statement_node, bufnr)
            context.buffer_fields = find_all_fields_from_subquery(statement_node, bufnr)
        end
        if (context.tables and #context.tables > 0) or (context.buffer_fields and #context.buffer_fields > 0) then
            context.type = 'columns'
            context.is_where = has_where


            if prev_char == '.' then
                local before_cursor = get_text_before_cursor(statement_node)
                context.alias_prefix = before_cursor:match(".*%s+([%w_]+)%.$")
                if context.alias_prefix then
                    context.alias_prefix = string.upper(context.alias_prefix)
                end
            end
            return context
        end
    end

    -- 3. Default to Database Context
    context.type = 'databases'
    return context
end

return M
