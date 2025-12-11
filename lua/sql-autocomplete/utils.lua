local config = require('sql-autocomplete.config')
local M = {}

local Schema = {
    cache = {}
}

--- Safely removes one or more files.
--- @param ... string One or more file paths to delete.
local function remove_files(...)
    for _, file in ipairs({ ... }) do
        if vim.fn.filereadable(file) == 1 then
            vim.fn.delete(file)
        end
    end
end

--- Splits a temporary CSV file into per-database files and generates a summary file.
--- @return nil
local function split_data_db_file_to_lua()
    local input_filename = config.options.data_dir .. "/data_tmp.csv"
    local data_files_dir = config.options.data_dir .. "/" .. config.options.data_completion_dir
    local summary_filename = data_files_dir .. "/data.lua"

    -- Ensure output directory exists
    local function ensure_dir(path)
        if vim.fn.isdirectory(path) == 0 then
            vim.fn.mkdir(path, "p")
        end
    end
    ensure_dir(data_files_dir)

    local input_file = io.open(input_filename, "r")
    if not input_file then
        return vim.notify("Error: Could not open the input file: " .. input_filename, vim.log.levels.ERROR)
    end

    -- Helpers
    local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
    local function escape_lua_string(s)
        s = s:gsub("\\", "\\\\"):gsub('"', '\\"')
        return s
    end
    local function add_unique(list, value)
        for _, v in ipairs(list) do if v == value then return end end
        table.insert(list, value)
    end
    local function sorted_keys(tbl)
        local keys = {}
        for k in pairs(tbl) do table.insert(keys, k) end
        table.sort(keys)
        return keys
    end

    -- Accumulators
    local per_db = {}     -- db -> table -> {columns}
    local unique_dbs = {} -- db -> true

    -- Parse lines
    for raw in input_file:lines() do
        local line = trim(raw or "")
        if line ~= "" then
            local parts = {}
            for token in line:gmatch("([^,]+)") do
                table.insert(parts, trim(token))
            end
            if #parts >= 3 then
                local db, tbl, col = parts[1], parts[2], parts[3]
                per_db[db] = per_db[db] or {}
                per_db[db][tbl] = per_db[db][tbl] or {}
                add_unique(per_db[db][tbl], col)
                unique_dbs[db] = true
            else
                vim.notify("Warning: Malformed line: " .. line, vim.log.levels.WARN)
            end
        end
    end
    input_file:close()

    -- Write per-db files
    for db_name, tables in pairs(per_db) do
        local db_filename = data_files_dir .. "/" .. db_name .. ".lua"
        local is_table = {}
        table.insert(is_table, "is_table = {")
        local f = io.open(db_filename, "w")
        if f then
            f:write("-- Auto-generated. Do not edit.\n")
            f:write("return {\n")
            for _, tname in ipairs(sorted_keys(tables)) do
                table.insert(is_table, string.format('  ["%s"] = true,', escape_lua_string(tname)))
                local cols = tables[tname]
                table.sort(cols)
                f:write(string.format('  ["%s"] = {', escape_lua_string(tname)))
                for i, c in ipairs(cols) do
                    f:write(string.format(' "%s"%s', escape_lua_string(c), i < #cols and "," or ""))
                end
                f:write(" },\n")
            end
            table.insert(is_table, "}")
            f:write(table.concat(is_table, "\n"))
            f:write("}\n")
            f:close()
        else
            vim.notify("Error: Could not write file: " .. db_filename, vim.log.levels.ERROR)
        end
    end

    -- Write summary file
    local summary_file = io.open(summary_filename, "w")
    if summary_file then
        summary_file:write("-- Auto-generated. Do not edit.\n")
        summary_file:write("return {\n")
        for _, db_name in ipairs(sorted_keys(unique_dbs)) do
            summary_file:write(string.format('  ["%s"] = true,\n', escape_lua_string(db_name)))
        end
        summary_file:write("}\n")
        summary_file:close()
    else
        vim.notify("Error: Could not write summary file: " .. summary_filename, vim.log.levels.ERROR)
    end
end

local function load_databases(summary_file)
    if not Schema.cache.db then
        Schema.cache.db = assert(dofile(summary_file))
    end
end

--- Return true if db_name is in the db file, false otherwise
--- @return boolean db_name is present.
function M.is_a_db(db_name)
    local data_files_dir = config.options.data_dir .. "/" .. config.options.data_completion_dir
    local summary_file = data_files_dir .. "/data.lua"
    if vim.fn.filereadable(summary_file) == 0 then return false end
    if not Schema.cache.db then
        load_databases(summary_file)
    end
    return Schema.cache.db[db_name:upper()]
end

--- Retrieves a list of available databases from a summary CSV file.
--- @return table | nil A list of database names.
function M.get_databases()
    local data_files_dir = config.options.data_dir .. "/" .. config.options.data_completion_dir
    local summary_file = data_files_dir .. "/data.lua"
    if vim.fn.filereadable(summary_file) == 0 then return nil end
    if not Schema.cache.db then
        load_databases(summary_file)
    end

    local filter_db = config.options.filter_db
    local databases = {}
    local want_all = (filter_db == nil) or (filter_db == "")
    local needle = ""
    if not want_all then
        needle = filter_db:upper()
    end

    for db_name, _ in pairs(Schema.cache.db or {}) do
        if want_all then
            table.insert(databases, db_name)
        else
            if string.find(db_name:upper(), needle, 1, true) then
                table.insert(databases, db_name)
            end
        end
    end

    return databases
end

local function load_tables(db_file, db)
    if not Schema.cache.tb then
        Schema.cache.tb = {}
    end
    if not Schema.cache.tb[db] then
        Schema.cache.tb[db] = assert(dofile(db_file))
    end
end

--- Return true if db_name is a the db files, false otherwise
--- @return boolean database + tablename is present.
function M.is_a_table(database, tablename)
    local data_files_dir = config.options.data_dir .. "/" .. config.options.data_completion_dir
    local db = database:gsub("%s+", ""):upper()
    local tb = tablename:gsub("%s+", ""):upper()
    local db_file = data_files_dir .. "/" .. db .. ".lua"

    if vim.fn.filereadable(db_file) == 0 then return false end

    load_tables(db_file, db)
    return Schema.cache.tb[db].is_table[tb]
end

--- Retrieves a list of unique tables from a database-specific CSV file.
--- @param database string The name of the database.
--- @return table | nil A list of table names.
function M.get_tables(database)
    local data_files_dir = config.options.data_dir .. "/" .. config.options.data_completion_dir
    local db = database:gsub("%s+", ""):upper()
    local db_file = data_files_dir .. "/" .. db .. ".lua"

    if vim.fn.filereadable(db_file) == 0 then return nil end

    load_tables(db_file, db)

    local tables = {}
    for tb, _ in pairs(Schema.cache.tb[db].is_table or {}) do
        table.insert(tables, tb)
    end
    return tables
end

--- @return boolean col exists
function M.is_a_column(database, tablename, columnname)
    local data_files_dir = config.options.data_dir .. "/" .. config.options.data_completion_dir
    local db = database:gsub("%s+", ""):upper()
    local tb = tablename:gsub("%s+", ""):upper()
    local col = columnname:gsub("%s+", ""):upper()
    local db_file = data_files_dir .. "/" .. db .. ".lua"

    if vim.fn.filereadable(db_file) == 0 then return false end

    load_tables(db_file, db)
    for _, c in ipairs(Schema.cache.tb[db][tb] or {}) do
        if c:upper() == col then
            return true
        end
    end
    return false
end

function M.get_columns(table_db_tb)
    local data_files_dir = config.options.data_dir .. "/" .. config.options.data_completion_dir
    local seen = {}
    local acc = {}
    for _, item in ipairs(table_db_tb or {}) do
        if item and item.db_name and item.tb_name then
            local db_file = data_files_dir .. "/" .. item.db_name .. ".lua"

            if vim.fn.filereadable(db_file) == 0 then goto continue end

            load_tables(db_file, item.db_name)

            for _, col in ipairs(Schema.cache.tb[item.db_name][item.tb_name] or {}) do
                if col ~= "" and not seen[col] then
                    seen[col] = true
                    table.insert(acc, col)
                end
            end
        end
        ::continue::
    end

    return acc
end

--- Checks if required external commands are executable.
--- @param commands table A list of command names to check (e.g., {'rg', 'bat'}).
--- @return boolean, string True if all exist, otherwise false and an error message.
function M.check_executables(commands)
    for _, cmd in ipairs(commands) do
        if vim.fn.executable(cmd) == 0 then
            return false, string.format('Error: %s is not installed or not in your PATH.', cmd) --
        end
    end
    return true, ""
end

--- Runs a Teradata export script and processes the resulting data into structured files.
--- @return nil
function M.export_db_data()
    local user = config.options.user
    local tdpid = config.options.tdpid
    local logon_mech = config.options.log_mech
    local tpt_script = config.options.tpt_script

    local data_tmp = config.options.data_dir

    local ok, msg = M.check_executables({ 'tbuild' })
    if not ok then
        return vim.notify(msg, vim.log.levels.ERROR)
    end

    if not user or not tdpid or not tpt_script or not logon_mech then
        return vim.notify("Missing TD env variables", vim.log.levels.ERROR)
    end

    local tbuild_command = "tbuild -f " ..
        tpt_script ..
        " -u \"user='" ..
        user .. "', logon_mech='" .. logon_mech .. "', tdpid='" .. tdpid .. "', data_path='" .. data_tmp .. "'\""

    local data_tmp_file = data_tmp .. "/data_tmp.csv"
    remove_files(data_tmp_file)
    local tpt_result = vim.fn.system(tbuild_command)
    local exit_code = vim.v.shell_error
    if exit_code ~= 0 then
        return vim.notify("tbuild command failed : " .. tpt_result, vim.log.levels.ERROR)
    end

    split_data_db_file_to_lua()
    remove_files(data_tmp_file)
end

return M
