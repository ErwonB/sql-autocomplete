local config = require('sql-autocomplete.config')
local M = {}

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
local function split_data_db_file()
    local input_filename = config.options.data_dir .. "/data_tmp.csv"
    local data_files_dir = config.options.data_dir .. "/" .. config.options.data_completion_dir
    local summary_filename = data_files_dir .. "/data.csv"

    local file_handles = {}
    local unique_dbs = {}

    local input_file = io.open(input_filename, "r")
    if not input_file then
        return vim.notify("Error: Could not open the input file: " .. input_filename, vim.log.levels.ERROR)
    end

    for line in input_file:lines() do
        local db, rest = line:match("([^,]+),(.*)")

        if db and rest then
            local handle = file_handles[db]

            if not handle then
                handle = io.open(data_files_dir .. "/" .. db .. ".csv", "w")
                file_handles[db] = handle
                unique_dbs[db] = true
            end

            if handle then
                handle:write((rest or "") .. "\n")
            else
                return vim.notify("File handle is nil. Cannot write to file.", vim.log.levels.ERROR)
            end
        end
    end
    input_file:close()

    for _, handle in pairs(file_handles) do
        handle:close()
    end

    local summary_file = io.open(summary_filename, "w")
    if summary_file then
        for db_name in pairs(unique_dbs) do
            summary_file:write(db_name .. "\n")
        end
        summary_file:close()
    else
        return vim.notify("Error: Could not open the summary file for writing: " .. summary_filename,
            vim.log.levels.ERROR)
    end
end

--- Retrieves a list of available databases from a summary CSV file.
--- @return table | nil A list of database names.
function M.get_databases()
    local data_files_dir = config.options.data_dir .. "/" .. config.options.data_completion_dir
    local db_file = data_files_dir .. "/data.csv"
    local input_file = io.open(db_file, "r")
    if not input_file then
        return vim.notify("Error: Could not open the input file: " .. db_file .. "\nBe sure to run TDSync command first",
            vim.log.levels.ERROR)
    end

    local databases = {}
    for line in input_file:lines() do
        table.insert(databases, line)
    end

    return databases
end

--- Retrieves a list of unique tables from a database-specific CSV file.
--- @param database string The name of the database.
--- @return table | nil A list of table names.
function M.get_tables(database)
    local data_files_dir = config.options.data_dir .. "/" .. config.options.data_completion_dir
    local db_file = data_files_dir .. "/" .. database .. ".csv"
    local input_file = io.open(db_file, "r")
    if not input_file then
        return vim.notify("Error: Could not open the input file: " .. db_file .. "\nBe sure to run TDSync command first",
            vim.log.levels.ERROR)
    end

    local unique_tables = {}
    local tables = {}
    for line in input_file:lines() do
        local tb = line:match('([^,]+)')
        if not unique_tables[tb] then
            table.insert(tables, tb)
            unique_tables[tb] = true
        end
    end
    return tables
end

--- Retrieves a list of unique columns for specified tables in their respective databases.
--- @param table_db_tb table A list of tables with associated database names (e.g., { db_name = "db", tb_name = "table" }).
--- @return table | nil A list of column names.
function M.get_columns(table_db_tb)
    local data_files_dir = config.options.data_dir .. "/" .. config.options.data_completion_dir
    local unique_columns = {}
    local columns = {}
    for _, item in ipairs(table_db_tb) do
        local db_file = data_files_dir .. "/" .. item.db_name .. ".csv"
        local input_file = io.open(db_file, "r")
        if not input_file then
            return vim.notify(
                "Error: Could not open the input file: " .. db_file .. "\nBe sure to run TDSync command first",
                vim.log.levels.ERROR)
        end

        for line in input_file:lines() do
            local tb, field = line:match('([^,]+),([^,]+)')
            if tb == item.tb_name then
                field = field:gsub("%s+$", "")
                if not unique_columns[field] then
                    table.insert(columns, field)
                    unique_columns[field] = true
                end
            end
        end
    end

    return columns
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
    local pwd = user and "\\$tdwallet(" .. user .. ")" or ""
    local tdpid = config.options.tdpid
    local tpt_script = config.options.tpt_script

    local data_tmp = config.options.data_dir

    local ok, msg = M.check_executables({ 'tbuild' })
    if not ok then
        return vim.notify(msg, vim.log.levels.ERROR)
    end

    if not user or not tdpid or not tpt_script then
        return vim.notify("Missing TD env variables", vim.log.levels.ERROR)
    end

    local tbuild_command = "tbuild -f " ..
        tpt_script ..
        " -u \"user='" .. user .. "', pwd='" .. pwd .. "', tdpid='" .. tdpid .. "', data_path='" .. data_tmp .. "'\""

    local data_tmp_file = data_tmp .. "/data_tmp.csv"
    M.remove_files(data_tmp_file)
    local tpt_result = vim.fn.system(tbuild_command)
    local exit_code = vim.v.shell_error
    if exit_code ~= 0 then
        return vim.notify("tbuild command failed : " .. tpt_result, vim.log.levels.ERROR)
    end

    split_data_db_file()
    remove_files(data_tmp_file)
end

return M
